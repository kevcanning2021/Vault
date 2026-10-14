// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IAavePool} from "./interfaces/IAavePool.sol";
import {IComet} from "./interfaces/IComet.sol";

/// @title BTC Vault
/// @notice Personal, non-upgradeable ERC-4626 vault. USDC deposited here is lent out on
///         Aave v3 or Compound v3 (owner picks which), and the share price rises as interest
///         accrues in USDC.
/// @dev    Only the owner can deposit, mint, withdraw or redeem. No fees.
///         COMET may be address(0), in which case the vault is Aave-only.
contract BtcVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Venue {
        Aave,
        Compound
    }

    /// @notice Smallest deposit accepted: 1 USDC (6 decimals).
    uint256 public constant MIN_DEPOSIT = 1e6;

    IAavePool public immutable POOL;
    IERC20 public immutable A_TOKEN;
    IComet public immutable COMET;

    /// @notice Where new deposits go and where funds currently sit.
    Venue public venue;

    /// @notice USDC put in minus USDC taken out (floored at 0). Used to show earned yield.
    uint256 public netDeposited;

    /// @notice When true, deposits are blocked and funds sit idle in the vault (out of both lenders).
    bool public exited;

    /// @notice Most USDC the vault may hold after a deposit. Owner can raise or lower it.
    uint256 public depositCap;

    event EmergencyExit(uint256 pulled);
    event Resumed(uint256 resupplied);
    event DepositCapChanged(uint256 oldCap, uint256 newCap);
    event Moved(Venue from, Venue to, uint256 amount);

    error OnlyOwner();
    error VaultExited();
    error CannotRescueVaultAssets();
    error BelowMinimumDeposit(uint256 assets, uint256 minimum);
    error AboveDepositCap(uint256 totalAfter, uint256 cap);
    error CompoundNotConfigured();
    error CometAssetMismatch();
    error AlreadyThere();

    constructor(IERC20 usdc, IAavePool pool, IERC20 aToken, IComet comet, address owner_, uint256 depositCap_)
        ERC20("BTC Vault USDC", "btcVault")
        ERC4626(usdc)
        Ownable(owner_)
    {
        POOL = pool;
        A_TOKEN = aToken;
        COMET = comet;
        depositCap = depositCap_;
        emit DepositCapChanged(0, depositCap_);
        usdc.forceApprove(address(pool), type(uint256).max);
        if (address(comet) != address(0)) {
            if (comet.baseToken() != address(usdc)) revert CometAssetMismatch();
            usdc.forceApprove(address(comet), type(uint256).max);
        }
    }

    // ------------------------------------------------------------------ views

    /// @notice USDC on Aave + USDC on Compound + any idle USDC.
    function totalAssets() public view override returns (uint256) {
        return _inAave() + _inCompound() + IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Interest earned so far, in USDC (6 decimals).
    function earned() external view returns (uint256) {
        uint256 total = totalAssets();
        return total > netDeposited ? total - netDeposited : 0;
    }

    function hasCompound() public view returns (bool) {
        return address(COMET) != address(0);
    }

    /// @notice How much more USDC fits under the cap (0 when paused or not the owner).
    function maxDeposit(address receiver) public view override returns (uint256) {
        if (exited || receiver != owner()) return 0;
        uint256 total = totalAssets();
        return total >= depositCap ? 0 : depositCap - total;
    }

    function maxMint(address receiver) public view override returns (uint256) {
        return _convertToShares(maxDeposit(receiver), Math.Rounding.Floor);
    }

    /// @dev Capped by the USDC the lenders actually have free to pay back right now.
    function maxWithdraw(address holder) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(holder), _liquidity());
    }

    function maxRedeem(address holder) public view override returns (uint256) {
        return Math.min(super.maxRedeem(holder), _convertToShares(_liquidity(), Math.Rounding.Floor));
    }

    // ------------------------------------------------------------- owner ops

    /// @notice Move everything to the other lender and send future deposits there.
    function moveTo(Venue to) external onlyOwner nonReentrant {
        if (to == Venue.Compound && !hasCompound()) revert CompoundNotConfigured();
        if (to == venue) revert AlreadyThere();
        if (exited) revert VaultExited();
        Venue from = venue;
        _pullAll();
        venue = to;
        uint256 amount = IERC20(asset()).balanceOf(address(this));
        _supply(amount);
        emit Moved(from, to, amount);
    }

    /// @notice Pull everything out of both lenders into the vault and block new deposits.
    function emergencyExit() external onlyOwner nonReentrant {
        exited = true;
        uint256 before = IERC20(asset()).balanceOf(address(this));
        _pullAll();
        emit EmergencyExit(IERC20(asset()).balanceOf(address(this)) - before);
    }

    /// @notice Undo an emergency exit: re-supply idle USDC to the current lender and reopen deposits.
    function resume() external onlyOwner nonReentrant {
        exited = false;
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        _supply(idle);
        emit Resumed(idle);
    }

    /// @notice Change the deposit cap (in USDC units, 6 decimals). Lowering it never blocks withdrawals.
    function setDepositCap(uint256 newCap) external onlyOwner {
        emit DepositCapChanged(depositCap, newCap);
        depositCap = newCap;
    }

    /// @notice Recover tokens sent here by mistake. Vault funds can never be pulled this way.
    function rescue(IERC20 token, address to) external onlyOwner {
        if (address(token) == asset() || address(token) == address(A_TOKEN) || address(token) == address(COMET)) {
            revert CannotRescueVaultAssets();
        }
        token.safeTransfer(to, token.balanceOf(address(this)));
    }

    // -------------------------------------------------------------- internals

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (caller != owner()) revert OnlyOwner();
        if (exited) revert VaultExited();
        if (assets < MIN_DEPOSIT) revert BelowMinimumDeposit(assets, MIN_DEPOSIT);
        uint256 totalAfter = totalAssets() + assets;
        if (totalAfter > depositCap) revert AboveDepositCap(totalAfter, depositCap);
        super._deposit(caller, receiver, assets, shares); // pulls USDC in, mints shares
        _supply(assets);
        netDeposited += assets;
    }

    function _withdraw(address caller, address receiver, address holder, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (caller != owner()) revert OnlyOwner();
        IERC20 usdc = IERC20(asset());
        uint256 idle = usdc.balanceOf(address(this));
        if (assets > idle) {
            uint256 need = assets - idle;
            // Current lender first, then the other one (covers dust left after a move).
            need -= _take(venue, need);
            if (need > 0) need -= _take(venue == Venue.Aave ? Venue.Compound : Venue.Aave, need);
        }
        super._withdraw(caller, receiver, holder, assets, shares); // burns shares, sends USDC
        netDeposited = assets >= netDeposited ? 0 : netDeposited - assets;
    }

    function _supply(uint256 amount) internal {
        if (amount == 0) return;
        if (venue == Venue.Aave) POOL.supply(asset(), amount, address(this), 0);
        else COMET.supply(asset(), amount);
    }

    /// @dev Withdraw up to `want` from one lender. Returns what actually arrived.
    function _take(Venue v, uint256 want) internal returns (uint256 got) {
        IERC20 usdc = IERC20(asset());
        uint256 before = usdc.balanceOf(address(this));
        if (v == Venue.Aave) {
            uint256 bal = _inAave();
            if (bal == 0) return 0;
            POOL.withdraw(asset(), Math.min(want, bal), address(this));
        } else {
            uint256 bal = _inCompound();
            if (bal == 0) return 0;
            // Asking for the full balance uses Compound's "withdraw all" path to avoid 1-wei dust.
            COMET.withdraw(asset(), want >= bal ? type(uint256).max : want);
        }
        got = usdc.balanceOf(address(this)) - before;
    }

    function _pullAll() internal {
        if (_inAave() > 0) POOL.withdraw(asset(), type(uint256).max, address(this));
        if (_inCompound() > 0) COMET.withdraw(asset(), type(uint256).max);
    }

    function _inAave() internal view returns (uint256) {
        return A_TOKEN.balanceOf(address(this));
    }

    function _inCompound() internal view returns (uint256) {
        return hasCompound() ? COMET.balanceOf(address(this)) : 0;
    }

    /// @dev Idle USDC plus un-borrowed cash each lender holds (capped at our position there).
    function _liquidity() internal view returns (uint256) {
        IERC20 usdc = IERC20(asset());
        uint256 liq = usdc.balanceOf(address(this)) + Math.min(_inAave(), usdc.balanceOf(address(A_TOKEN)));
        if (hasCompound()) liq += Math.min(_inCompound(), usdc.balanceOf(address(COMET)));
        return liq;
    }

    /// @dev Virtual-share offset guards against share-price inflation tricks.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
