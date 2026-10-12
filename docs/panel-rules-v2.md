# Panel rules, version 2 (draft for the mainnet registry)

The rules (`definitions`) the IdentityMD oracle panel reads when it judges a listing. Version 1 is what the deployed Sepolia ProjectRegistry sends; it is fixed in that contract's code. Version 2 says the same things more plainly, after PLEA's two Sepolia applications split the panel ([history, section 17](history.md#17-registry-trial-pleas-first-applications-2026-10-12)). It was rehearsed once on Sepolia and reached a signed answer ([history, section 18](history.md#18-clearer-panel-rules-rehearsed-2026-10-12)).

**In `src/ProjectRegistry.sol` on `main` since 2026-10-12**, approved by the owner together with IMD's Sepolia fixes, for the mainnet registry. Not deployed anywhere yet; the Sepolia registry keeps version 1. The original rehearsal is historical. This launch revision corrects the draft `trader` rule to resolve router callers and the `feeGuard` rule to exclude LP fees and other returns to the trader. These revisions have local regression coverage and are not claimed to be deployed or panel-approved.

## The rules

`<project>`, `<rate>` and `<beneficiary>` are filled in by the registry. Each rule must stay at most 512 characters (IMD's limit) and contain no double quote or backslash (the registry writes them into JSON as they are).

| Key | Rule |
|---|---|
| `trading` | `<project>` is a trading venue (for example a Uniswap v4 hook, a pool or a launchpad). Every call it can make to credit(trader, amount) on the Stacker happens while executing a trade, for the trader of that trade, with IMD from the fees of that trade. A wallet, an unverified contract, or a contract that can call credit outside a trade, for wallets it picks, or with IMD that is not from the trade fails this rule. |
| `trader` | The project never chooses who is credited. Resolve valid router hookData first, else IMsgSender(sender).msgSender() during the swap, else sender only if sender has no code; never tx.origin. Reject zero, Stacker, IMD, vault and forwarding-router recipients. If data is invalid, pay plain IMD to a valid resolved caller. If credit fails, pay its resolved trader plain IMD. Never pay an unresolved router: unsupported routes must supply trader data before cashback is enabled. |
| `otherPayouts` | Cashback that is not credited through the Stacker is allowed and simply earns no points: for example plain IMD paid when credit reverts, or a payout in another form when crediting is not possible. Such payouts never break the trading or rate rules. |
| `rate` | Each credit is `<rate>` basis points of its trade (100 basis points = 1%), and that rate is between 25 and 100. If the rate can change, the code must keep it between 25 and 100 and `<rate>` must be the rate in force now. |
| `feeGuard` | Split each trading fee into cashback, owner/team returns (including withdrawable reserves), and qualifying outflow (burns, prizes to others, third-party payments, locked value as in lockedValue). Qualifying outflow must be at least the cashback for every allowed setting of rate and fee split. LP fees do not count: the trader may also be the LP. Amounts returned to the trader, owner or team do not qualify. |
| `lockedValue` | Liquidity or reserves that no owner or team wallet can ever withdraw count as leaving for good, even if the contract itself can move them between its own positions or pools. |
| `beneficiary` | `<beneficiary>` must be the owner of `<project>`, or a wallet its verified source or its official website names as its team or treasury. (unchanged) |
| `evidence` | Use the verified source published for this address on the chain named in the question, on its block explorer (Etherscan or Blockscout) or on Sourcify; a full or partial match on any one of them is verified source. Use on-chain reads at the latest block. Code with no verified source on any of them, or unreadable code, means false. |

For a challenge, `rate` keeps version 1's challenge form (the rate in force must be within 25-100; the application rate is historical), with the same `otherPayouts` rule.

## What changed from version 1, and why

| Version 1 said | Panel members read it as | Version 2 |
|---|---|---|
| "calls credit … only while executing a trade, for the trader of that trade" | every cashback must be staked, so a plain-IMD fallback (our integration rule 2) or another payout fails | `otherPayouts`: allowed, earns no points |
| "for the trader of that trade" | an address from caller-supplied `hookData` (our integration rule 3) isn't bound to the trader | `trader`: the hookData address counts as the trader |
| "liquidity locked forever" | liquidity the contract can move back into its own reserve isn't locked | `lockedValue`: what no owner or team wallet can ever withdraw leaves for good |
| "the verified source on the block explorer" | Etherscan only; unverified there means false | `evidence`: Etherscan, Blockscout or Sourcify |
| (mainnet condition agreed on 2026-10-11) | | `feeGuard`: true for every allowed setting |

## Results on PLEA's hook (Sepolia, the same question otherwise)

| Rules | Yes | No | Outcome |
|---|---|---|---|
| Version 1, PLEA's first application | 8 | 5 | split, cleared |
| Version 1, PLEA's second application | 9 | 4 | split, cleared |
| Version 2, rehearsal | 11 | 2 | **signed yes** (11 needed) |

With version 2 no member raised the trading, trader, rate or evidence rules. The two "no" answers were about PLEA's own fee split: its owner can enter and win Seasons prizes, and a public `rebalance()` pays a 0.01 IMD keeper tip from the hook's retained IMD to whoever calls it. The margin was exactly the quorum, so one rehearsal is not proof that every panel will agree.
