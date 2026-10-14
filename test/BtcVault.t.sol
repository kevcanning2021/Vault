// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {BtcVault} from "../src/BtcVault.sol";
import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {MockUSDC, MockPool, MockAToken, MockComet} from "./mocks/MockAave.sol";
import {IComet} from "../src/interfaces/IComet.sol";

contract BtcVaultTest is Test {
    MockUSDC usdc;
    MockPool pool;
    MockAToken aToken;
    MockComet comet;
    BtcVault vault;

    address me = makeAddr("me");
    address stranger = makeAddr("stranger");

    function setUp() public {
        usdc = new MockUSDC();
        pool = new MockPool(usdc);
        aToken = pool.aToken();
        comet = new MockComet(usdc);
        vault = new BtcVault(usdc, IAavePool(address(pool)), aToken, IComet(address(comet)), me, 1_000_000e6);
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

    function test_BelowMinimumDepositReverts() public {
        vm.prank(me);
        vm.expectRevert(abi.encodeWithSelector(BtcVault.BelowMinimumDeposit.selector, 999_999, 1e6));
        vault.deposit(999_999, me);
    }

    function test_ExactMinimumDepositWorks() public {
        _deposit(1e6);
        assertEq(vault.totalAssets(), 1e6);
    }

    function test_MintBelowMinimumReverts() public {
        vm.prank(me);
        vm.expectRevert();
        vault.mint(1e6, me); // 1e6 shares ≈ 1 wei of USDC with the 6-decimal offset
    }

    function test_DepositCapBlocksOverflow() public {
        vm.prank(me);
        vault.setDepositCap(100e6);
        _deposit(60e6);
        assertEq(vault.maxDeposit(me), 40e6);
        vm.prank(me);
        vm.expectRevert(); // ERC4626ExceededMaxDeposit
        vault.deposit(41e6, me);
        _deposit(40e6);
        assertEq(vault.maxDeposit(me), 0);
        assertEq(vault.maxMint(me), 0);
    }

    function test_InterestCanPushAboveCapButWithdrawStillWorks() public {
        vm.prank(me);
        vault.setDepositCap(100e6);
        _deposit(100e6);
        pool.accrue(address(vault), 5e6);
        assertEq(vault.maxDeposit(me), 0);
        vm.prank(me);
        vault.withdraw(50e6, me, me);
        assertEq(vault.maxDeposit(me), 45e6);
    }

    function test_LoweringCapNeverBlocksWithdraw() public {
        _deposit(500e6);
        vm.prank(me);
        vault.setDepositCap(0);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        vault.redeem(shares, me, me);
        assertEq(vault.totalAssets(), 0);
    }

    function test_OnlyOwnerSetsCap() public {
        vm.prank(stranger);
        vm.expectRevert();
        vault.setDepositCap(1);
    }

    function test_MoveToCompoundAndBack() public {
        _deposit(1_000e6);
        pool.accrue(address(vault), 10e6);
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        assertEq(uint8(vault.venue()), 1);
        assertEq(aToken.balanceOf(address(vault)), 0);
        assertEq(comet.balanceOf(address(vault)), 1_010e6);
        assertEq(vault.totalAssets(), 1_010e6);

        comet.accrue(address(vault), 20e6);
        assertEq(vault.earned(), 30e6);

        _deposit(100e6); // new deposits follow the venue
        assertEq(comet.balanceOf(address(vault)), 1_130e6);

        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Aave);
        assertEq(comet.balanceOf(address(vault)), 0);
        assertEq(aToken.balanceOf(address(vault)), 1_130e6);
    }

    function test_WithdrawFromCompound() public {
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        _deposit(500e6);
        vm.prank(me);
        vault.withdraw(200e6, me, me);
        assertEq(comet.balanceOf(address(vault)), 300e6);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        vault.redeem(shares, me, me);
        assertEq(vault.totalAssets(), 0);
    }

    function test_WithdrawDrawsFromBothLenders() public {
        _deposit(300e6); // on Aave
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        // leave some on Aave by simulating interest arriving after the move
        pool.accrue(address(vault), 5e6);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        vault.redeem(shares, me, me);
        // ERC-4626 rounds in the vault's favour, so at most 1 wei of dust may stay behind.
        assertLe(aToken.balanceOf(address(vault)) + comet.balanceOf(address(vault)), 1);
        assertApproxEqAbs(usdc.balanceOf(me), 10_005e6, 1);
    }

    function test_EmergencyExitPullsFromCompound() public {
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        _deposit(400e6);
        vm.prank(me);
        vault.emergencyExit();
        assertEq(comet.balanceOf(address(vault)), 0);
        assertEq(usdc.balanceOf(address(vault)), 400e6);
        vm.prank(me);
        vault.resume();
        assertEq(comet.balanceOf(address(vault)), 400e6);
    }

    function test_MaxWithdrawRespectsCompoundLiquidity() public {
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        _deposit(1_000e6);
        comet.borrowOut(900e6, stranger);
        assertEq(vault.maxWithdraw(me), 100e6);
    }

    function test_MoveGuards() public {
        vm.prank(stranger);
        vm.expectRevert();
        vault.moveTo(BtcVault.Venue.Compound);
        vm.prank(me);
        vm.expectRevert(BtcVault.AlreadyThere.selector);
        vault.moveTo(BtcVault.Venue.Aave);
        vm.prank(me);
        vault.emergencyExit();
        vm.prank(me);
        vm.expectRevert(BtcVault.VaultExited.selector);
        vault.moveTo(BtcVault.Venue.Compound);
    }

    function test_AaveOnlyVaultRejectsCompound() public {
        BtcVault aaveOnly = new BtcVault(usdc, IAavePool(address(pool)), aToken, IComet(address(0)), me, 1_000e6);
        vm.prank(me);
        vm.expectRevert(BtcVault.CompoundNotConfigured.selector);
        aaveOnly.moveTo(BtcVault.Venue.Compound);
        assertFalse(aaveOnly.hasCompound());
    }

    function test_CometAssetMismatchReverts() public {
        MockUSDC other = new MockUSDC();
        MockComet wrong = new MockComet(other);
        vm.expectRevert(BtcVault.CometAssetMismatch.selector);
        new BtcVault(usdc, IAavePool(address(pool)), aToken, IComet(address(wrong)), me, 1_000e6);
    }

    function test_RescueCannotTouchCometPosition() public {
        vm.prank(me);
        vm.expectRevert(BtcVault.CannotRescueVaultAssets.selector);
        vault.rescue(IERC20(address(comet)), me);
    }

    function testFuzz_MoveKeepsValue(uint256 amt, uint256 aaveInt, uint256 compInt) public {
        amt = bound(amt, 1e6, 10_000e6);
        aaveInt = bound(aaveInt, 0, 500e6);
        compInt = bound(compInt, 0, 500e6);
        _deposit(amt);
        pool.accrue(address(vault), aaveInt);
        vm.prank(me);
        vault.moveTo(BtcVault.Venue.Compound);
        comet.accrue(address(vault), compInt);
        assertEq(vault.totalAssets(), amt + aaveInt + compInt);
        uint256 shares = vault.balanceOf(me);
        vm.prank(me);
        uint256 out = vault.redeem(shares, me, me);
        assertApproxEqAbs(out, amt + aaveInt + compInt, (aaveInt + compInt) / amt + 1);
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

/// @notice Runs against the real Aave v3 pool on Base MAINNET. Skipped unless BASE_RPC is set.
///         Uses a fork: no real funds move.
contract BtcVaultBaseForkTest is Test {
    address constant POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant COMET = 0xb125E6687d4313864e53df431d5425969c15Eb2F; // Compound v3 cUSDCv3 on Base

    function test_BaseForkAaveCompoundRoundTrip() public {
        string memory rpc = vm.envOr("BASE_RPC", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        address me = makeAddr("me");
        BtcVault vault = new BtcVault(IERC20(USDC), IAavePool(POOL), IERC20(A_USDC), IComet(COMET), me, 100e6);
        deal(USDC, me, 100e6);
        vm.startPrank(me);
        IERC20(USDC).approve(address(vault), type(uint256).max);

        vault.deposit(100e6, me);
        assertEq(vault.maxDeposit(me), 0); // cap reached
        vm.warp(block.timestamp + 15 days);
        vm.roll(block.number + 650_000);
        uint256 afterAave = vault.totalAssets();
        assertGt(afterAave, 100e6); // real Aave interest

        vault.moveTo(BtcVault.Venue.Compound);
        assertApproxEqAbs(vault.totalAssets(), afterAave, 2); // nothing lost in the move
        assertLe(IERC20(A_USDC).balanceOf(address(vault)), 1);

        vm.warp(block.timestamp + 15 days);
        vm.roll(block.number + 650_000);
        assertGt(vault.totalAssets(), afterAave); // real Compound interest

        vault.moveTo(BtcVault.Venue.Aave);
        vault.redeem(vault.balanceOf(me), me, me);
        vm.stopPrank();
        assertGt(IERC20(USDC).balanceOf(me), 100e6);
        assertLe(vault.totalAssets(), 2);
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
        BtcVault vault = new BtcVault(IERC20(USDC), IAavePool(POOL), IERC20(A_USDC), IComet(address(0)), me, 1_000_000e6);
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
