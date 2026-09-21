# Wager contracts

Wager (WGR) and HandshakeBet implement bilateral statement wagers on Sepolia (chain ID 11155111). This assignment delivers Solidity source, tests and ABI exports. Manifest generation, independent review, source publication, attestation, admission, deployment and the website are separate workflow responsibilities. No transactions were broadcast.

## Build and verify

Use Foundry with Solidity 0.8.26 available in its compiler cache:

```sh
forge build --offline
forge test --offline
forge fmt --check
```

Compiler settings are pinned in `foundry.toml`: Cancun, optimizer 200 runs, no bytecode metadata hash. No FFI or filesystem permissions are enabled. Tests vendor forge-std v1.9.7 source and licenses under `lib/forge-std`, from the official foundry-rs release; no dependency installation or network is needed for verification. Foundry and the pinned compiler are execution-profile prerequisites.

ABI arrays are in `docs/abi/Wager.json` and `docs/abi/HandshakeBet.json`. Regenerate after source changes with `forge inspect Wager abi --json > docs/abi/Wager.json` and the equivalent HandshakeBet command.

## Contract and deployment parameters

| Artifact | Constructor | Behavior |
| --- | --- | --- |
| `src/Wager.sol:Wager` | none, nonpayable | Name Wager, symbol WGR, 18 decimals; exactly 10^27 minor units minted to constructor caller |
| `src/HandshakeBet.sol:HandshakeBet` | `address tokenAddress`, nonpayable | Immutable WGR reference, configured as `$token` by the manifest assignment |

Deploy through ProjectFactory in that order. The factory receives the entire token supply. Neither application ownership nor initialization calls are required. HandshakeBet has no owner, fees, rescue function, upgrades, pause switch, oracle or privileged beneficiary. Its only external calls are to the immutable token. No wallet or key is needed for this source assignment.

The manifest contributor must use kind `evm_project`, token identifier `Wager`, and application identifier `HandshakeBet` with `constructorArgs: ["$token"]`. This assignment intentionally does not create `launch.json`. The authorized pool guidance is native ETH (zero address) on Sepolia, fee 3000, tickSpacing 60, initialPrice `79228162514264337593543950336`; these are configuration parameters, not a valuation. Policy and signed-artifact linkage are service responsibilities. Services supply the factory and final deployment addresses.

## Bet lifecycle and ABI usage

1. The proposer approves HandshakeBet to transfer their WGR, then calls `propose(counterparty, stake, deadline, statement)`. Stake is in minor units, positive and at most `uint256.max / 2`; deadline is a future Unix timestamp with room for seven days. Counterparty cannot be zero, proposer or HandshakeBet. `statement` is a nonzero bytes32 commitment, conventionally `keccak256(UTF-8 statement text)`. Both parties must preserve and agree on the exact text off chain; it is not stored by this contract. The proposer backs the statement being true.
2. IDs begin at zero and increment. Only the named counterparty can call `accept(id)`, strictly before the deadline, with sufficient balance and allowance for the exact matching stake. There is no caller-supplied amount on accept. Proposer may `cancel(id)` while unmatched; anyone may `expire(id)` at or after the deadline if unmatched. Both credit the proposer their stake. Cancellation and acceptance are ordered by transaction inclusion.
3. For accepted bets, each party may call `submitOutcome(id, outcome)` once in `[deadline, deadline + 7 days)`. Outcome 1 means proposer wins (statement true), 2 means counterparty wins (false), and 0 is invalid. Claims are immutable. Equal outcomes credit the full two-stake pot to the agreed winner. Different outcomes immediately credit one stake to each party.
4. At exactly `deadline + 7 days`, submissions close and anyone can call `expire(id)` if still accepted. Zero or one submitted outcome results in both stakes being credited back. Expiration requires a transaction; time alone does not change storage.
5. Each party calls `claim()` to withdraw all their accumulated credits to themselves. No one may claim for another address. Resolution makes no token calls. A failed token payout reverts the claim and preserves credits for retry; it does not reopen a resolved bet.

`bets(id)` returns proposer, counterparty, stake, deadline, statement, state, proposerOutcome and counterpartyOutcome. State values are 0 Missing, 1 Proposed, 2 Accepted, 3 Resolved. `nextBetId`, `token`, `GRACE_PERIOD` and `claimable(address)` are public getters. Resolution details remain in the `Resolved` event (outcome 0 is refund). Proposed, Accepted, OutcomeSubmitted, Resolved and Claimed events cover all application state transitions; ERC-20 transfers and allowance changes emit their standard events. Index events or enumerate `[0, nextBetId)` to show bets in the later frontend.

## Assumptions and operational responsibilities

This is agreement-based escrow, not a truth oracle or an enforceable prediction market. Either party can prevent the other from winning by disagreeing or remaining silent, causing refunds. Funds may be locked until timeout; there is no administrator who can adjudicate statements or accelerate accepted-bet refunds. Parties must choose useful, unambiguous statements and deadlines, monitor outcomes and send claim transactions. A public keeper or either party can expire stale bets. Block timestamps determine the specified boundaries and are not a source of randomness.

Production must use the delivered WGR. Constructor validation checks deployed code, not token authenticity. Deposits and claims require true ERC-20 return values and exact balance changes; fee-on-transfer and no-return tokens are unsupported. Reentrancy guards protect all mutating entry points, and state effects precede token interactions. A malicious immutable token can still lie about balances or deny service; mock tests establish callback and rollback behavior, not arbitrary-token safety. There is no custody key. Direct token donations are not credited and cannot be rescued. Ordinary ETH transfers revert; forced ETH cannot be recovered.

The separate independent adversarial review must examine accepted source and the concrete manifest before deployment. Passing tests is not an audit. Later services publish source, attest, admit and deploy the approved release. The frontend assignment then consumes runtime configuration and ABIs from `dist/imd-deployment.json`, implements the lifecycle above with React/Vite/TypeScript/RainbowKit/wagmi/viem under `web/`, and produces a relative-base static `dist/` build for IPFS, followed by final independent review. Those service and frontend outcomes are not prerequisites for this contract deliverable.

## Validation coverage

Tests cover fixed supply and metadata, exact transfers, finite/infinite/revoked allowances, no mint entry point, factory deployment and forbidden runtime opcodes, both winners and submission orders, disagreement, one/both silent, duplicate and unauthorized actions, invalid terms and IDs, cancellation, exact acceptance/settlement/timeout boundaries, insufficient balance/allowance, multiple-bet fund conservation, failed/short token transfers with rollback and retry, and malicious-token reentry into every mutating application function. Fuzz cases run 256 examples each.
