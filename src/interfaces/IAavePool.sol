// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal slice of the Aave v3 Pool the vault needs.
interface IAavePool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}
