// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BtcVault} from "../src/BtcVault.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {MockUSDC, MockPool, MockAToken} from "./mocks/MockAave.sol";

contract BtcVaultTest is Test {
    MockUSDC usdc;
    MockPool pool;
    MockAToken aToken;
    BtcVault vault;

    address me = makeAddr("me");
    address stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC();
        pool = new MockPool(usdc);
        aToken = pool.aToken();
        vault = new BtcVault(usdc, IAavePool(address(pool)), aToken, me);
        usdc.mint(me, 10_000e6);
        usdc.mint(stranger, 10_000e6);
        vm.prank(me);
        usdc.approve(address(vault), type(uint256).max);
        vm.prank(stranger);
        usdc.approve(address(vault), type(uint256).max);
    }

    function _deposit(uint256 amt) internal {
        vm.prank(me);
        vault.deposit(amt, me);
    }

    function test_DepositSuppliesToAave() public {
        _deposit(1_000e6);
        assertEq(aToken.balanceOf(address(vault)), 1_000e6);
        assertEq(usdc.balanceOf(address(vault)), 0);
        assertEq(vault.totalAssets(), 1_000e6);
        assertEq(vault.netDeposited(), 1_000e6);
        assertEq(vault.earned(), 0);
    }

    function test_InterestAccruesInUSDC() public {
        _deposit(1_000e6);
        pool.accrue(address(vault), 50e6);
        assertEq(vault.totalAssets(), 1_050e6);
        assertEq(vault.earned(), 50e6);
        assertApproxEqAbs(vault.convertToAssets(vault.balanceOf(me)), 1_050e6, 1);
    }

    function test_RedeemAllReturnsPrincipalPlusYield() public {
        _deposit(1_000e6);
        pool.accrue(address(vault), 50e6);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        uint256 out = vault.redeem(shares, me, me);
        assertApproxEqAbs(out, 1_050e6, 1);
        assertApproxEqAbs(usdc.balanceOf(me), 10_050e6, 1);
        assertEq(vault.netDeposited(), 0);
    }

    function test_PartialWithdraw() public {
        _deposit(1_000e6);
        vm.prank(me);
        vault.withdraw(400e6, me, me);
        assertEq(vault.totalAssets(), 600e6);
        assertEq(vault.netDeposited(), 600e6);
    }

    function test_StrangerCannotDeposit() public {
        vm.prank(stranger);
        vm.expectRevert();
        vault.deposit(100e6, stranger);
    }

    function test_StrangerCannotDepositForOwner() public {
        vm.prank(stranger);
        vm.expectRevert(BtcVault.OnlyOwner.selector);
        vault.deposit(100e6, me);
    }

    function test_StrangerCannotWithdrawOwnerFunds() public {
        _deposit(1_000e6);
        vm.prank(stranger);
        vm.expectRevert();
        vault.withdraw(100e6, stranger, me);
    }

    function test_EmergencyExitAndResume() public {
        _deposit(1_000e6);
        pool.accrue(address(vault), 10e6);
        vm.prank(me);
        vault.emergencyExit();
        assertEq(aToken.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(address(vault)), 1_010e6);
        assertEq(vault.maxDeposit(me), 0);

        // withdrawing while exited uses idle USDC
        vm.prank(me);
        vault.withdraw(10e6, me, me);
        assertEq(usdc.balanceOf(address(vault)), 1_000e6);

        vm.prank(me);
        vault.resume();
        assertEq(aToken.balanceOf(address(vault)), 1_000e6);
        assertGt(vault.maxDeposit(me), 0);
    }

    function test_OnlyOwnerCanExit() public {
        vm.prank(stranger);
        vm.expectRevert();
        vault.emergencyExit();
    }

    function test_MaxWithdrawRespectsAaveLiquidity() public {
        _deposit(1_000e6);
        pool.borrowOut(700e6, stranger); // borrowers took 700 of the cash
        assertEq(vault.maxWithdraw(me), 300e6);
    }

    function test_RescueCannotTouchVaultAssets() public {
        vm.startPrank(me);
        vm.expectRevert(BtcVault.CannotRescueVaultAssets.selector);
        vault.rescue(IERC20(address(usdc)), me);
        vm.expectRevert(BtcVault.CannotRescueVaultAssets.selector);
        vault.rescue(IERC20(address(aToken)), me);
        vm.stopPrank();
    }

    function testFuzz_DepositRedeemRoundTrip(uint256 amt, uint256 interest) public {
        // >= 1 USDC: below that the ERC-4626 virtual share (1 wei) takes a visible cut of yield.
        amt = bound(amt, 1e6, 10_000e6);
        interest = bound(interest, 0, 1_000e6);
        _deposit(amt);
        pool.accrue(address(vault), interest);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        uint256 out = vault.redeem(shares, me, me);
        assertLe(out, amt + interest);
        // Virtual-share leakage is at most interest / amt (+1 wei rounding): < 1 ppm of yield per USDC.
        assertApproxEqAbs(out, amt + interest, interest / amt + 1);
    }
}

/// @notice Runs against the real Aave v3 pool on Base Sepolia. Skipped unless BASE_SEPOLIA_RPC is set.
contract BtcVaultForkTest is Test {
    address constant POOL = 0x8bAB6d1b75f19e9eD9fCe8b9BD338844fF79aE27;
    address constant USDC = 0xba50Cd2A20f6DA35D788639E581bca8d0B5d4D5f;
    address constant A_USDC = 0x10F1A9D11CDf50041f3f8cB7191CBE2f31750ACC;

    function test_ForkDepositWithdraw() public {
        string memory rpc = vm.envOr("BASE_SEPOLIA_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        address me = makeAddr("me");
        BtcVault vault = new BtcVault(IERC20(USDC), IAavePool(POOL), IERC20(A_USDC), me);
        deal(USDC, me, 1_000e6);
        vm.startPrank(me);
        IERC20(USDC).approve(address(vault), type(uint256).max);
        vault.deposit(1_000e6, me);
        vm.warp(block.timestamp + 30 days);
        assertGe(vault.totalAssets(), 1_000e6 - 1);
        vault.redeem(vault.balanceOf(me), me, me);
        vm.stopPrank();
        assertGe(IERC20(USDC).balanceOf(me), 1_000e6 - 1);
    }
}
