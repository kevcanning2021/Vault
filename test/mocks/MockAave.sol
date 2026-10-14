// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amt) external {
        _mint(to, amt);
    }
}

/// @dev aToken stand-in: holds the underlying cash, balances can be bumped to simulate interest.
contract MockAToken is ERC20 {
    address public pool;

    constructor() ERC20("Aave USDC", "aUSDC") {
        pool = msg.sender;
    }

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amt) external {
        require(msg.sender == pool, "pool");
        _mint(to, amt);
    }

    function burn(address from, uint256 amt) external {
        require(msg.sender == pool, "pool");
        _burn(from, amt);
    }

    function sendUnderlying(IERC20 u, address to, uint256 amt) external {
        require(msg.sender == pool, "pool");
        u.transfer(to, amt);
    }
}

contract MockPool {
    IERC20 public immutable usdc;
    MockAToken public immutable aToken;

    constructor(IERC20 _usdc) {
        usdc = _usdc;
        aToken = new MockAToken();
    }

    function supply(address, uint256 amount, address onBehalfOf, uint16) external {
        usdc.transferFrom(msg.sender, address(aToken), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address, uint256 amount, address to) external returns (uint256) {
        uint256 bal = aToken.balanceOf(msg.sender);
        if (amount == type(uint256).max) amount = bal;
        require(amount <= bal, "balance");
        require(amount <= usdc.balanceOf(address(aToken)), "liquidity");
        aToken.burn(msg.sender, amount);
        aToken.sendUnderlying(usdc, to, amount);
        return amount;
    }

    /// @dev Simulate interest: credit `amt` aUSDC to `who`, backed by freshly minted USDC.
    function accrue(address who, uint256 amt) external {
        MockUSDC(address(usdc)).mint(address(aToken), amt);
        aToken.mint(who, amt);
    }

    /// @dev Simulate borrowers draining cash from the reserve.
    function borrowOut(uint256 amt, address to) external {
        aToken.sendUnderlying(usdc, to, amt);
    }
}

/// @dev Compound III stand-in: tracks base supply per account; holds the USDC cash itself.
contract MockComet {
    IERC20 public immutable usdc;
    mapping(address => uint256) public balanceOf;
    uint64 public supplyRatePerSec = 1_902_587_519; // ~6% APR, 1e18-scaled

    constructor(IERC20 _usdc) {
        usdc = _usdc;
    }

    function baseToken() external view returns (address) {
        return address(usdc);
    }

    function supply(address, uint256 amount) external {
        usdc.transferFrom(msg.sender, address(this), amount);
        balanceOf[msg.sender] += amount;
    }

    function withdraw(address, uint256 amount) external {
        if (amount == type(uint256).max) amount = balanceOf[msg.sender];
        require(amount <= balanceOf[msg.sender], "balance");
        balanceOf[msg.sender] -= amount;
        usdc.transfer(msg.sender, amount);
    }

    function getUtilization() external pure returns (uint256) {
        return 8e17;
    }

    function getSupplyRate(uint256) external view returns (uint64) {
        return supplyRatePerSec;
    }

    function accrue(address who, uint256 amt) external {
        MockUSDC(address(usdc)).mint(address(this), amt);
        balanceOf[who] += amt;
    }

    function borrowOut(uint256 amt, address to) external {
        usdc.transfer(to, amt);
    }
}
