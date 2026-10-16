# EXERCISES.md — the hands-on list

This file is **what you have to write**. The README tells you what the lab is; this tells you what to do.

Every exercise has one command that answers "am I done?". Red means not done, green means done.
The starter tests under `test/exercises/` are **deliberately red** — that is not a bug report, that is your task.

> **Completion status:** verify with `make test` (7 passed), `make exercise` (29 passed),
> `make challenge` (2 passed), and unfiltered `forge test` (38 passed, 0 failed).
> Ex3 and Ex7 are completed locally. The three core contracts are deployed on Sepolia;
> the README records addresses and the precise Etherscan verification classifications.

---

## Overview

| # | What you will do | Acceptance command | Where to look if stuck |
|---|---|---|---|
| Ex0 | Set up the environment, get the core tests passing | `make test` (7 green) | `README.md` "1. Setup" |
| Ex1 | Walk the mint/redeem loop once on the command line | faucet → approve → `make mint` → redeem → readback | `README.md` "2. Quick start", the Ex1 commands below |
| Ex2 | Catch the 6-vs-18-decimal trap in a test | the two `Ex2` tests under `01_*` in `make exercise` | the Ex2 "hint" below, `test/exercises/01_LoopTasks.t.sol` |
| Ex3 | Break a stablecoin's peg with your own hands | `totalSupply() >> totalCollateral()` on local Anvil | the four Ex3 commands below |
| Ex4 | Write tests for permissions and pausing | the five `Ex4` tests under `01_*` | `STUDENT-QUESTIONS.md` A1/B1, `test/exercises/01_LoopTasks.t.sol` |
| Ex5 | Implement the over-collateralized vault and liquidation | all of `03_*` green | `src/exercises/OverCollateralizedVault.sol`, the decimals table below |
| Ex6 | Write invariant tests (the machine calls things at random and hunts for a counterexample) | all of `02_*` green | `test/exercises/02_InvariantTasks.t.sol`, the Ex6 "hint" below |
| Ex7 | Make a real vault stop serving | `make challenge` (2 green) | `test/challenges/Unstoppable.t.sol` |

The deck has three reference pages worth keeping open:
P18 decimals, P25 the invariant handler, P27 if you are stuck look here.

---

## Ex0 · Environment

```bash
make doctor    # 30 seconds: is this machine ready? anything ✗ comes with its own fix
make test      # acceptance: 7 passed
```

`lib/` (forge-std + OpenZeppelin v5.0.2) **ships inside this repository** — a plain
`git clone` compiles as-is. There is nothing to install, and you do not need `make setup`
unless `lib/` is somehow empty (then `git checkout -- lib` restores it).

Installing Foundry on your own machine is the one step that can fail on a mainland
network; the Setup section of `README.md` covers the `gh-proxy.com` mirror, and
Track B (Codespaces) installs nothing locally.

---

## Ex1 · Walk the loop once

Use a fresh local Anvil and account 0 for this walkthrough. All keys below are Anvil's
published test fixtures, **never a wallet for real funds**. `make mint` only calls
`Vault.deposit`: it neither faucets mUSDC nor approves collateral for you.

```bash
# Terminal A: leave the local chain running.
make anvil

# Terminal B: deploy the core loop and copy the printed addresses.
make deploy-anvil
export RPC=http://127.0.0.1:8545
export USDC="<MockUSDC_address>" SUSD="<SimpleStablecoin_address>" VAULT="<Vault_address>"

# Anvil's public default account 0; matches deploy-anvil and make mint.
export ANVIL_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export USER=$(cast wallet address --private-key "$ANVIL_KEY")
export AMOUNT=1000000000   # 1,000 tokens at 6 decimals

# 1. Receive local collateral, then authorize the Vault to take it.
cast send "$USDC" "faucet(address,uint256)" "$USER" "$AMOUNT" \
  --rpc-url "$RPC" --private-key "$ANVIL_KEY"
cast send "$USDC" "approve(address,uint256)" "$VAULT" "$AMOUNT" \
  --rpc-url "$RPC" --private-key "$ANVIL_KEY"

# 2. Deposit collateral; the Vault mints the same number of sUSD units.
make mint AMOUNT="$AMOUNT"
make balance TO="$USER"
cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"

# 3. Burn your sUSD and recover collateral. The CURRENT core needs no sUSD allowance.
cast send "$VAULT" "redeem(uint256)" "$AMOUNT" \
  --rpc-url "$RPC" --private-key "$ANVIL_KEY"

# 4. Read the final state, not just the transaction receipt.
make balance TO="$USER"
cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"
cast call "$USDC" "balanceOf(address)(uint256)" "$USER" --rpc-url "$RPC"
```

Replace each `<..._address>` placeholder before running; use the addresses from this chain,
not a previous deployment. The Makefile fixes RPC and signer to the values above, unless
overridden explicitly on its command line. This walkthrough does not use `.env` or Sepolia.

**Expected state on a fresh deployment with this one depositor** (not a fabricated run log):

| Checkpoint | User sUSD | Total sUSD supply | Vault mUSDC | User mUSDC |
|---|---:|---:|---:|---:|
| After faucet, before deposit | 0 | 0 | 0 | 1,000,000,000 |
| After deposit | 1,000,000,000 | 1,000,000,000 | 1,000,000,000 | 0 |
| After full redeem | 0 | 0 | 0 | 1,000,000,000 |

All numbers are smallest units. With multiple holders, an individual `balanceOf(user)`
need not equal global supply. Direct donations can make collateral greater than supply.
Save your own commands, receipts, and readbacks; expected values alone are not execution evidence.

---

## Ex2 · The decimals trap

Open `test/exercises/01_LoopTasks.t.sol` and write two tests:

1. `test_Ex2_DepositIncreasesSupplyByExactly` — for any legitimate amount x,
   the supply must increase by exactly x after `deposit(x)`.
2. `test_Ex2_DecimalsTrap` — run it with `1000e18` (instead of `1000e6`) and assert what you observe.

The second one has no expected answer. Run it, read the numbers carefully, then ask yourself one question:

> This operation **did not revert**, and the invariant **still holds**.
> So what exactly went wrong?

> Hint: `MockUSDC` has 6 decimals. `1000e18` units is **10^15** coins,
> not 1000 — off by a factor of 10^12. 18-decimal intuition does not transfer to a 6-decimal coin.

---

## Ex3 · Break the peg by hand (command line, no tests)

```bash
export ATTACK_KEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
export ATTACKER=$(cast wallet address --private-key "$ATTACK_KEY")

# 1. The attacker (no MINTER_ROLE) mints for themselves -- this must fail
cast send "$SUSD" "mint(address,uint256)" "$ATTACKER" 1000000000000 \
  --rpc-url "$RPC" --private-key "$ATTACK_KEY"

# 2. Now grant MINTER_ROLE to the attacker (simulating a leaked key / insider / bribe)
cast send "$SUSD" "grantRole(bytes32,address)" \
  $(cast keccak "MINTER_ROLE") "$ATTACKER" --rpc-url "$RPC" --private-key "$ANVIL_KEY"

# 3. Mint again -- this time it succeeds
cast send "$SUSD" "mint(address,uint256)" "$ATTACKER" 1000000000000 \
  --rpc-url "$RPC" --private-key "$ATTACK_KEY"

# 4. Read totalSupply() and totalCollateral(), screenshot both numbers
cast call "$SUSD" "totalSupply()(uint256)" --rpc-url "$RPC"
cast call "$VAULT" "totalCollateral()(uint256)" --rpc-url "$RPC"
```

Deliverable: one screenshot where `totalSupply()` is far greater than `totalCollateral()`.
**That is a depeg.** Not a line of code changed, and the peg is gone.

**Observed state on a local Anvil run (after an honest `1,000e6` deposit followed by Ex3 steps 1–4):**
- Step 1 (`mint` without `MINTER_ROLE`): reverted with `AccessControlUnauthorizedAccount(0x70997970C51812dc3A010C7d01b50e0d17dc79C8, 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6)`; `totalSupply() = 1000000000 [1e9]`, `totalCollateral() = 1000000000 [1e9]`.
- Step 2 (`grantRole(MINTER_ROLE, attacker)`): succeeded (`tx 0x13e85a8a...`, block 5).
- Step 3 (`mint(attacker, 1000000000000)`): succeeded (`tx 0x13a076f9...`, block 6).
- Step 4 readbacks: `totalSupply() = 1001000000000 [1.001e12]` (`1,001,000` sUSD) vs. `totalCollateral() = 1000000000 [1e9]` (`1,000` mUSDC), leaving an unbacked deficit of `1000000000000` raw units (`1,000,000` sUSD).

---

## Ex4 · Permissions and pausing

Same file, `01_LoopTasks.t.sol`, five tests:

| Function | What you are proving |
|---|---|
| `test_Ex4_Mint_RevertsForNonMinter` | no MINTER_ROLE, no minting |
| `test_Ex4_Pause_BlocksTransfers` | a transfer reverts after `pause()` |
| `test_Ex4_Pause_BlocksRedeem` | **redemption is frozen along with everything else** |
| `test_Ex4_AttackerCannotBurnOthersBalance` | an attacker cannot touch someone else's balance |
| `test_Ex4_VaultHoldsTheKey_CanBurnAnyonesBalance` | **but the vault can** |

The last one is not there to justify it, it is there to **prove the backdoor really exists**.
It maps to A1 in `STUDENT-QUESTIONS.md` — think it through, then go back and answer A1.

The third one maps to B1/B2: if you wanted "freeze transfers but allow redemption", how would you change it?

---

## Ex5 · Over-collateralization + liquidation

Open `src/exercises/OverCollateralizedVault.sol` and fill in the four TODOs:

| TODO | What to do | The hard part |
|---|---|---|
| Ex5.1 `collateralValue` | turn collateral into a value in sUSD | 18 decimals × 8 decimals -> 6 decimals: divide by 10 to what power? |
| Ex5.2 `mintStable` | the ratio after minting must not fall below 150% | record first, or check first? |
| Ex5.3 `redeemCollateral` | the ratio after withdrawing must not fall below 150% | as above |
| Ex5.4 `liquidate` | below 120% anyone may liquidate | the bonus can exceed the collateral that is left |

Acceptance:

```bash
make exercise   # just the 03_* group
```

Three decimal counts you must keep apart — this is the sequel to Ex2:

```
collateral mWETH   18 decimals
stablecoin sUSD     6 decimals
price feed          8 decimals   ->   18 + 8 - 6 = 20
```

About Ex5.4, one question to think through:

> When the price falls hard enough, "debt value × 110%" can be more than the collateral the user
> deposited. Who eats the shortfall? Why can't real lending protocols escape this either?

---

## Ex6 · Invariant testing

Open `test/exercises/02_InvariantTasks.t.sol`.

Every test so far has been "I set up a situation and check the result".
Invariant testing flips that around: **let the machine call a pile of operations at random and in
sequence**, then ask "no matter how it thrashes, has this property been broken?"

Three things to do:

1. Implement the handler's `redeem` (the parameters have no names yet — name them first)
2. Turn `invariant_CollateralBacksSupply` into the property you actually want to defend
3. Do the same for `invariant_VaultHoldsNoStablecoin`

```bash
make exercise   # just the 02_* group
```

When an assertion fails, Foundry prints the **counterexample call sequence** — walk that sequence by
hand and you will see exactly at which step, and with which arguments, the invariant broke. This is
the closest thing in the lab to a real security audit.

> Hint: why must `invariant_VaultHoldsNoStablecoin` hold?
> The vault only ever mints sUSD to users and should keep none for itself. If it did hold sUSD,
> what would that mean?

---

## Ex7 · Make a real vault stop serving

```bash
make challenge     # acceptance: 2 passed (test_assertInitialState and test_unstoppable)
```

The material is in `test/challenges/Unstoppable.t.sol`, ported from Damn Vulnerable DeFi v4.
You are holding 10 DVT, and the goal is to make the vault **stop offering flash loans**.

The only function you need to change is `test_unstoppable()`. The hint is already in there:

> What assumption does the vault make about its own balance?

Transferring `INITIAL_PLAYER_TOKEN_BALANCE` directly to `address(vault)` causes `totalAssets()` (`IERC20(asset()).balanceOf(address(this))`) to exceed `convertToShares(totalSupply())`, triggering `InvalidBalance()` inside `flashLoan()`, so `UnstoppableMonitor.checkFlashLoan` emits `FlashLoanStatus(false)`, pauses the vault, and returns ownership to `deployer`.

---

## Deliverables

The homework requirements, grading weights and how to submit are in the "4. Homework" and
"6. Submission" sections of `README.md`.
The discussion questions are in `STUDENT-QUESTIONS.md`.
