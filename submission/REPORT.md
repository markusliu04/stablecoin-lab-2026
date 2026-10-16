# COMP7810 Lab 1 — Submission report

Date: 16 October 2026. Repository: [markusliu04/stablecoin-lab-2026](https://github.com/markusliu04/stablecoin-lab-2026).

## Scope and attribution

Completed the required local Ex0–Ex6 and optional Ex7 on an isolated Anvil/Foundry teaching fixture. AI assistance was used; the [discussion answers](../STUDENT-QUESTIONS.md) retain the disclosure. Review and responsibility remain with the student. This is not a production or audited stablecoin.

**Tier 2 Sepolia deployment and Etherscan verification were not performed.** Although described as bonus in the course material, the rubric assigns it 20%; no claim of completing that component or earning full marks is made.

## Implemented code

- [OverCollateralizedVault](../src/exercises/OverCollateralizedVault.sol): collateral value / decimals conversion, collateral ratio checks, debt handling and capped liquidation bonus.
- [Loop and permission tests](../test/exercises/01_LoopTasks.t.sol): Ex2 decimals and Ex4 authorization / pausing cases.
- [Invariant handler and invariants](../test/exercises/02_InvariantTasks.t.sol): Ex6 redeem handler and collateral/debt checks.
- [Additional edge tests](../test/exercises/04_OverCollateralEdgeCases.t.sol).
- [Ex7 test_unstoppable](../test/challenges/Unstoppable.t.sol): direct donation via `token.transfer(address(vault), INITIAL_PLAYER_TOKEN_BALANCE);`; setup, monitor and solved checks preserved.

## Observed verification

Foundry 1.8.4; solc 0.8.24; OpenZeppelin 5.0.2. All dependencies are vendored in the repository.

| Scope | Observed result | Evidence |
|---|---|---|
| Fresh independent unfiltered `forge test -vv --fuzz-seed 0x330377eebfe9f24b10d1259f4370f0f8ade6823f20ba30baacca9be4ac0f33b8` | 6 suites; **38 passed, 0 failed, 0 skipped; exit 0** | [Literal output](logs/PREPUSH_FULL_SUITE.json), [native screenshot](screenshots/native_macos_full_test_38_passed.png) |
| Historical pristine baseline, non-challenge suite | 7 passed, 18 failed; exit 1 | [Baseline log](logs/BASELINE_MATCHED.json) |
| Completed non-challenge suite | 36 passed, 0 failed; exit 0 | [Modified log](logs/MODIFIED_MATCHED.json) |
| Rollback, same non-challenge command/input | 7 passed, 18 failed; exit 1; restored tree hash equals original | [Rollback log](logs/ROLLBACK_MATCHED.json) |

The independent publishing checkout was also compiled from scratch and passed the same 38 tests with exit 0 ([literal output](logs/PUBLISH_CHECKOUT_FULL_SUITE.json)).

The core / exercises / challenge counts are 7 / 29 / 2. Saved historical logs are not represented as fresh reruns. Exported logs normalize the local working directory and omit environment PATH details; literal stdout, stderr and exit status are retained. Full canonical rollback artifacts remain in the local audit bundle, rather than adding a redundant baseline archive to this source repository.

## Ex3 local role-compromise simulation

Chain ID 31337; disposable local Anvil only. No public-chain or third-party attack was performed. The private keys present in original teaching commands are the publicly known Anvil test keys and must never hold real funds.

1. Honest deposit: supply and collateral both `1000000000` raw units (1,000 tokens each).
2. [Unauthorized mint](logs/EX3_STEP1_UNAUTHORIZED_MINT.json): rejected with `AccessControlUnauthorizedAccount` during gas estimation, exit 1. This was **not** a mined failed transaction. Balances remained unchanged.
3. [Admin role grant](logs/EX3_STEP2_GRANT_MINTER_ROLE.json): successful local transaction.
4. [Unbacked mint](logs/EX3_STEP3_AUTHORIZED_MINT.json): successful local transaction.
5. [Summary and readbacks](ex3-demo-summary.json): supply `1001000000000`, collateral `1000000000`, attacker balance `1000000000000`.

Only about 0.000999 units of MockUSDC now back each sUSD by quantity. MockUSDC has no real reserve value: this does not measure a dollar market price. Granting `MINTER_ROLE` permits minting outside the reserve vault, breaking the quantity-backing invariant.

[Native Ex3 screenshot](screenshots/native_macos_ex3_depeg_readback.png). The [README](../README.md) contains both Mermaid architecture diagrams and the [rendered diagram](screenshots/architecture_diagram.png).
