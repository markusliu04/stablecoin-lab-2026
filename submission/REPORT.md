# COMP7810 Assignment 2 - Stablecoin Lab 1

Repository: [markusliu04/stablecoin-lab-2026](https://github.com/markusliu04/stablecoin-lab-2026).

## Submission contents

The [main PDF](COMP7810_Assignment2_Submission.pdf) contains the repository link, test and Ex3 screenshots, deployment addresses and verification links, architecture diagram, and discussion questions/answers. The [standalone appendix](COMP7810_Assignment2_Generative_AI_Appendix.pdf) centralizes the contribution statement; it is not repeated before each answer.

## Local implementation and evidence

Required Ex0-Ex6 and optional Ex7 are completed. `make test`, `make exercise` and `make challenge` cover 7, 29 and 2 tests respectively. Unfiltered `forge test` passes all 38 tests across 6 suites, including the invariant run. See the [native screenshot](screenshots/native_macos_full_test_38_passed.png), [original independent publishing run](logs/PUBLISH_CHECKOUT_FULL_SUITE.json), and the [final refresh full-suite log](logs/FINAL_FULL_SUITE.json).

Ex3 was performed only on disposable local Anvil. Before the role grant, the mint attempt was rejected during gas estimation (not a mined failed transaction). After a local admin role grant and direct mint, supply was `1001000000000`, collateral `1000000000`, and attacker balance `1000000000000`. See the [summary](ex3-demo-summary.json) and [native screenshot](screenshots/native_macos_ex3_depeg_readback.png). MockUSDC is a test token; this readback does not establish a real dollar market price.

## Sepolia deployment and source verification

Chain ID: `11155111`. Deployment block: `11928229`. All three deployment receipts and the role-grant receipt have status `1`. [Independent public-chain readback](SEPOLIA_PUBLIC_VERIFICATION.json) confirms nonempty deployed code, the vault's collateral/stable references and the vault's `MINTER_ROLE`.

| Contract | Source verification link | Exact classification |
|---|---|---|
| MockUSDC | [0xdB7bdC4faBE2c136896A061F905227567c5Cc307](https://sepolia.etherscan.io/address/0xdb7bdc4fabe2c136896a061f905227567c5cc307#code) | Source Code Verified - Similar Match |
| SimpleStablecoin | [0x9Acfcc3d676c77E409E81Cf24d2766bEeEe66878](https://sepolia.etherscan.io/address/0x9acfcc3d676c77e409e81cf24d2766beeee66878#code) | Source Code Verified - Similar Match |
| Vault | [0xC940A20D69a12D8806C7d8928a99b41478f266E9](https://sepolia.etherscan.io/address/0xc940a20d69a12d8806c7d8928a99b41478f266e9#code) | Source Code Verified - Exact Match |

The first two runtime bytecodes match the local compilation exactly. Similar Match is not relabeled as Exact Match. The project is an educational prototype, not production-ready or audited.

## Written work and architecture

[Questions and answers](../STUDENT-QUESTIONS.md); [README with architecture and deployment table](../README.md); [rendered architecture](screenshots/architecture_diagram.png). The course starter is retained as the comparison baseline; the code changes implement Ex5 vault operations, Ex6 handler/invariants, Ex2/Ex4 tests and the optional Ex7 test.

## Delivery notes

Moodle accepts file uploads. Upload the main PDF and the separate appendix PDF; the source ZIP is an optional backup, not an extra handout requirement. The lab handout does not prescribe the PDF format or an appendix; these files package its actual requirements for a file-only submission form. Private keys, API credentials, `.env`, build caches and deployment broadcast artifacts are excluded.
