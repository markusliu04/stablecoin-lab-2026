// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {MockUSDC} from "../../src/MockUSDC.sol";
import {SimpleStablecoin} from "../../src/SimpleStablecoin.sol";
import {Vault} from "../../src/Vault.sol";

/// @title Ex2 + Ex4 — amount precision and authorization regression tests
/// @notice Acceptance: make exercise. These tests preserve, rather than silently fix,
///         the original contracts' teaching limitations.
contract LoopTasksTest is Test {
    MockUSDC internal usdc;
    SimpleStablecoin internal stable;
    Vault internal vault;

    address internal admin = address(this);
    address internal alice = makeAddr("alice");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUSDC();
        stable = new SimpleStablecoin(admin);
        vault = new Vault(usdc, stable);
        stable.grantRole(stable.MINTER_ROLE(), address(vault));
    }

    function _deposit(address user, uint256 amount) internal {
        usdc.faucet(user, amount);
        vm.startPrank(user);
        usdc.approve(address(vault), amount);
        vault.deposit(amount);
        vm.stopPrank();
    }

    // ==================================================================
    // Ex2 · the decimals trap: a 6-decimal stablecoin meets 18-decimal intuition
    // ==================================================================

    /// @dev For any legitimate amount x, totalSupply() must grow by exactly x after
    ///      deposit(x). Hint: use vm.assume to rule out x == 0, and faucet alice enough
    ///      usdc first.
    function test_Ex2_DepositIncreasesSupplyByExactly(uint96 raw) public {
        uint256 amount = uint256(raw) % 1_000_000e6;
        vm.assume(amount > 0);
        _deposit(alice, 23e6);
        uint256 supplyBefore = stable.totalSupply();
        uint256 collateralBefore = vault.totalCollateral();

        _deposit(alice, amount);

        assertEq(stable.totalSupply() - supplyBefore, amount);
        assertEq(vault.totalCollateral() - collateralBefore, amount);
        assertEq(stable.balanceOf(alice), supplyBefore + amount);
        assertEq(vault.totalCollateral(), stable.totalSupply());
    }

    /// @dev Run deposit with 1000e18 instead of 1000e6, see what happens, then assert what
    ///      you observed. With 6 decimals, 1000e18 is 10^15 coins, not 1000.
    ///      The unrestricted test faucet lets the wrong input succeed, while backing
    ///      still holds: the error is human-unit interpretation, not vault accounting.
    function test_Ex2_DecimalsTrap() public {
        uint256 intended = 1000e6;
        uint256 wrong = 1000e18;
        assertEq(usdc.decimals(), 6);
        assertEq(stable.decimals(), 6);
        assertEq(wrong / intended, 1e12);
        assertEq(wrong / 1e6, 1e15);

        _deposit(alice, wrong);

        assertEq(stable.balanceOf(alice), wrong);
        assertEq(stable.totalSupply(), wrong);
        assertEq(vault.totalCollateral(), wrong);
        vm.prank(alice);
        vault.redeem(wrong);
        assertEq(usdc.balanceOf(alice), wrong);
        assertEq(stable.totalSupply(), 0);
    }

    // ==================================================================
    // Ex4 · permissions and pausing: where the guard is, who holds the key
    // ==================================================================

    /// @dev The attacker has no MINTER_ROLE, so calling mint directly must revert. Use
    ///      vm.expectRevert + abi.encodeWithSelector to pin down the exact error.
    function test_Ex4_Mint_RevertsForNonMinter() public {
        bytes32 role = stable.MINTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, role
            )
        );
        vm.prank(attacker);
        stable.mint(attacker, 1000e6);
        assertEq(stable.totalSupply(), 0);
        assertEq(stable.balanceOf(attacker), 0);
    }

    /// @dev After pause(), an ordinary transfer must revert
    function test_Ex4_Pause_BlocksTransfers() public {
        _deposit(alice, 1000e6);
        stable.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        stable.transfer(attacker, 1e6);
        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(stable.balanceOf(attacker), 0);
    }

    /// @dev What pause() freezes is _update, so redemption is frozen along with everything
    ///      else — why is that bad news in a real crisis?
    ///      (This is STUDENT-QUESTIONS.md B1 and B2.)
    function test_Ex4_Pause_BlocksRedeem() public {
        _deposit(alice, 1000e6);
        stable.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(alice);
        vault.redeem(1000e6);
        assertEq(vault.totalCollateral(), 1000e6);
        assertEq(stable.totalSupply(), 1000e6);
        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(usdc.balanceOf(alice), 0);

        stable.unpause();
        vm.prank(alice);
        vault.redeem(1000e6);
        assertEq(usdc.balanceOf(alice), 1000e6);
        assertEq(stable.totalSupply(), 0);
    }

    /// @dev An attacker cannot burn someone else's balance
    function test_Ex4_AttackerCannotBurnOthersBalance() public {
        _deposit(alice, 1000e6);
        bytes32 role = stable.MINTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, role
            )
        );
        vm.prank(attacker);
        stable.burn(alice, 100e6);
        assertEq(stable.balanceOf(alice), 1000e6);
        assertEq(stable.totalSupply(), 1000e6);
    }

    /// @dev ...but the vault can, because it holds MINTER_ROLE and burn() answers to that
    ///      same role. This test proves the backdoor exists; it does not justify it.
    function test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance() public {
        _deposit(alice, 1000e6);
        vm.prank(address(vault));
        stable.burn(alice, 100e6);
        assertEq(stable.balanceOf(alice), 900e6);
        assertEq(stable.totalSupply(), 900e6);
        assertEq(vault.totalCollateral(), 1000e6);
    }
}
