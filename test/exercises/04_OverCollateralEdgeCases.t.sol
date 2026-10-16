// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {MockWETH} from "../../src/exercises/MockWETH.sol";
import {MockPriceFeed} from "../../src/exercises/MockPriceFeed.sol";
import {OverCollateralizedVault} from "../../src/exercises/OverCollateralizedVault.sol";

/// @notice Additional Ex5 checks for boundary conditions and atomic rollback.
contract OverCollateralEdgeCasesTest is Test {
    MockWETH internal weth;
    SimpleStablecoin internal stable;
    MockPriceFeed internal feed;
    OverCollateralizedVault internal vault;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        weth = new MockWETH();
        stable = new SimpleStablecoin(address(this));
        feed = new MockPriceFeed(2000e8);
        vault = new OverCollateralizedVault(weth, stable, feed);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
        weth.faucet(alice, 10e18);
        weth.faucet(bob, 10e18);
    }

    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        weth.approve(address(vault), amount);
        vault.depositCollateral(amount);
        vm.stopPrank();
    }

    function _mintAndFundBob() internal {
        _deposit(alice, 1e18);
        vm.startPrank(alice);
        vault.mintStable(1000e6);
        stable.transfer(bob, 1000e6);
        vm.stopPrank();
    }

    function test_Ex5Edge_ZeroMintAndRedeemRevert() public {
        vm.expectRevert(OverCollateralizedVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.mintStable(0);

        vm.expectRevert(OverCollateralizedVault.ZeroAmount.selector);
        vm.prank(alice);
        vault.redeemCollateral(0);

        assertEq(vault.debtOf(alice), 0);
        assertEq(stable.totalSupply(), 0);
    }

    function test_Ex5Edge_MintChecksAccumulatedDebtAndRevertsAtomically() public {
        _deposit(alice, 1e18);
        vm.prank(alice);
        vault.mintStable(1000e6);

        vm.expectRevert(OverCollateralizedVault.Undercollateralized.selector);
        vm.prank(alice);
        vault.mintStable(334e6);

        assertEq(vault.debtOf(alice), 1000e6);
        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(stable.totalSupply(), 1000e6);
        assertEq(vault.collateralOf(alice), 1e18);
    }

    function test_Ex5Edge_RedeemFailuresLeaveCollateralUnchanged() public {
        _deposit(alice, 2e18);
        vm.prank(alice);
        vault.mintStable(2000e6);

        vm.expectRevert(OverCollateralizedVault.InsufficientCollateral.selector);
        vm.prank(alice);
        vault.redeemCollateral(2e18 + 1);

        vm.expectRevert(OverCollateralizedVault.Undercollateralized.selector);
        vm.prank(alice);
        vault.redeemCollateral(0.6e18);

        assertEq(vault.collateralOf(alice), 2e18);
        assertEq(weth.balanceOf(address(vault)), 2e18);
        assertEq(weth.balanceOf(alice), 8e18);
        assertEq(vault.debtOf(alice), 2000e6);
    }

    function test_Ex5Edge_DebtFreeUserCanRedeemAllCollateral() public {
        _deposit(alice, 1e18);

        vm.prank(alice);
        vault.redeemCollateral(1e18);

        assertEq(vault.collateralOf(alice), 0);
        assertEq(weth.balanceOf(alice), 10e18);
        assertEq(weth.balanceOf(address(vault)), 0);
        assertEq(vault.collateralRatio(alice), type(uint256).max);
    }

    function test_Ex5Edge_LiquidationAtExactly120PercentReverts() public {
        _mintAndFundBob();
        feed.setPrice(1200e8);
        assertEq(vault.collateralRatio(alice), 120);

        vm.expectRevert(OverCollateralizedVault.NotLiquidatable.selector);
        vm.prank(bob);
        vault.liquidate(alice);

        assertEq(vault.debtOf(alice), 1000e6);
        assertEq(vault.collateralOf(alice), 1e18);
        assertEq(stable.balanceOf(bob), 1000e6);
    }

    function test_Ex5Edge_DebtFreeUserCannotBeLiquidated() public {
        _deposit(alice, 1e18);

        vm.expectRevert(OverCollateralizedVault.NotLiquidatable.selector);
        vm.prank(bob);
        vault.liquidate(alice);

        assertEq(vault.collateralOf(alice), 1e18);
        assertEq(vault.debtOf(alice), 0);
    }

    function test_Ex5Edge_UnderfundedLiquidatorRevertsAtomically() public {
        _deposit(alice, 1e18);
        vm.startPrank(alice);
        vault.mintStable(1000e6);
        stable.transfer(bob, 1000e6 - 1);
        vm.stopPrank();
        feed.setPrice(1100e8);

        // The vault must burn Bob's balance, not Alice's debt-associated balance.
        vm.expectRevert();
        vm.prank(bob);
        vault.liquidate(alice);

        assertEq(vault.debtOf(alice), 1000e6);
        assertEq(vault.collateralOf(alice), 1e18);
        assertEq(stable.balanceOf(alice), 1);
        assertEq(stable.balanceOf(bob), 1000e6 - 1);
        assertEq(stable.totalSupply(), 1000e6);
        assertEq(weth.balanceOf(bob), 10e18);
        assertEq(weth.balanceOf(address(vault)), 1e18);
    }

    function test_Ex5Edge_UncappedBonusLeavesRedeemableRemainder() public {
        _mintAndFundBob();
        uint256 price = 1150e8 + 1;
        feed.setPrice(int256(price));
        uint256 seized = uint256(1000e6) * 110 * 1e20 / (100 * price);

        vm.prank(bob);
        vault.liquidate(alice);

        assertEq(vault.debtOf(alice), 0);
        assertEq(stable.balanceOf(bob), 0);
        assertEq(stable.totalSupply(), 0);
        assertEq(weth.balanceOf(bob), 10e18 + seized);
        assertEq(vault.collateralOf(alice), 1e18 - seized);
        assertEq(weth.balanceOf(address(vault)), 1e18 - seized);
        assertGt(vault.collateralOf(alice), 0);

        vm.prank(alice);
        vault.redeemCollateral(1e18 - seized);
        assertEq(vault.collateralOf(alice), 0);
        assertEq(weth.balanceOf(address(vault)), 0);
        assertEq(weth.balanceOf(alice), 10e18 - seized);
    }

    function test_Ex5Edge_ConversionRoundsDownAndRejectsInvalidPrice() public {
        assertEq(vault.collateralValue(499999999), 0);
        assertEq(vault.collateralValue(500000000), 1);

        feed.setPrice(0);
        vm.expectRevert(OverCollateralizedVault.ZeroAmount.selector);
        vault.collateralValue(1e18);

        feed.setPrice(-1);
        vm.expectRevert(OverCollateralizedVault.ZeroAmount.selector);
        vault.collateralValue(1e18);
    }
}
