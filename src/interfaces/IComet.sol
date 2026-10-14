// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal slice of Compound III (Comet) the vault needs.
interface IComet {
    function supply(address asset, uint256 amount) external;

    /// @dev amount = type(uint256).max withdraws the full base balance.
    function withdraw(address asset, uint256 amount) external;

    /// @notice Present value of the account's base-asset supply (grows with interest).
    function balanceOf(address account) external view returns (uint256);

    function baseToken() external view returns (address);

    function getUtilization() external view returns (uint256);

    /// @notice Per-second supply rate, scaled by 1e18.
    function getSupplyRate(uint256 utilization) external view returns (uint64);
}
