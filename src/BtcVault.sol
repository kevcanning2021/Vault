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

/// @title BTC Vault
/// @notice Personal, non-upgradeable ERC-4626 vault. USDC deposited here is supplied to
///         Aave v3, and the vault's share price rises as Aave interest accrues in USDC.
/// @dev    Only the owner can deposit, mint, withdraw or redeem. No fees.
contract BtcVault is ERC4626, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Smallest deposit accepted: 1 USDC (6 decimals).
    uint256 public constant MIN_DEPOSIT = 1e6;

    IAavePool public immutable POOL;
    IERC20 public immutable A_TOKEN;

    /// @notice USDC put in minus USDC taken out (floored at 0). Used to show earned yield.
    uint256 public netDeposited;

    /// @notice When true, deposits are blocked and funds sit idle in the vault (out of Aave).
    bool public exited;

    /// @notice Most USDC the vault may hold after a deposit. Owner can raise or lower it.
    uint256 public depositCap;

    event EmergencyExit(uint256 pulledFromAave);
    event Resumed(uint256 resuppliedToAave);
    event DepositCapChanged(uint256 oldCap, uint256 newCap);

    error OnlyOwner();
    error VaultExited();
    error CannotRescueVaultAssets();
    error BelowMinimumDeposit(uint256 assets, uint256 minimum);
    error AboveDepositCap(uint256 totalAfter, uint256 cap);

    constructor(IERC20 usdc, IAavePool pool, IERC20 aToken, address owner_, uint256 depositCap_)
        ERC20("BTC Vault USDC", "btcVault")
        ERC4626(usdc)
        Ownable(owner_)
    {
        POOL = pool;
        A_TOKEN = aToken;
        depositCap = depositCap_;
        emit DepositCapChanged(0, depositCap_);
        usdc.forceApprove(address(pool), type(uint256).max);
    }

    // ------------------------------------------------------------------ views

    /// @notice USDC in Aave (aUSDC grows every block) plus any idle USDC.
    function totalAssets() public view override returns (uint256) {
        return A_TOKEN.balanceOf(address(this)) + IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Interest earned so far, in USDC (6 decimals).
    function earned() external view returns (uint256) {
        uint256 total = totalAssets();
        return total > netDeposited ? total - netDeposited : 0;
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

    /// @dev Capped by the USDC Aave actually has free to lend back right now.
    function maxWithdraw(address holder) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(holder), _liquidity());
    }

    function maxRedeem(address holder) public view override returns (uint256) {
        return Math.min(super.maxRedeem(holder), _convertToShares(_liquidity(), Math.Rounding.Floor));
    }

    // ------------------------------------------------------------- owner ops

    /// @notice Pull everything out of Aave into the vault and block new deposits.
    function emergencyExit() external onlyOwner nonReentrant {
        exited = true;
        uint256 bal = A_TOKEN.balanceOf(address(this));
        uint256 pulled = bal == 0 ? 0 : POOL.withdraw(asset(), type(uint256).max, address(this));
        emit EmergencyExit(pulled);
    }

    /// @notice Undo an emergency exit: re-supply idle USDC to Aave and reopen deposits.
    function resume() external onlyOwner nonReentrant {
        exited = false;
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (idle > 0) POOL.supply(asset(), idle, address(this), 0);
        emit Resumed(idle);
    }

    /// @notice Change the deposit cap (in USDC units, 6 decimals). Lowering it never blocks withdrawals.
    function setDepositCap(uint256 newCap) external onlyOwner {
        emit DepositCapChanged(depositCap, newCap);
        depositCap = newCap;
    }

    /// @notice Recover tokens sent here by mistake. USDC and aUSDC can never be pulled this way.
    function rescue(IERC20 token, address to) external onlyOwner {
        if (address(token) == asset() || address(token) == address(A_TOKEN)) revert CannotRescueVaultAssets();
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
        POOL.supply(asset(), assets, address(this), 0);
        netDeposited += assets;
    }

    function _withdraw(address caller, address receiver, address holder, uint256 assets, uint256 shares)
        internal
        override
        nonReentrant
    {
        if (caller != owner()) revert OnlyOwner();
        uint256 idle = IERC20(asset()).balanceOf(address(this));
        if (assets > idle) POOL.withdraw(asset(), assets - idle, address(this));
        super._withdraw(caller, receiver, holder, assets, shares); // burns shares, sends USDC
        netDeposited = assets >= netDeposited ? 0 : netDeposited - assets;
    }

    /// @dev Idle USDC plus USDC sitting un-borrowed in the Aave reserve (capped at our position).
    function _liquidity() internal view returns (uint256) {
        IERC20 usdc = IERC20(asset());
        uint256 idle = usdc.balanceOf(address(this));
        uint256 inAave = A_TOKEN.balanceOf(address(this));
        uint256 reserveCash = usdc.balanceOf(address(A_TOKEN));
        return idle + Math.min(inAave, reserveCash);
    }

    /// @dev Virtual-share offset guards against share-price inflation tricks.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
