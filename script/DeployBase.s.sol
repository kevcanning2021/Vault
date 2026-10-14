// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BtcVault} from "../src/BtcVault.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {IComet} from "../src/interfaces/IComet.sol";

/// @notice Deploys BtcVault on BASE MAINNET (chain 8453) against Aave v3. REAL MONEY.
/// Addresses: bgd-labs/aave-address-book, AaveV3Base.sol (checked 2026-10-13)
contract DeployBase is Script {
    address constant POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // native USDC on Base
    address constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB; // aBasUSDC
    address constant COMET = 0xb125E6687d4313864e53df431d5425969c15Eb2F; // Compound v3 cUSDCv3
    uint256 constant CAP = 100e6; // start at 100 USDC; raise later with setDepositCap

    function run() external returns (BtcVault vault) {
        require(block.chainid == 8453, "Not Base mainnet");
        vm.startBroadcast();
        address owner_ = msg.sender;
        vault = new BtcVault(IERC20(USDC), IAavePool(POOL), IERC20(A_USDC), IComet(COMET), owner_, CAP);
        vm.stopBroadcast();
        console.log("BtcVault (Base mainnet) deployed at:", address(vault));
        console.log("Owner:", owner_);
        console.log("Deposit cap (USDC, 6dp):", CAP);
    }
}
