// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BtcVault} from "../src/BtcVault.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {IComet} from "../src/interfaces/IComet.sol";

/// @notice Deploys BtcVault on Base Sepolia (chain 84532) against Aave v3.
/// Addresses: bgd-labs/aave-address-book, AaveV3BaseSepolia.sol
contract Deploy is Script {
    address constant POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
    address constant USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f; // Aave test USDC (faucet-mintable)
    address constant A_USDC = 0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC;
    address constant COMET = address(0); // Compound has no Base Sepolia deployment
    uint256 constant CAP = 1_000_000e6; // test money: effectively uncapped

    function run() external returns (BtcVault vault) {
        require(block.chainid == 84532, "Not Base Sepolia");
        vm.startBroadcast();
        address owner_ = msg.sender;
        vault = new BtcVault(IERC20(USDC), IAavePool(POOL), IERC20(A_USDC), IComet(COMET), owner_, CAP);
        vm.stopBroadcast();
        console.log("BtcVault deployed at:", address(vault));
        console.log("Owner:", owner_);
    }
}
