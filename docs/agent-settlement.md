# Agent settlement on Recourse

Plan for retargeting the deployed escrow at agent to agent commerce. Written
August 14, 2026 against the contracts live on Arc testnet (chain 5042002).

The one sentence version:

> x402, but the agent can get its money back.

## Why this and not the other five

Arc publishes six focus areas. Four of them (stablecoin FX, lending, prediction
markets, treasury) need other people's capital already sitting on the chain.
Measured on testnet August 13: the only DEX holds under $600 total and its one
stablecoin pool is mispriced 2.2x, and StableFX is an RFQ escrow behind an
on chain relayer allowlist. That capital does not exist yet, so those four are
not buildable solo today.

Agentic settlement needs no counterparty liquidity. It needs exactly one hard
primitive: hold funds until work is verified, and resolve deterministically when
it is not. That primitive is already deployed.

## What already works unchanged

Verified by reading the deployed sources, not assumed:

- `pay()` takes `msg.sender` as the buyer. No EOA check, no `tx.origin`, no
  signature. A smart account or agent wallet calls it directly.
- `registerPolicy()` is permissionless and sets `msg.sender` as merchant. An
  agent lists its own service and its own refund terms with no gatekeeper.
- `resolve()` and `release()` are permissionless. Any keeper, either party, or
  the agent itself can settle.
- `previewVerdict()` is a free view. An agent computes the exact refund outcome
  before it pays.
- `resolveDelay` is 60 seconds on the live deployment, not days.

The load bearing property is in `PolicyEngine.compute`. It never interprets what
any value means. It does equality checks and one bitmask containment test. So
`claimType`, `evidenceMask`, `attType` and `attValue` are opaque numbers to the
chain, and their meaning is an off chain convention we own.

That is why most of this is a constants change rather than a rewrite.

## A1. Vocabulary

`evType` is `uint8`, so eight evidence bits exist. Four are spent on the parcel
vocabulary (PHOTO 1, DESCRIPTION 2, TRACKING_REF 4, VIDEO 8). Four are free and
become the agent vocabulary:

| Bit | Name | Hash commits to |
|---|---|---|
| 16 | CALL_LOG_ROOT | the running root over every call in the session |
| 32 | SCHEMA_FAILURE | the first non conforming response plus the schema id |
| 64 | SLA_MEASUREMENT | the latency series |
| 128 | UNREACHABLE | the probe attempts that got no answer |

Claim types extend the same way. `claimType` is `uint8` and the engine only
compares it for equality, so the parcel claims (0 through 4) keep their meaning
and agent claims start above them:

```
5  NOT_SERVED         paid, service never answered
6  SCHEMA_VIOLATION   answered, output did not match the advertised contract
7  SLA_BREACH         answered and valid, but outside the promised latency
8  PARTIAL_FAILURE    a session where some fraction of calls failed
```

Attestation types likewise. `attType 1` stays DELIVERY_STATUS. `attType 2`
becomes SLA_OUTCOME, described next.

None of the above touches a contract.

## A2. Bucketed attestation, so one escrow covers many calls

The problem: a session of 500 calls where 40 failed deserves a partial refund,
but the engine only does equality and `refundBps` is a static field on a rule.

The method: quantise the failure rate into severity levels, and give each level
its own rule. The engine's first match wins loop then selects the refund.

```
given  total   = calls attempted in the session
       failed  = calls that did not satisfy the contract
       f       = failed / total                         (0.0 .. 1.0)

severity(f):
    f == 0            -> 0  CLEAN
    f <= 0.05         -> 1  MINOR
    f <= 0.25         -> 2  MODERATE
    f <= 0.75         -> 3  SEVERE
    otherwise         -> 4  TOTAL

attType  = 2                  (SLA_OUTCOME)
attValue = severity(f)
```

The policy declares one rule per level:

| attExpected | meaning | refundBps |
|---|---|---|
| 0 | CLEAN | 0 |
| 1 | MINOR | 1000 |
| 2 | MODERATE | 2500 |
| 3 | SEVERE | 5000 |
| 4 | TOTAL | 10000 |

That is five of the sixteen rule slots, leaving eleven for other claim types.
The thresholds are published in the policy `metadataURI` so a buyer reads them
before paying, and they are pinned by `policyHash` through the rules array.

Finer granularity is available by spending more slots. Sixteen levels is the
ceiling because `MAX_RULES` is 16.

## A3. Silence favours the buyer

This falls out of the engine and is worth stating as a design rule, because it
decides how agent policies must be authored.

A rule with `attType != 0` cannot match when no attestation arrived, since the
engine requires `i.attType == r.attType`. An unattested dispute therefore skips
every attested rule and lands on either a later unattested rule or
`defaultRefundBps`.

So for agent policies:

- Order attested rules first. They are the precise outcomes.
- Set `defaultRefundBps` high, normally 10000.

The consequence is the correct incentive. If the service's attestor goes silent,
the dispute resolves 60 seconds later and refunds the buyer in full. A service
that wants to keep its revenue has to attest, and attesting means committing to
a measurable claim.

## A4. Deterministic evidence

Both sides must derive the same bytes from the same session, otherwise the
attestor cannot verify anything and the whole thing collapses into judgment.

Per call the agent records:

```
h[i] = keccak256(abi.encode(
           i, requestHash, responseHash, statusCode, latencyMs, schemaValid))
```

Chained into a single root, mirroring what `fileDispute` already does to the
evidence array:

```
L[0] = 0
L[i] = keccak256(abi.encodePacked(L[i-1], h[i]))
root = L[n]
```

The dispute then carries a small fixed set of items regardless of session size:

```
fileDispute(paymentId, PARTIAL_FAILURE, [
    { evType: 16,  hash: root },
    { evType: 32,  hash: keccak256(failingResponseHash, schemaId) },   // if any
])
```

The full call log is published off chain through the evidence service the app
already has, so the attestor and the merchant both recompute `root` from the log
and check it against `evidenceRoot` on chain. Nothing is trusted, everything is
recomputed.

Cost is constant. A session of five calls and a session of fifty thousand submit
the same two evidence items.

## A5. The settlement loop

```
1  agent    GET /resource
2  service  402  { price, asset: USDC@Arc, escrow, policyId, sessionId }
3  agent    registry.getPolicy(policyId)
            check merchant, disputeWindow, rules, attestor
4  agent    run the TS engine mirror over every claimType it might raise
            this is free and off chain; it answers "what protection do I get"
5  agent    if acceptable: approve(escrow, amount)
                           pay(policyId, amount, orderRef = keccak256(sessionId))
6  agent    call with X-PAYMENT: paymentId on every subsequent request
7  service  verify on chain: status == Paid, merchant == self, amount >= price
            then serve
8  agent    append a CallRecord per call (A4)

9  end of session:
     satisfied    do nothing. after disputeWindow anyone calls release()
                  and the service is paid
     unsatisfied  fileDispute(paymentId, claimType, evidence) before the window
                  closes; the service attestor signs a severity bucket or stays
                  silent; 60 seconds later anyone calls resolve()
```

Step 9 is the part worth noticing. Doing nothing means paying. Only failure
requires an action, which is the right default for machines: the happy path
costs one transaction at the start and one at the end, and needs no supervision.

## The one contract change

Everything above works on the deployed contracts except this.

`attestor` is a single address on the escrow, settable only by the owner. Agent
commerce needs the attestation to come from a party named per service. Two ways:

**Option A, a mapping on the escrow.** `mapping(uint256 policyId => address)`,
set once by that policy's merchant, immutable after. Small, no parity impact.
The weakness is that it is not covered by `policyHash`, so the buyer has to
check a second value separately.

**Option B, a field on Policy.** `Policy` gains `address attestor`, so the whole
agreement stays verifiable from one hash. This is the correct shape, and it is
the more expensive one: `Types.sol` field order is load bearing, so changing it
means updating the `policyHash` encoding, the `engine/src/hash.ts` mirror, and
regenerating `packages/vectors/*.json`, with both suites green in the same
commit. The repo already documents that discipline.

Recommendation is B. The product promise is that one hash pins the entire
agreement, and an attestor outside the hash quietly breaks that.

Either way `submitAttestation` changes from comparing against the global
`attestor` to comparing against the policy's attestor, falling back to the global
one when unset.

## The unresolved risk

If a merchant names itself as its own attestor, it can sign CLEAN against a real
failure and defeat the dispute. The policy makes that visible before payment, so
a buyer can refuse, but visible is not the same as prevented.

Options, none of them yet chosen:

- Buyer side policy: only transact where the attestor is a neutral third party
  the buyer already trusts.
- Reputation: track attestor behaviour and let agents price it in.
- Engine change: let an attested rule only increase the refund above
  `defaultRefundBps`, never decrease it. Clean incentive, but it changes engine
  semantics and every vector with it.

This is the real open question in the design. It should be settled before any of
this handles money that matters, and it does not block a testnet demo.

## Build order

1. Vocabulary constants and the TS engine mirror additions. Hours, no contract
   change, and it makes A2 through A5 expressible.
2. Session recorder and evidence derivation (A4) in the SDK. Half a day. Testable
   entirely off chain against the existing vectors discipline.
3. Per policy attestor, option B, with the vectors regenerated. Half a day.
4. The x402 handshake on both sides, one agent buying from one agent. A day.

A working demo is a weekend. Each step is demonstrable alone, which matters if
this gets shown to anyone before it is finished.

## Open questions

- Whether the session escrow should ever support drawdown, where the service
  claims incrementally rather than once at the end. It needs a new contract and
  is not worth it until someone asks.
- Whether `orderRef` should commit to the request contract (the schema and SLA
  the service advertised) rather than just the session id, so the promise itself
  is pinned on chain.
- Which side runs the keeper that calls `resolve()` and `release()`, and whether
  it needs to exist at all given both parties are already automated.
