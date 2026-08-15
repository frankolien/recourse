# Agent settlement on Recourse

System design, architecture, formal properties, and algorithms for retargeting
the deployed escrow at agent to agent commerce.

Written August 14, 2026. Every claim about Arc or x402 below was measured or read
from the spec, not recalled. Sources are named in section 1 so they can be
rechecked when either moves.

The one sentence version:

> x402, but the agent can get its money back.

## 0. Scope

In scope: an autonomous buyer paying an autonomous seller for a service over
HTTP, with funds escrowed under terms both sides can verify before payment, and
a dispute that resolves without a human.

Out of scope for v1: multi hop agent chains, drawdown billing, cross chain
settlement, and anything needing counterparty liquidity.

## 1. Verified ground truth

**Arc testnet, chain 5042002.**

| Fact | Value | How known |
|---|---|---|
| USDC | `0x3600...0000`, proxy to `0xc6ad664a...` | storage slot read |
| EIP-3009 | `transferWithAuthorization`, `receiveWithAuthorization`, `cancelAuthorization`, `authorizationState` all present | selector grep of implementation bytecode |
| EIP-2612 | `permit` present | same |
| Token domain | `name "USDC"`, `version "2"` | eth_call |
| Transfers | delegated to a precompile at `0x1800...0000`, 18 decimals | fork trace |
| Escrow | `0x61Fd9978...`, `resolveDelay` 60s, `yieldFeeBps` 1000 | eth_call |

The EIP-3009 result is load bearing. It means the standard x402 `exact` scheme
works on Arc unmodified, and it gives us a way to pay into escrow gaslessly. Both
were open questions before this was checked.

The precompile result constrains how any of this can be verified. Arc USDC keeps
balances and transfers in a chain level module rather than in token bytecode, so
no local fork can execute a transfer: `forge --fork-url` and anvil both fail with
`StackUnderflow` inside the precompile, and `vm.deal` cannot find the balance slot
behind the proxy. R13's anvil dry run therefore cannot cover Arc value movement.
What a fork does still settle is the half that fails silently in production, the
EIP-712 domain a payer signs under, which `ArcForkAgent.t.sol` reconstructs and
matches against the deployed token.

**x402, from `coinbase/x402` specs, v2.**

Headers on the HTTP transport, all base64 encoded JSON:

| Header | Direction | Carries |
|---|---|---|
| `PAYMENT-REQUIRED` | server to client, with 402 | `PaymentRequired` |
| `PAYMENT-SIGNATURE` | client to server | `PaymentPayload` |
| `PAYMENT-RESPONSE` | server to client | `SettlementResponse` |

`X-PAYMENT` is v1 and is not what we build against. `network` is CAIP-2, so Arc
testnet is `eip155:5042002`. `PaymentRequired.accepts[]` holds one or more
`PaymentRequirements` of `{scheme, network, amount, asset, payTo,
maxTimeoutSeconds, extra}`. There is a first class `extensions` map that servers
advertise and clients echo back, with a JSON Schema declaring its shape.

## 2. Protocol binding

Two ways to attach escrow to x402 were considered.

**Rejected: a bespoke handshake.** Inventing headers gives a demo that
interoperates with nothing, which defeats the reason to adopt a standard.

**Chosen: a new scheme plus an extension.** The `exact` scheme settles by
transferring straight to `payTo`, so it cannot escrow by construction. Escrow
therefore needs its own scheme. The refund terms ride in `extensions`, which is
exactly what that field is for, so an x402 client with no knowledge of Recourse
still parses the payment and simply does not get protection.

```jsonc
// PAYMENT-REQUIRED, decoded
{
  "x402Version": 2,
  "resource": { "url": "https://api.example.com/infer", "mimeType": "application/json" },
  "accepts": [{
    "scheme":  "recourse-escrow",
    "network": "eip155:5042002",
    "amount":  "5000000",                  // atomic units, 6dp, session budget
    "asset":   "0x3600000000000000000000000000000000000000",
    "payTo":   "0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0",   // the escrow
    "maxTimeoutSeconds": 60,
    "extra":   { "name": "USDC", "version": "2" }
  }],
  "extensions": {
    "recourse/v1": {
      "info": {
        "policyId":      "42",
        "policyHash":    "0x...",          // pins the whole agreement
        "merchant":      "0x...",
        "attestor":      "0x...",
        "disputeWindow": 3600,
        "engineVersion": "1"
      },
      "schema": { /* JSON Schema for the above */ }
    }
  }
}
```

`payTo` is the escrow, not the merchant. A client that ignores the extension
still pays correctly and simply forfeits the ability to dispute, which is the
right failure mode: degraded, not broken.

## 3. Architecture

### 3.1 Components

Five, of which we build three.

```
  ┌────────────┐   PAYMENT-REQUIRED    ┌──────────────┐
  │ Buyer agent│ <-------------------- │ Seller agent │
  │            │                       │  + gateway   │
  │  + SDK     │   PAYMENT-SIGNATURE   │              │
  └─────┬──────┘ --------------------> └──────┬───────┘
        │                                     │
        │  pay / fileDispute                  │ verify payment
        v                                     v
  ┌──────────────────────────────────────────────────┐
  │  Arc: RecourseEscrow, PolicyRegistry, USDC        │
  └──────────────────────────────────────────────────┘
                        ^
                        │ submitAttestation
                  ┌─────┴──────┐
                  │  Attestor  │   neutral, named in the policy
                  └────────────┘
```

| Component | Who runs it | We build |
|---|---|---|
| Buyer SDK | the buying agent | yes, TypeScript |
| Seller gateway | the selling agent | yes, TypeScript middleware |
| Attestor service | a neutral third party | yes, reference implementation |
| Escrow, registry | on chain, already deployed | one change, section 6 |
| Facilitator | optional, x402 ecosystem | no |

TypeScript for both SDK and gateway, because that is where agents live and
because `engine/` already has the verdict mirror we need for client side
simulation. The Rust backend does not change. The mobile app does not change.
Swift bindings are a later question, not a v1 one.

### 3.2 Trust boundaries

Three parties, none of whom trust each other, and one contract that trusts none
of them:

- **Buyer and seller** are mutually adversarial. Neither can move the other's
  funds. Both can read every term before committing.
- **Attestor** is trusted only to sign objective facts, and only within the
  bounds the policy already fixed. It cannot invent a refund percentage; it
  selects among outcomes the merchant published in advance. It cannot be the
  merchant, enforced on chain (section 6).
- **Facilitator**, if present, is untrusted. Section 5.2 binds its submission so
  it can only do the thing the buyer signed for.

### 3.3 Why gas is not a problem here

On Arc, USDC is the gas token. An agent holding USDC can pay for its own
transactions, so the facilitator role that x402 exists to provide (gasless
payment for clients holding no native token) is optional rather than required.
We support both: direct `pay()` when the agent transacts for itself, and
`payWithAuthorization()` when a facilitator submits. The second is section 5.2.

## 4. Algorithms

### A1. Vocabulary

`evType` is `uint8`, so eight evidence bits exist. Four are spent on the parcel
vocabulary (PHOTO 1, DESCRIPTION 2, TRACKING_REF 4, VIDEO 8). Four are free:

| Bit | Name | Hash commits to |
|---|---|---|
| 16 | CALL_LOG_ROOT | the running root over every call in the session |
| 32 | SCHEMA_FAILURE | the first non conforming response plus the schema id |
| 64 | SLA_MEASUREMENT | the latency series |
| 128 | UNREACHABLE | probe attempts that got no answer |

Claim types extend the same way, above the parcel range:

```
5  NOT_SERVED         paid, service never answered
6  SCHEMA_VIOLATION   answered, output did not match the advertised contract
7  SLA_BREACH         answered and valid, but outside the promised latency
8  PARTIAL_FAILURE    a session where some fraction of calls failed
```

`attType 2` becomes SLA_OUTCOME. None of this touches a contract, because
`PolicyEngine.compute` only ever compares these values for equality and never
interprets them.

### A2. Bucketed attestation

One escrowed session covers many calls, so the refund must scale with how badly
the service performed. The engine cannot do arithmetic, only equality, so
quantise the failure rate and give each level a rule.

```
given  total  = calls attempted
       failed = calls that did not satisfy the contract
       f      = failed / total

severity(f) =  0 CLEAN     if f == 0
               1 MINOR     if f <= 0.05
               2 MODERATE  if f <= 0.25
               3 SEVERE    if f <= 0.75
               4 TOTAL     otherwise

attType = 2, attValue = severity(f)
```

| attExpected | refundBps |
|---|---|
| 0 CLEAN | 0 |
| 1 MINOR | 1000 |
| 2 MODERATE | 2500 |
| 3 SEVERE | 5000 |
| 4 TOTAL | 10000 |

Five of sixteen rule slots, leaving eleven. Thresholds are published in
`metadataURI` and pinned by `policyHash` through the rules array. Sixteen levels
is the ceiling because `MAX_RULES` is 16.

### A3. Default outcome and who bears attestor downtime

A rule with `attType != 0` cannot match when no attestation arrived, because the
engine requires `i.attType == r.attType`. An unattested dispute therefore skips
every attested rule and lands on a later unattested rule or `defaultRefundBps`.

This makes `defaultRefundBps` the answer to "what happens when the attestor is
silent", which is a liveness question, not a fairness one. Given the attestor
cannot be the merchant (section 6), silence is an operational failure of a
neutral party rather than an exploit by a counterparty.

Rule for authoring agent policies:

- Attested rules first. They are the precise outcomes.
- `defaultRefundBps` set to the value both sides accept for "we could not
  measure". 5000 is the neutral choice; a service competing on trust will
  publish higher.
- `resolveDelay` must exceed the attestor's response SLA, or disputes resolve
  before the attestor can speak. **The deployed value is 60 seconds and it is
  immutable**, so an attestor slower than that requires a redeploy.

### A4. Deterministic evidence

Both sides must derive identical bytes from the same session, or the attestor
has nothing objective to check.

Per call:

```
h[i] = keccak256(abi.encode(
           i, requestHash, responseHash, statusCode, latencyMs, schemaValid))
```

Chained, mirroring what `fileDispute` already does over the evidence array:

```
L[0] = 0
L[i] = keccak256(abi.encodePacked(L[i-1], h[i]))
root = L[n]
```

The dispute carries a fixed set of items regardless of session size:

```
fileDispute(paymentId, PARTIAL_FAILURE, [
    { evType: 16, hash: root },
    { evType: 32, hash: keccak256(failingResponseHash, schemaId) },   // if any
])
```

The full log is published off chain. The attestor and the merchant recompute
`root` and check it against `evidenceRoot` on chain. Nothing is trusted,
everything is recomputed. Cost is constant: five calls and fifty thousand submit
the same two items.

### A5. The settlement loop

```
1  buyer   GET /resource
2  seller  402 + PAYMENT-REQUIRED (section 2)
3  buyer   read policy on chain, check policyHash matches the extension,
           check attestor != merchant, check attestor is one it accepts
4  buyer   run the TS engine mirror over every claimType it might raise.
           free, off chain, answers "what protection do I actually get"
5  buyer   if acceptable: pay(policyId, amount, orderRef = keccak256(sessionId))
6  buyer   PAYMENT-SIGNATURE carrying { paymentId, sessionId, sig } on each call
7  seller  verify on chain: status == Paid, merchant == self,
           amount >= price, orderRef == keccak256(sessionId).
           meter calls against the escrowed budget, stop serving when spent
8  buyer   append a CallRecord per call (A4)

9  end of session
     satisfied    do nothing. after disputeWindow anyone calls release()
     unsatisfied  fileDispute(...) before the window closes;
                  attestor signs a severity bucket; after resolveDelay or
                  immediately once attested, anyone calls resolve()
```

Step 9 is the point of the design. **Doing nothing means paying.** Only failure
requires an action, which is correct for machines: the happy path is one
transaction at each end of a session and no supervision in between.

## 5. Formal properties

### 5.1 State machine

```
        pay()                    fileDispute()              resolve()
None ----------> Paid ---------------------------> Disputed ---------> Settled
                  │  guard: msg.sender == buyer         │
                  │         now <= paidAt + window      │  guard: attested
                  │                                     │   or now >= filedAt
                  │  release()                          │        + resolveDelay
                  └────────────────────────────────────────────────> Settled
                     guard: now > paidAt + disputeWindow
```

### 5.2 Invariants

Numbered so tests can cite them.

- **I1 Conservation.** For a settled payment, `refund + protocolFee +
  toBeneficiary == total` redeemed from the adapter, exactly. Enforced by
  construction: `rest = total - refund` and `toBeneficiary = rest - protocolFee`.
- **I2 Monotonic status.** Transitions follow 5.1 and never run backwards. No
  payment leaves `Settled`.
- **I3 Single settlement.** `resolve()` and `release()` each require a
  non-`Settled` status and set `Settled` before transferring, so at most one
  payout occurs per payment. With `nonReentrant`, this holds under reentry.
- **I4 Policy immutability.** `policyHash(policyId)` is fixed at registration.
  A verdict is a pure function of `(policyHash, VerdictInput)`.
- **I5 Cross implementation parity.** Solidity `PolicyEngine.compute` and the
  TypeScript mirror agree on every vector in `packages/vectors/verdicts.json`.
  This is existing repo discipline and extends to the new claim types.
- **I6 Attestation authenticity.** `attValue` is set only by an ECDSA signature
  from the policy's attestor over `(paymentId, attType, value, deadline)`, bound
  to this chain and contract through `DOMAIN_SEPARATOR`, with the upper `s`
  range rejected for malleability.
- **I7 Authorization binding (new).** An EIP-3009 authorization accepted by
  `payWithAuthorization` can create a payment only for the `policyId` and
  `orderRef` committed inside its nonce, where
  `nonce == keccak256(abi.encode(policyId, orderRef, salt))`. The contract
  recomputes and rejects a mismatch.
- **I8 Attestor separation (new).** A policy's attestor is never its merchant nor
  the zero address, checked in `setPolicyAttestor`, and is immutable once set so a
  buyer's pre-payment check cannot be invalidated afterwards.
- **I9 Agreement pinning (new).** `agreementHash(policyId)` is a pure function of
  `policyHash(policyId)` and `attestorFor(policyId)`, both immutable after
  registration, so the value a buyer quotes before paying still describes the
  agreement at settlement.

### 5.3 Safety and liveness

- **S1 No stranding (liveness).** Every `Paid` payment can reach `Settled`
  without cooperation from any specific party: `release()` opens after
  `disputeWindow`, `resolve()` opens after `resolveDelay`, and both are
  permissionless. No party can withhold settlement.
- **S2 Buyer bound.** A buyer who files within the window receives at least the
  refund selected by the engine, and no counterparty can reduce it except by an
  attestation from a party that is not the merchant.
- **S3 Merchant bound.** After `disputeWindow` closes, no refund is possible:
  `fileDispute` reverts with `WindowClosed`.
- **S4 Adapter risk falls on the beneficiary.** If the yield adapter returns less
  than principal, `refund` is clamped to `total` and the beneficiary absorbs the
  shortfall. The buyer's refund has priority. This is visible in the code today
  and is stated here so it is a decision rather than an accident.
- **S5 Facilitator containment.** A facilitator can submit a buyer's
  authorization but cannot redirect it, by I7. Replay is additionally blocked by
  EIP-3009 nonce consumption on chain.

### 5.4 Threat model

| Id | Attacker | Capability | Status |
|---|---|---|---|
| T1 | Merchant | attests CLEAN over a genuine failure | **closed by I8**: the merchant cannot be the attestor |
| T2 | Buyer | fabricates a failure log and disputes | mitigated: merchant holds the same log, attestor recomputes the root and signs CLEAN |
| T3 | Facilitator | replays or redirects an authorization | **closed by I7** plus EIP-3009 nonces |
| T4 | Attestor | offline during the dispute window | **residual**: falls through to `defaultRefundBps`. Managed by A3, not eliminated |
| T5 | Yield adapter | returns less than principal | contained by S4, loss falls on the beneficiary |
| T6 | Buyer | reuses one paymentId beyond the escrowed budget | metering is the seller's responsibility, step 7. Not enforced on chain |

T4 and T6 are the two live residuals. Both are operational rather than
cryptographic, and both are stated so they are chosen rather than discovered.

### 5.5 Verification strategy

- I1, I2, I3 as Foundry invariant tests over random action sequences
  (`EscrowInvariants.t.sol`, 32k calls each). These are properties over sequences,
  so a handler based suite is the right tool, not unit tests. Every handler action
  swallows its reverts, which means the invariants could pass on an empty run, so
  `afterInvariant` asserts the campaign actually reached paid, disputed, attested
  and settled states.
- I5 by extending `packages/vectors/verdicts.json` with the new claim types and
  keeping both suites green in the same commit, which is the discipline already
  written into `Types.sol` and `PolicyEngine.sol`.
- I6, I7, I8, I9 as unit tests with negative cases (`AgentEscrow.t.sol`): wrong
  signer, the global attestor after a policy names its own, an authorization
  redirected at another policy or another order, a replayed authorization, the
  merchant as its own attestor, and a second `setPolicyAttestor`.
- A4 by differential test: the TypeScript SDK and a Solidity harness must derive
  the same `root` from the same log, both asserting against
  `packages/vectors/session-roots.json`.

A green suite is not evidence on its own, so each layer was mutation tested: the
fold order and the packed `evType` width in A4, and a settlement that strands the
beneficiary residual here. Both were caught by the specific assertion meant to
catch them. One mutation that was not caught, a widened integer inside
`abi.encode`, turned out to be genuinely harmless because that encoding pads to 32
bytes, and the comment claiming otherwise was wrong and has been corrected.

## 6. Contract changes

Three, all small.

**C1. Per policy attestor.** Built on the escrow rather than in `Policy`, which
reverses what this document recommended before the cost was measured.

The original plan added `address attestor` to `Policy` so `policyHash` would
cover it. Surveying the call sites first showed what that actually breaks:
`backend/src/services/chain.rs` declares the `Policy` struct positionally inside a
`sol!` macro, `ArcContractReader.swift` hard checks `tuple.count == 4`, and every
one of the 28 golden vectors carries a policy. It also forces a `PolicyRegistry`
redeploy, which orphans the policies and payments already live on testnet,
including the one sitting in the settlement vault, and breaks the shipped iOS
build against the current addresses.

The escrow already had to be redeployed for C3, so putting the attestor there
costs one contract instead of two and leaves `Policy` untouched:

- `mapping(uint256 => address) public policyAttestor`, set once by that policy's
  merchant and immutable after, so a buyer that checked before paying cannot have
  it swapped underneath the payment.
- `attestorFor(policyId)` falls back to the global attestor while unset, which is
  what keeps every existing parcel policy working unchanged.
- `agreementHash(policyId) = keccak256(policyHash, attestorFor(policyId))` is the
  single value that pins the whole agreement. Quote this to a buyer rather than
  `policyHash`, which covers the rules but not who may attest against them.

What this gives up: `policyHash` alone no longer determines the attestor, so an
offline verifier reconstructing an agreement needs `agreementHash`. That is a
naming change, not a weaker guarantee, because both values come from the same
immutable on chain state and neither can move after registration.

**C2. Attestor separation (I8).** `setPolicyAttestor` reverts when the attestor is
the policy's merchant or the zero address. It closes T1 structurally rather than
by convention: a merchant that can attest against its own dispute defeats the
engine whichever way `defaultRefundBps` points, because it either signs the
outcome it prefers or stays silent for the same effect.

**C3. `payWithAuthorization` (I7).** A new entry point so a facilitator can
submit on the buyer's behalf without becoming the buyer:

```solidity
function payWithAuthorization(
    uint256 policyId, uint128 amount, bytes32 orderRef,
    address from, uint256 validAfter, uint256 validBefore, bytes32 nonce,
    uint8 v, bytes32 r, bytes32 s
) external nonReentrant returns (uint256 paymentId) {
    // EIP-3009 requires msg.sender == to, so only this contract can spend
    // this authorization, and `from` is proven by the buyer's signature.
    if (nonce != keccak256(abi.encode(policyId, orderRef, from))) revert BadNonce();
    usdc.receiveWithAuthorization(from, address(this), amount,
                                  validAfter, validBefore, nonce, v, r, s);
    // ... identical to pay(), except buyer = from rather than msg.sender
}
```

Without C3 a facilitator submitting `pay()` would be recorded as the buyer, and
the real buyer could never dispute or be refunded. That is a correctness bug in
the agent flow, not an enhancement.

## 7. Build order

1. **Vocabulary and engine mirror.** Constants plus new vectors. Hours. No
   contract change, and it makes everything below expressible.
2. **Session recorder and evidence derivation (A4)** in the TS SDK, with the
   differential test against a Solidity harness. Half a day.
3. **Contract changes C1 to C3** with the invariant suite and regenerated
   vectors. One day, and per repo rule R13 the fund moving paths get an anvil
   fork run before anything touches testnet.
4. **Gateway middleware and buyer SDK**, x402 v2 conformant. One day.
5. **End to end demo**: one agent buys inference from another, a second run fails
   its SLA and is refunded without a human. Half a day.

Roughly a weekend of focused work. Each step is demonstrable alone.

## 8. Open questions

- Whether `orderRef` should commit to the advertised contract (schema plus SLA)
  rather than only the session id, so the promise itself is pinned on chain.
  Leaning yes, it is free.
- Who runs the neutral attestor in production. Recourse running it for the demo
  is fine and is not a long term answer.
- Whether T6 metering should move on chain. It needs a call counter the seller
  increments, which costs a transaction per call and defeats session batching.
  Probably stays off chain permanently.
- `resolveDelay` is immutable at 60 seconds. Decide the attestor SLA first, then
  decide whether the agent deployment needs its own escrow instance.
