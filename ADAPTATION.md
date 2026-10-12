# Mainnet Stacker adaptation

This launch remains one ownerless `Stacker(IERC20 imd, IStakedIMD sImd)` on Ethereum, using the existing `launch.json` unchanged:

- IMD: `0xD34a99Bc0f67aE1bbd63C660e6d0b0dd03E263B7`.
- sIMD: `0x9Efa934D9fAd4AE28c998a40195646b965a97247`.

The constructor remains nonpayable with two static address arguments and no external calls. First-use asset validation, one-time vault approval, rollback on failure, permissionless crediting, project totals, and `Stacked` events are preserved. There is no new owner, administrator, fee, pause, upgrade, token, or deployed contract. The registry, oracle, mocks, build configuration, and dependencies are unchanged.

## Reproduced audit findings and changes

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

Item `1a181526be5437cdcfef1429d9e809ecdea47283281063b81286145d84719bb2` describes the earlier review's scope, not an additional failing input. Its old runtime size and byte identity to Sepolia are superseded by this adaptation. The final runtime is 2,528 bytes. Constructor, opcode, accounting, rollback, reentrancy, and custody tests pass. The full registry/oracle suite was retained and run; those contracts are not deployed here. This work does not claim an independent full audit of the live OFT implementation or the later registry launch. Slither and Mythril were not run.

No actionable imported finding was dismissed as non-reproducible. Both low findings reproduced and were addressed; the hold behavior is an existing external dependency property, and the fourth item is informational scope reporting.

## Verification and handoff

- `forge build`: passed with the existing solc 0.8.26, Cancun, 10,000 optimizer runs and `bytecode_hash = "none"` configuration.
- `forge test`: 181 passed, 0 failed, 11 fork tests skipped without RPC URLs.
- `ETH_RPC_URL=https://ethereum-rpc.publicnode.com SEPOLIA_RPC_URL=https://ethereum-sepolia-rpc.publicnode.com forge test`: 192 passed, 0 failed, 0 skipped. These public RPCs are read-only; all state changes occur only in local fork execution.
- Ran the exact supplied `Contracts.protected.t.sol` from scratch space with final compiled creation bytecode and the existing manifest's arguments, using a local test factory: passed CREATE2 address prediction, empty-chain construction, runtime size and forbidden-opcode checks. Constructor ABI is nonpayable `(address,address)` and creation/runtime bytecode has no library links.
- Formatted the changed Solidity files with `forge fmt`; `git diff --check` passes.

`README.md` retains the 0.25%–1% project choice, funding from existing fees with the outgoing-fee guard, one-time project approval, real-trader resolution (never `tx.origin`), and `try/catch` with plain-IMD fallback. It distinguishes the audited candidate from the already deployed Sepolia version and qualifies the custody invariant: unsolicited direct token transfers are not recoverable.

Only the deployment service can supply the confirmed mainnet Stacker address. The Deployments entry remains honestly pending, with the address and optional priming receipt updates described for that handoff. No wallet keys were read and no transaction was broadcast.
