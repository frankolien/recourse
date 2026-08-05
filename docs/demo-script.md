# Recourse: 3-minute demo script

Target: one continuous story, phone in one hand, browser open. Every number shown is live chain state. Practice once end to end before recording; total speaking time is about 2:45.

## Setup (before recording)

- Phone: Recourse app installed (latest build: new home, Earn tab), buyer wallet funded (a few USDC), signed in.
- A second device or the same phone in merchant mode with a policy published.
- Browser tabs, in order: recourse-arc.vercel.app (landing), /vault, /verify/13.
- Backend healthy (api.frankolien.com/health) and NOT mid-deploy.
- CRITICAL: /health must show demoMode: true or the live attest beat fails.
  Flip DEMO_MODE=true on Railway first and re-check /health.
- Do not push to GitHub during the demo window.

## Beat 1: the claim (0:00 - 0:20)

Say: "USDC payments are final. That is why nobody shops with them. Recourse gives buyers card-style protection with one difference: disputes are computed, not decided. Watch."

Show: landing page hero (real app screenshots), then the phone.

## Beat 2: a protected purchase (0:20 - 1:00)

Do: merchant side, create a checkout: item name, description, photo, amount. Show the share card, and flash the Copy embed code button: "this same checkout is two lines of HTML; any website can take protected payments with a Pay with Recourse button." Scan the card with the plain iPhone Camera app; the app opens straight to review.

Say while the review loads: "The QR carries a hash. The phone refetched the order, rehashed it, and checked the merchant, amount, policy, and chain against what I am about to sign. If any byte were different, payment would be blocked."

Do: pay with Face ID. Show the success screen.

## Beat 3: break it, then prove the outcome (1:00 - 2:00)

Say: "Now the part every marketplace hides in fine print. Say it never arrives."

Do: open the payment, Report a problem, Not delivered, attach a photo, submit with Face ID. Then: "An attestor confirms the objective fact: not delivered. What that fact MEANS was fixed by the policy before I ever paid: rule 0, 100 percent refund. Nobody, including us, can decide otherwise."

Show: the verifier at /verify/13 (the already-settled refund). Point at the two hashes: "This browser just recomputed the onchain verdict from scratch. Solidity says this hash. TypeScript says the same hash. That is the whole trust model: do not trust the verdict, recompute it."

Optional flash: /verify/15, the denied Wrong item claim. "Same engine, honest in both directions. The policy did not cover this claim, so it is 0 percent, and no support agent can be sweet-talked."

## Beat 4: merchants and LPs are not waiting (2:00 - 2:40)

Show: /vault.

Say: "Protection windows lock money for two weeks. Merchants do not wait: the settlement vault fronts them the same minute, takes over the escrow claim, and LPs earn the fee plus the yield the escrow accrues. Share price started at 1.0000; it is 1.0091 today from real settlements, and the next claim reconciles August 7. Buyer protected, merchant paid today, LP earning bounded risk: all three legs live on Arc."

## Beat 5: close (2:40 - 3:00)

Say: "Recourse is a working answer to the open problems in Circle's own Refund Protocol research: immutable policies, deterministic verdicts, productive escrow, instant settlement. Everything you saw is on Arc testnet right now, and every outcome is a hash anyone can recompute."

Show: README with the tx hashes.

## Failure fallbacks

- RPC hiccup on the phone: pull to refresh once; the app retries reads.
- If live payment fails on stage, pivot to payments 13 and 15 on the verifier: the settled story is already onchain and cannot break.
- Backend down: verifier still works (chain-direct); lead with it and say so out loud, it proves the trust model.
