# Mainnet Stacker adaptation

This launch remains one ownerless `Stacker(IERC20 imd, IStakedIMD sImd)` on Ethereum, using the existing `launch.json` unchanged:

- IMD: `0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7`.
- sIMD: `0x9Efa934D9fAd4AE28c998a40195646b965a97247`.

The constructor remains nonpayable with two static address arguments and no external calls. First-use asset validation, one-time vault approval, rollback on failure, permissionless crediting, project totals, and `Stacked` events are preserved. There is no new owner, administrator, fee, pause, upgrade, token, or deployed contract. The oracle, mocks, build configuration, dependencies and manifest are unchanged. The revision below changes only two registry policy strings for its later launch; it does not change the registry state machine.

## Previously accepted adaptation (historical record)

### Unreachable share recipients — fixed

Finding `bf1a675b10f24655645f202dd9fdf7f7ef69c188d0e0bcc6fcf64bdab18d2168` reproduced before modification: two 1 IMD credits minted positive shares to the Stacker and the vault itself. Both balances are unreachable through their code. A scratch probe reached that state, and the four new rejection regressions failed against the original code because no revert occurred.

- `src/Stacker.sol`: reject `address(this)` and `address(SIMD)` with `InvalidTrader()` before zero-amount handling or dependency calls. These are the only new rejected recipients. `ZeroTrader()` and ordinary self-staking remain unchanged. NatSpec documents the new error. This is the sole production behavior change, justified by the reproduced audit finding.
- `test/StackerAuditRegression.t.sol`: test both invalid recipients, zero amounts, arbitrary amounts, and fresh/already initialized Stackers. Rejections preserve balances, allowances, share supply, hold stamps, totals and logs; a subsequent valid credit succeeds.
- `test/Stacker.t.sol`: point the successful-credit fuzz test's recipient exclusions to their dedicated rejection coverage.
- `test/StackerEdges.t.sol`: exclude the two newly invalid recipients from the fuzz test specifically expecting a paused-vault error. Recipient rejection is exercised separately.
- `test/SepoliaFork.t.sol`: the previous byte-for-byte comparison to launch #1294 necessarily fails after this fix. Replace it with a comparison of valid credits from identical vault state (shares, balances, assets and accounting deltas), and add a fork regression proving that the live legacy Stacker accepts both unreachable recipients while the candidate rejects them. This tests the intended difference without changing the existing Sepolia deployment.

### First-credit gas omission — fixed in integration guidance and coverage

Finding `a919c07fbbc59cd0a79da0998eb3f9cb9529805b8f37a76926b1f4e1764b6e83` reproduced with the local vault copy and the real mainnet pair. A fresh Stacker repeatedly runs out of gas with a 177,000-gas cap and retains zero vault allowance and totals. A sufficiently funded credit initializes it; the same 177,000-gas cap then succeeds for another trader of that project.

- `README.md`: add the provided first-ever credit reference measurement (about 232k whole-transaction gas) alongside the 136k/102k figures, explicitly identifying these as pre-adaptation reference measurements rather than call-gas limits. Explain initialization rollback and the distinction between receipt costs and gas required during execution.
- The integration example now checks `gasleft() >= 410_000` before calling `credit{gas: 350_000}` in `try/catch`, reserving gas for call overhead, EIP-150 and the plain-IMD fallback. Integrators must allow additional gas for their own remaining hook work. The budget supports an unprimed Stacker; it does not assume deployment initializes the vault.
- Document the operator's post-deployment self-credit handoff, confirmation via `Stacked` and vault allowance, and recording the confirmed address and priming transaction/block in the Deployments table. An amount must preview to positive shares; a failed or zero-amount credit does not prime the vault. No priming transaction or mainnet deployment is claimed here.
- `test/StackerGas.t.sol`: reproduce repeated failure under the old cap, test the README budget on a cold first credit, prove the gas guard rejects a low estimate, and test plain-IMD fallback both for a paused vault and for a dependency exhausting its forwarded gas.
- `test/MainnetFork.t.sol`: add the repeated-underfunding regression and a separate cold first-credit test with the documented call budget against the real IMD/sIMD pair.

### Third-party renewal of the vault hold — reproduced, documented

Finding `0a1f3e65e541c23e94afeccd42c72d419fe30292eea961a1bfe3d589ac6976dd` reproduces in the existing `test/VaultTrustRegression.t.sol::test_dustHoldThroughStackerAndDirectVault`, which was run before and after the change. A 1-wei credit renews the hold and blocks redemption; a direct deposit does the same. Redemption succeeds after a block without another hold renewal.

`README.md` now explains that anyone can renew the hold and that next-block redemption is not guaranteed. No minimum deposit, permission gate, or vault change is introduced: the launch uses the existing renounced vault, and a Stacker restriction would not prevent direct deposits. The existing regression already covers this behavior, so no duplicate test was added.

### Review scope note — not a defect

Item `1a181526be5437cdcfef1429d9e809ecdea47283281063b81286145d84719bb2` describes the earlier review's scope, not an additional failing input. Its old runtime size and byte identity to Sepolia are superseded by this adaptation. That round's runtime was 2,528 bytes; the current revision's size is recorded below. Constructor, opcode, accounting, rollback, reentrancy, and custody tests pass. The full registry/oracle suite was retained and run; those contracts are not deployed here. This work does not claim an independent full audit of the live OFT implementation or the later registry launch. Slither and Mythril were not run.

No actionable imported finding was dismissed as non-reproducible. Both low findings reproduced and were addressed; the hold behavior is an existing external dependency property, and the fourth item is informational scope reporting.

## Previous-round verification and handoff (historical)

- `forge build`: passed with the existing solc 0.8.26, Cancun, 10,000 optimizer runs and `bytecode_hash = "none"` configuration.
- `forge test`: 181 passed, 0 failed, 11 fork tests skipped without RPC URLs.
- `ETH_RPC_URL=https://ethereum-rpc.publicnode.com SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test`: 192 passed, 0 failed, 0 skipped. These public RPCs are read-only; all state changes occur only in local fork execution.
- Ran the exact supplied `Contracts.protected.t.sol` from scratch space with final compiled creation bytecode and the existing manifest's arguments, using a local test factory: passed CREATE2 address prediction, empty-chain construction, runtime size and forbidden-opcode checks. Constructor ABI is nonpayable `(address,address)` and creation/runtime bytecode has no library links.
- Formatted the changed Solidity files with `forge fmt`; `git diff --check` passes.

`README.md` retains the 0.25%–1% project choice, funding from existing fees with the outgoing-fee guard, one-time project approval, real-trader resolution (never `tx.origin`), and `try/catch` with plain-IMD fallback. It distinguishes the audited candidate from the already deployed Sepolia version and qualifies the custody invariant: unsolicited direct token transfers are not recoverable.

Only the deployment service can supply the confirmed mainnet Stacker address. The Deployments entry remains honestly pending, with the address and optional priming receipt updates described for that handoff. No wallet keys were read and no transaction was broadcast.

## Revision: independent-review responses

The accepted adaptation above was retained. The following changes address the reopened findings; every finding, including the imported review, also has a verdict in `.imd-responses.json`.

### Router recipient resolution — fixed

Finding `92b47490cb9aef8fe1b298a64fe57e4a1e673dfb6f226d822e03ddda70cf0dbc` reproduced before editing the rules. In `test/TraderResolution.t.sol::test_legacyEmptyHookDataCreditsRouterAndAnyoneCanSweep`, a minimal pool/router model passes the router as the hook's sender with empty data. The Stacker mints shares to that router and records it as trader, then an unrelated caller sweeps the shares. The model isolates the semantics confirmed in Uniswap's [Hooks](https://github.com/Uniswap/v4-core/blob/main/src/libraries/Hooks.sol), [Dispatcher](https://github.com/Uniswap/universal-router/blob/main/contracts/base/Dispatcher.sol) and [Payments](https://github.com/Uniswap/universal-router/blob/main/contracts/modules/Payments.sol); it is not a full Uniswap deployment or a claim about every frontend's encoding.

- `README.md`, `docs/listing.md`, `docs/design.md` and `jobs/4-mainnet-launch.md`: require valid router `hookData`, otherwise the active `IMsgSender(sender).msgSender()`, otherwise `sender` only if it has no code. Preserve smart wallet recipients and never use `tx.origin`. Bound/catch accessor calls and validate destinations. Invalid data can pay plain IMD to a separately resolved valid caller; a failed credit pays the same resolved trader. When no trader can be resolved, no cashback token is sent to a router and the trade continues; the unsupported route must supply trader data before cashback is enabled or advertised.
- `src/ProjectRegistry.sol`: correct only the `trader` definition, shared by applications and challenges. Mirror it in `docs/panel-rules-v2.md` and distinguish these local revisions from the historical Sepolia rehearsal.
- `test/TraderResolution.t.sol`: retain the legacy loss reproduction and test empty data with active caller resolution, explicit data precedence, smart wallets, direct no-code senders, paused-vault fallback, invalid recipients/data, and absent, reverting, gas-exhausting or malformed accessors. This is a test-only example with an explicitly chosen packed 20-byte format; no resolver or router is added to the deployment.
- `test/RegistryPolicyRevision.t.sol`: the rule regression failed on the accepted tree, then passed with the corrected application/challenge rules. Existing JSON/body/property and callback-budget checks continue to run.

### IMD token as share recipient — fixed

Finding `cf16df63af705872d87958aee3b462febc69bc51bb152843a1a8e576e34b7c2d` reproduced in a scratch probe: a 1 IMD credit minted positive shares to the IMD token, consumed the project's funds and recorded the token as trader. Before the production fix, three extended rejection tests failed because no `InvalidTrader` revert occurred.

- `src/Stacker.sol`: add `trader == address(IMD)` to the existing `InvalidTrader` check, before zero-amount handling and all dependency calls. Update NatSpec. This is the only new Stacker behavior change.
- `test/StackerAuditRegression.t.sol`: extend zero/arbitrary-amount and fresh/initialized coverage to IMD, including its share balance and hold stamp in the atomicity snapshot. Add the explicit positive-amount rejection test.
- `test/Stacker.t.sol` and `test/StackerEdges.t.sol`: exclude the newly invalid recipient in the successful-credit and paused-vault fuzz cases, which have separate rejection coverage.
- `README.md` and the launch job: add the IMD token to invalid recipients and distinguish the mainnet candidate from the already deployed Sepolia code. Stacker still accepts legitimate smart wallets; it cannot determine the real trader from a project's arguments.

### LP rebates and the fee floor — fixed in policy

Finding `162145369c381ca5e151563be3d174ed05702b400c78292f291410bdbd724587` reproduces as a cash-flow counterexample in `test/RegistryPolicyRevision.t.sol::test_lpRebateDefeatsGrossFeeFloor`: two normalized 1,000 IMD legs, 1% cashback and 1% LP fees, with 99% of LP fees returning to the trader, give 20 IMD cashback for 0.2 IMD net fees before gas/price movement. The previous gross-fee inequality passes.

- `src/ProjectRegistry.sol`: the `feeGuard` definition now excludes LP fees entirely and excludes other amounts returned to the trader, owner or team. The floor still requires qualifying outflow at least equal to cashback for every allowed setting. Locked principal remains a qualifying category; claimable LP fees do not.
- `README.md`, `docs/listing.md`, `docs/design.md`, `docs/panel-rules-v2.md` and `jobs/4-mainnet-launch.md`: mirror that policy, remove the universal wash-trading-cost claim and qualify the earlier illustrative fee split. The reported LP-only split now has zero qualifying outflow and fails the listing rule. No indexer discount or automatic wash-trade detector is claimed.
- `test/RegistryPolicyRevision.t.sol`: assert the exclusion in both application and challenge bodies, JSON parsing, the per-rule 512-character cap and successful settlement within the existing callback budget. The registry is still not deployed by this launch; the policy revision changes no existing live listing.

### Application-slot squatting — reproduced; state-machine change deferred

Advisory `b4b0143bdaa908ba17f23c179dcf2862b0de5b5d39d5e7a1c24a763f44948c82` is real and was already a documented limit in `docs/design.md`. The retained test `test/RegistryPolicyRevision.t.sol::test_applicationSlotCanBeReoccupiedAfterFailureNoAndExpiry` demonstrates four consecutive applications by a stranger across a failure, a signed no and an expiry, with the legitimate application rejected by `AskOpen` each time. The stranger spends exactly four oracle fees and posts no bond.

The response verdict is `disputed` about fixing this advisory in the Stacker-only launch, not about its reproducibility. No registry state-machine or economic change is made. A forfeiture destination and treatment of unsigned failures/expiry are not specified by the existing application policy; a bond forfeited only on signed no does not address the other cycles, and a cooldown waived for a different beneficiary is bypassable by rotating beneficiary addresses. The later registry launch needs a separately reviewed application-liveness policy. `docs/design.md` and `docs/listing.md` now explicitly say there is no bounded wait or privileged legitimate-applicant slot. The Stacker does not call this registry.

### Test-count drift and imported findings

Finding `41a89fc7255cf5aaf51a87e28cda97a56ec63913eaa483041a21c77d1580fd2d` is partly reproduced: the launch job's 180/172/8 count was stale. This provided checkout actually started at **192 total: 181 passed offline, 11 skipped**, across 29 suites; the reviewer's 210/199 figure is not this checkout's result. The previous ADAPTATION counts are retained above as explicitly historical. `jobs/4-mainnet-launch.md` now gives the current 203-test count, including this revision's 11 new offline tests, and identifies the old gas measurements as pre-guard references.

The imported unreachable-Stacker/vault and gas-guidance defects (`bf1a675b...`, `a919c07f...`) were already addressed in the accepted tree. Their existing rejection, rollback, gas-budget and fallback regressions still pass. The original 177k gas cap still fails as expected; the published 350k call budget succeeds on both the local copy and live mainnet fork. The existing `VaultTrustRegression` dust-hold test reproduces `0a1f3e65...`; the README already describes the renewable hold accurately, and this revision adds no ineffective deposit restriction. Item `1a181526...` is a historical scope note, not a defect. No new full audit of the live OFT or the registry is claimed.

## Current verification and handoff

- `forge build`: **passed**, using the original configuration and vendored dependencies. `forge test`: **192 passed, 0 failed, 11 skipped**, across 31 suites (**203 total**); the skipped tests require RPC URLs.
- `ETH_RPC_URL=https://ethereum-rpc.publicnode.com SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test --match-path 'test/*Fork.t.sol' -vv`: **11 passed**, including five mainnet tests, five Sepolia Stacker tests and one real-Intake test. All state changes were local to the forks.
- After the final registry fallback-wording clarification, reran `SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test --match-contract RegistrySepoliaForkTest -vv`: **1 passed**, including payment to the real Intake and successful listing settlement. The Stacker bytecode was unchanged from the eleven-test fork run.
- The exact supplied protected test, copied into scratch space and supplied the manifest's real arguments and final Stacker creation bytecode, passes empty-chain CREATE2 deployment, predicted address, size and forbidden-opcode checks. Current Stacker runtime: **2,614 bytes**; constructor ABI remains nonpayable `(address,address)`; no library links.
- Added tests use only existing local dependencies and run without RPCs. Scratch probes and the temporary protected harness are not deliverables. No dependency, manifest, build configuration or restricted path was changed.
- `forge fmt --check` for changed Solidity files and `git diff --check`: **passed**. Reviewer-response JSON parses with all nine unique finding IDs, and the documented registry definitions match the contract within the 512-character caps. Slither and Mythril were not run.

The mainnet deployment and any optional priming transaction remain the deployment service's handoff. No keys were read, no transaction was broadcast and no mainnet Stacker address was invented.
