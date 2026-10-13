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
