# log.md (append-only, newest entries at the top)

Convention: every session appends one entry above this line's predecessors. Format: date, what was found, what was fixed or decided, what rule the session earned. Never edit or delete past entries.

---

## 2026-07-21: Session 22, wire the merchant lists to the indexer read API

Found: the payments, disputes, receipts, and protection pages still rendered hardcoded arrays (CloudCompute, FileStore, and similar fictional merchants) as Server Components. With the backend read API in place, these should show the real seeded onchain payments, which is the "not mocks" payoff the owner asked for.

Built: web/lib/api.ts (typed client for /api/payments, /api/disputes, /api/policies, /health with USDC and enum formatters mirroring RecourseEscrow.Status and the engine claim-type table), web/lib/use-live.ts (a small fetch-on-mount hook exposing loading, data, and error), and web/components/live-notice.tsx (loading, indexer-offline, and empty states). Converted the four list pages to client components that render live payments: amounts formatted from u128 base units (R1), merchants and buyers shown as short addresses, statuses mapped from the Status enum, disputed rows linking to the dynamic verifier at /verify/{id}, and metrics computed from the live set. Protection joins payments to policy dispute windows to show a real progress bar. When the backend is unreachable the pages show an honest "indexer offline" notice rather than fabricated rows, and the chain-direct verifiable sections stay untouched. NEXT_PUBLIC_BACKEND_URL configures the base (defaults to localhost:8080).

Verified: tsc and eslint clean; production build green, 16 routes, the landing still static and the four list pages now client shells that fetch at runtime. Not yet exercised against a live backend (needs docker compose up plus cargo run locally), so the live rows are wired and type-correct but the end-to-end fetch is unverified here.

Rules earned: when a real data source can be offline, degrade to an explicit offline state, never to fabricated data that reads as real, and keep the independently verifiable sections chain-direct so they work even when the projection is down.

---

## 2026-07-21: Session 21, backend code-review pass (three P1 correctness fixes)

Found: a review of the Session 20 backend flagged three real correctness bugs. (1) In indexer.rs the disputed-payment verdict came from preview_verdict(...).ok(), so a transient RPC failure became None and the upsert overwrote the cached verdict columns with NULL, blanking a disputed payment's verdict for a tick. (2) The projection tables were keyed by paymentId alone with no deployment scoping; paymentIds restart at 1 on a redeploy, so a prior escrow's rows could masquerade as current. (3) /health ran count_payments(...).unwrap_or(0) and returned 200 "ok" even when Postgres was unreachable. The review also raised P2s (state-poller cannot reconstruct tx hashes or events, serial per-record reads, raw startup SQL without migration history, permissive CORS once write routes land) and zero tests.

Fixed: (1) preview failure now logs and yields None while the upsert COALESCEs each verdict column against the stored row, so a transient failure keeps the last-good verdict (verdicts are deterministic and one-way, so old is always safe). (2) added an index_meta single-row table recording the active escrow and chainId; on startup reset_if_deployment_changed truncates payments and policies when the configured deployment differs, so stale rows never linger (the chain is the source of truth, so a truncate loses nothing). (3) /health now depends on the DB probe and returns 503 degraded when the count query fails.

Decided: accept the reviewer's strategic call. The backend stays a thin, rebuildable projection for the merchant lists and disputes; do not grow it into an event indexer for the demo. The P2s are acknowledged and deferred (tighten CORS when attestor write routes arrive; a full event indexer only if the receipts view needs tx hashes). Next backend value is the attestor bot, not more read plumbing. cargo clippy --all-targets clean (zero warnings). Still compile-verified only, not run against live Postgres plus Arc.

Rules earned: a projection upsert must never let a transient source read erase a good cached value (COALESCE, do not overwrite with NULL), and a rebuildable projection of a single deployment should record and check that deployment's identity so a redeploy wipes rather than shadows the old rows.

---

## 2026-07-21: Session 20, Rust backend indexer and read API (actix-web)

Found: the merchant app surfaces still ran on mock arrays. The architecture calls for a Rust backend that indexes chain state, serves reads, stores evidence, and signs demo attestations, with no business logic (R4) and no third verdict implementation (R2). The owner asked for actix-web rather than axum.

Decided: start the backend with the read half (indexer plus read routes); defer evidence store and attestor bot. Use a state-polling indexer (read every payment and policy each tick) rather than event-log decoding, which is simpler and robust at demo scale. Verdicts come from the onchain previewVerdict, never recomputed (R2). Addresses load from deployments/arc-testnet.json at startup (R3). Keep the verifier and policy reads chain-direct on the web so they stay independently verifiable without trusting this service.

Built: backend/ as a Cargo crate with actix-web, actix-cors, sqlx (Postgres, runtime queries so no live DB at compile time), and alloy for chain reads. src/chain.rs models the escrow and registry via sol! and reads paymentCount, getPayment, previewVerdict, policyCount, getPolicy, policyHash. src/indexer.rs polls Arc every INDEX_INTERVAL_SECS and upserts payments and policies, previewing verdicts only for filed disputes. src/db.rs holds the schema (migrations/0001_init.sql, run idempotently on startup), models, upserts, and read queries. src/routes.rs serves /health, /api/payments (optional merchant filter), /api/payments/{id}, /api/disputes, /api/policies, /api/policies/{id}. ops/docker-compose.yml provides Postgres; backend/README.md is the runbook.

Verified: cargo check is clean (zero warnings). alloy 1.8 resolved; the only fix needed was on_http to connect_http. Not yet run against live Postgres plus Arc (needs docker compose up and cargo run locally), so the indexer loop and endpoints are compile-verified but not yet exercised end to end.

Rules earned: a state-polling indexer is a legitimate, lower-risk first cut before event-log decoding, and a read-only backend earns R4 compliance by pulling verdicts from previewVerdict rather than ever recomputing them.

---

## 2026-07-21: Session 17, wallet connect, onchain policy publish, and R5 reconcile

Found: the onboarding (Session 16) set up an account but the web still had no real wallet. The PRD F1 specifies "connect wallet on web" with wagmi v2 and the injected connector for testnet, and publishing a policy onchain was the last open web item. The onboarding also offered Buyer as a web role, which conflicts with R5 (buyer lives on the Flutter mobile app; merchant and LP on the web).

Decided: add wallet connect with wagmi v2 and the injected connector only, scoped to the (merchant) route group via a Providers wrapper so the marketing landing stays static and untouched. The connected address is the policy merchant, so the builder previews the exact hash that registerPolicy will pin. Reconcile R5 by making Merchant the web default, dropping Buyer as a selectable web workspace, and framing buyers as mobile. Hold the vault deposit transaction: it moves USDC, so per R13 it needs a funded wallet to verify, which is not possible here.

Built: lib/wagmi.ts (Arc chain plus injected, ssr true), components/providers.tsx mounted in app/(merchant)/layout.tsx, components/connect-wallet.tsx (connect, disconnect, shortAddress) wired into the shell topbar with the connected address shown on the profile. The policy builder now reads the connected address as the merchant and gained a Publish to Arc panel that calls registerPolicy through useWriteContract and links the confirmed transaction. Added registerPolicy and policyCount to the registry ABI. R5: default role merchant, onboarding web roles are merchant and liquidity provider with a buyers-use-mobile note. next.config.ts ignores the optional connector deps that wagmi bundles but we never use (@x402/* via the Coinbase SDK, React Native async storage via the MetaMask SDK, pino-pretty via WalletConnect).

Verified: tsc and eslint clean; production build green with zero module-not-found warnings, 16 routes, the landing still statically prerendered. The onchain publish path is ABI-correct and compiles, but the actual transaction needs a funded Arc wallet to exercise (untested against a live wallet here).

Rules earned: when a wallet library bundles connectors you do not use, scope its provider to the routes that need it and ignore the unused connectors' optional deps rather than installing them, and keep the preview identity (merchant address) equal to the transaction signer so the previewed hash equals the onchain one.

---

## 2026-07-21: Session 19, Peec-inspired focused onboarding

Found: the previous onboarding used a persistent progress sidebar and oversized editorial headings, making a short setup flow feel like an admin dashboard. Research into Peec AI's hands-on onboarding showed a tighter pattern: magic-link entry followed by a few focused screens for business type, brand details, location, and suggested topics. Its visual layout keeps the active form compact on the left and uses contextual product or customer proof on the right.

Decided: adapt the interaction principle, not Peec's brand. Recourse now presents one decision per screen with compact sans-serif typography, dense selectable rows, a clear black action button, and four-step progress in the supporting panel. Replace Peec's testimonial with truthful Recourse product proof based on implemented workspace, policy, settlement, and verifier capabilities.

Built: removed the persistent setup checklist, moved the active onboarding form into a focused left panel, added a faded dashboard preview and step-aware proof card on the right, tightened every step's spacing and controls, sanitized old buyer roles back to merchant on web, and retained a single-column mobile flow.

Green: web typecheck, lint, all four onboarding steps exercised in-browser, personalized completion verified, 390px mobile width with zero overflow, no console warnings, and git diff check.

Rules earned: reference products should inform interaction hierarchy, not supply borrowed brand content or invented social proof.

---

## 2026-07-21: Session 18, real photography for the sign-in story

Found: the solid green sign-in panel still felt synthetic after removing the decorative gradient.

Decided: use real editorial photography rather than crypto circuitry or generated abstract art. A portrait aerial ocean photograph by Alex Perez provides natural movement, a premium dark palette, and enough negative space for the headline. The image is free under the Unsplash License, stored locally, and documented beside the asset. A single flat overlay exists only for text contrast, not decoration.

Built: searched Unsplash and Pexels candidates, compared a real ocean photograph against an abstract light photograph, selected the ocean crop, resized it to 1440 by 1922, compressed it to a 384 KB WebP, and installed it as the responsive sign-in story background.

Green: source and license recorded, asset localized, and git diff check clean.

Rules earned: prefer real editorial imagery with documented provenance over decorative gradients when a brand surface needs atmosphere.

---

## 2026-07-21: Session 17, replace translucent status decoration with purposeful motion

Found: the soft green status pill and pale shield bubble looked generic and decorative rather than connected to live product state.

Decided: status decoration should communicate behavior. Use the existing ping Lottie for Arc network activity and the existing burst Lottie behind a crisp solid protection mark. Avoid translucent gradient decoration when a real icon or state animation can carry the meaning.

Built: reusable LivePulse and ProtectionMark components, applied them to landing network labels, the payment proof label, the protected-payment receipt, and the dashboard protected-payments summary. Removed the soft fill from the landing eyebrow and replaced the sign-in story gradient with a solid product color.

Green: web typecheck, lint, browser visual check, zero browser console warnings, and git diff check.

Rules earned: purposeful motion should represent live state, not decorate empty space.

---

## 2026-07-20: Session 16, fintech-style onboarding and profile-driven dashboard

Found: the landing page previously skipped directly to a dashboard with a hardcoded user, so there was no credible path from first visit to "Good morning, Frank." Starting with wallet connection would also make the product feel like a DeFi console rather than payment infrastructure.

Decided: D27, use a familiar fintech sequence: sign in, choose the first workspace role, complete a short profile, review role-specific setup, then enter the dashboard. Buyer, Merchant, and Liquidity Provider are product roles; developers continue through documentation rather than becoming an account type. Wallet connection remains secondary and appears only when an onchain action needs it. Until a real auth and embedded wallet provider is integrated, every auth action is explicitly labeled as a simulated testnet demo and no credentials are collected.

Built: /signin with Google, passkey, email, and existing-wallet entry options; /onboarding with four responsive steps and tailored Buyer, Merchant, and Liquidity Provider setup content; a small localStorage-backed demo profile module; personalized dashboard greeting, initials, and profile name; and landing Launch App links routed through sign-in. Verified the complete click path with a renamed user through to the personalized dashboard. Mobile checks at 390px found zero horizontal overflow on both new routes and no console errors.

Green: web typecheck, lint, production build, and git diff check.

Rules earned: none new. Reinforced R6 by clearly separating simulated onboarding from real authentication and wallet infrastructure.

---

## 2026-07-20: Session 15, marketing landing page at the root

Found: the app had no front door. The root redirected straight to /dashboard, so there was nowhere to explain the product to a first-time visitor or a judge. The owner supplied a landing reference whose display headlines are a serif, which conflicts with the Geist-everywhere decision from Session 12.

Decided: build the landing to match the reference and make it the root route, with Launch App and Start building going to /dashboard and Explore the demo going to /verify/5. Resolve the font conflict by scope: add a --serif token (Georgia, offline, no CDN) used only for the landing headlines under a .landing scope, so the app keeps Geist and only the marketing page gets the editorial serif. Flag this so the owner can unify later if they want serif headlines app-wide.

Built: components/landing-page.tsx and the root page, a full landing with a sticky nav (brand, links, Arc Testnet chip, Launch App), a two column hero (serif headline, subcopy, two CTAs, social proof) beside an overlapping product mockup collage (dashboard card, a scalloped protected-payment receipt, a dispute-status card with a timeline, and a floating escrow-earnings sparkline chip), a Powered by Circle stack strip (Arc, USDC, USYC, Gateway, CCTP, Circle Wallets, Paymaster, Nanopayments), a four card feature grid, and a footer. All landing styles are scoped under .landing and collapse cleanly at 1080, 860, and 640 px.

Verified: web tsc, eslint, and the production build are green (14 routes). The root returns 200 and renders the landing (no longer a redirect); the hero CTAs resolve to /dashboard and /verify/5.

Rules earned: when a new reference conflicts with a standing font decision, scope the exception to the surface that needs it rather than reversing the decision app-wide, and name the choice so the owner can decide whether to generalize it.

---

## 2026-07-20: Session 14, policy compiler and the visual policy builder

Found: the policy builder was the last big web piece, and it needed an engine compiler to turn authored JSON (PRD section 6) into the on-chain Rule structs. The risk was R2: the compiler must not become a third implementation of anything. The verdict logic lives in compute and the hash in policyHash, both already mirrored to Solidity.

Decided: make the compiler pure authoring and serialization. It maps claim-type and evidence and attestation names to the numeric struct fields, validates ranges (uint32 windows, bps 0 to 10000, at most 16 rules), and reuses policyHash and compute unchanged. The merchant is supplied separately because on-chain it is msg.sender, not part of the authored JSON. The builder previews only; publishing on-chain needs a wallet and is the next step.

Built: engine/src/compiler.ts (compilePolicy, toSpec, PolicyCompileError, name tables) exported from the package, with engine/test/compiler.test.ts (9 cases). The golden case authors the seed policy #1 spec and asserts it compiles to the exact structs and hash. Web: components/policy-builder.tsx and the /policies/new route, a two column authoring UI (policy settings, add and remove rules with claim type, evidence, attestation, window, refund, return) that live-compiles to the policy hash, shows the compiled Rule structs, tests a sample claim through compute, and copies the authored JSON. The /policies "New policy" button now routes here.

Verified: engine typecheck and 24 vitest cases green; web tsc, eslint, and the production build green (14 routes). The builder's default spec is policy #1, and its compiled hash rendered server-side as 0xc5a2b6c0d2ca...41fa892f, which is byte-for-byte the on-chain policyHash(1) read from Arc. Authoring JSON to TS compiler to Solidity registerPolicy all agree.

Rules earned: a compiler that sits next to a canonical engine earns its keep by reusing the engine's hash and compute, never by re-deriving them, and a golden test that ties the authored default to a live on-chain hash proves the whole chain in one assertion.

---

## 2026-07-20: Session 13, panel padding, Lottie accents, and a verifier dead end

Found: three issues surfaced while reviewing the new merchant routes. The base .dash-panel class had no padding (the dashboard's own panels each set their own via variant classes), so the new bare panels rendered flush to the border. The public verifier had no link back into the app: its logo and its "Public verifier" back link both pointed at /verify/5, the page itself, so they were no-ops and the page felt like a dead end. And the app used only static icons with no motion.

Decided: give the base .dash-panel a default 22px padding (the dashboard variants declare their own later and still override). Point the verifier logo and back link at /dashboard, relabel the back link "Back to app". Add Lottie for motion, but self-hosted and on-brand: use lottie-web directly (the MIT core has no React peer dep, so it installs against React 19 where the common React wrappers cap at 18), dynamic-imported inside a small client wrapper so it stays out of SSR and loads as a lazy chunk. Author the animation JSON by hand in brand green rather than pulling from a CDN, matching the offline, no-CDN posture used for fonts and seeding.

Built: components/lottie-player.tsx (dynamic import, reduced-motion aware, destroy on unmount), three hand-authored animations (loader, ping, burst) in lib/lottie, wired into the verify and policies loading states, the verify hash-match success (a ring burst behind the check), and the live indicators (the "Live on Arc" pill and the Arc Testnet chip on every merchant page).

Verified: production build is green (13 routes), tsc and eslint are clean, every route returns 200 with no SSR error from the JSON imports or the client player, and the verifier logo and back link resolve to /dashboard. lottie-web stays a lazy chunk, so First Load JS moved only 1 kB.

Rules earned: a control that looks like a back affordance must lead somewhere other than the current page, and a shared base class that expects per-variant padding will bite the next author who uses it bare, so give the base a sane default.

---

## 2026-07-20: Session 12, Geist typeface, real routing, and a full merchant app

Found: the dashboard was the only real merchant route. Its sidebar navigation mostly pointed at /verify/5 or dead # anchors, the shell was hard coded inside the dashboard component, and the app used Georgia and Inter rather than the requested xend.global typeface. xend.global was inspected directly and runs on Geist and Geist Mono (the Vercel typeface).

Decided: adopt Geist across the app through the self-hosted geist package (offline woff2, no CDN), keeping the design system intact by only swapping the three font tokens. Extract the sidebar and a persistent topbar into a shared MerchantShell driven by usePathname, mount it through a (merchant) route group layout so the sidebar persists across navigation and the active item and section title are always correct. Then give every navigation destination a real page instead of a redirect.

Built: MerchantShell (pathname active state, section title, persistent topbar, notification and profile links), a (merchant) route group, and eight routes: /payments, /protection, /disputes, /receipts, /vault, /policies, /settings, /support. The dashboard moved into the group and shed its embedded shell. Pages reuse the existing panel, table, and card vocabulary and add a small shared set (metric cards, records tables, status pills, address rows, toggles, how-steps). /policies reads policy #1 live from the registry and renders its rules and onchain hash. /vault and /settings surface the real contract addresses from deployments/arc-testnet.json with ArcScan links. The verifiable Arc payments (5 refunded, 6 denied) are linked from /payments, /receipts, and /disputes so the public proof is one click from the app.

Verified: production next build is green (13 routes), tsc --noEmit and eslint are clean, and every route returns 200 (root 307 to /dashboard). Confirmed the built CSS ships Geist @font-face with real woff2 files and defines --font-geist-sans, so the typeface loads rather than falling back. Confirmed server-rendered active nav and section title are correct on a sub-route, and that no href resolves to a dead anchor.

Rules earned: when a user asks for a specific site's font, inspect that site's stylesheet to identify it rather than guessing, and prefer the self-hosted package over a CDN so the app stays offline safe.

---

## 2026-07-20: Session 13, full landing page product narrative

Found: after the credibility pass, the landing page still ended after four feature cards and did not explain the mechanism, public verification, user roles, vault economics, or the prototype’s limits. The short page looked polished but left judges and prospective users to infer the core product story.

Decided: expand with product-specific context rather than generic marketing blocks. The narrative order is value proposition, capability summary, four-step flow, live verification proof, aligned buyer and merchant and LP incentives, vault return equation, operational FAQs, then final demo actions.

Built: a four-step workflow section, live Solidity versus browser hash proof card, three audience value cards, vault economics section, five-question semantic FAQ accordion, and closing launch banner. Navigation now points About to the workflow and For Merchants to the dashboard. Added responsive layouts for every new section, including stacked workflow cards, single-column audience cards, a mobile vault equation, and readable FAQ spacing.

Verified: TypeScript, ESLint, and the production build are green. Desktop structure renders once for every section, mobile width remains exactly 390 pixels with no overflow, the FAQ anchor and accordion render correctly below the sticky header, and the browser console is clean. The full-page browser capture repeated content due to a stitching artifact; DOM counts confirmed one instance of each section.

Rules earned: landing page length should come from answering real product questions in narrative order, not from adding decorative filler sections.

---

## 2026-07-20: Session 12, landing page credibility and responsive polish

Found: the landing page claimed a broader Circle integration stack than the prototype currently implements, showed a protected total that did not equal its visible payments, mixed developer and product CTAs, used placeholder portrait avatars as social proof, and stacked four large mockup cards vertically below 1400 pixels. The desktop collage also allowed floating cards to escape its visual boundary.

Decided: make every above-the-fold claim demonstrable. The eyebrow now says Live on Arc Testnet, the trust row reports the live contract, eight seeded payments, and hash-verified verdicts, and the stack lists Arc Testnet, USDC, the USYC adapter, and the deterministic engine only. The primary CTA opens the live proof demo and developer documentation is secondary.

Built: reconciled the protected total to $464, rewrote the hero around immutable refund rules and evidence-based outcomes, removed placeholder avatars and unsupported integration marks, contained and rebalanced the desktop product collage, improved body contrast, and replaced the laptop breakpoint with a stable two-column layout. Mobile now hides decorative side cards and shows one readable protected-payment receipt.

Verified: production build, TypeScript, and ESLint are green. Visual checks passed at 1440 by 900 and 390 by 844. Mobile document width equals viewport width with no horizontal overflow, and the browser console is clean.

Rules earned: marketing claims must map to implemented capabilities, and decorative product collages need a single contained mobile focal point rather than stacking every desktop layer.

---

## 2026-07-20: Session 11, dashboard corrected to the supplied reference

Found: the first web delivery made the verifier the visual home, but the owner’s reference was the full account dashboard. The verifier was functionally correct but was the wrong primary surface and could not resemble the requested 1536 by 1024 dashboard screenshot.

Decided: keep the verifier as the public proof route, add the dashboard as its own surface, and redirect the root to /dashboard. Match the reference directly rather than stretching the verifier shell into a dashboard.

Built: /dashboard with the fixed buyer sidebar, account and network controls, USDC balance, protected payment and action summaries, monthly spend chart, active protection table, dispute timeline, recent activity, escrow earnings, learning cards, and support panel. Added responsive fallbacks for narrower screens while preserving the dense desktop composition.

Verified: rendered at the reference 1536 by 1024 viewport and visually compared against web.png. Content start, sidebar width, card grid, table density, dispute tracker, and right rail now align closely with the target. Browser console is clean. TypeScript and the production build are green; the unused import found by ESLint was removed.

Rules earned: when a user provides a target screenshot, the default route and information architecture are part of the visual requirement, not just the palette and component styling.

---

## 2026-07-20: Session 10, public verifier web experience

Found: web/ was still empty, while the seeded Arc deployment already exposed every read needed for the demo weapon through getPayment, getPolicy, policyHash, and previewVerdict. The seeded refunded and denied claims do not make evidence alone decisive, so a direct evidence toggle on the chain inputs would not demonstrate the promised outcome change.

Decided: build the verify surface before the dashboard, as required by the dependency order. The app reads Arc through dRPC in the browser, imports @recourse/engine rather than copying verdict logic, and sources contract addresses from deployments/arc-testnet.json. The sandbox includes an explicit local evidence-test preset that selects the damaged claim with no photo, then adding Photo changes the result from Denied to Refunded under Rule 2 without writing to chain.

Built: a Next.js App Router app in web/, public /verify/[paymentId] routes, responsive Recourse shell based on the supplied editorial dashboard reference, live payment and immutable policy panels, Solidity eth_call versus TypeScript hash comparison, refunded, partial, and denied stamp states, evidence sandbox, and demo links for payments 5 and 6.

Verified: npm build, TypeScript, and ESLint are green. Browser checks against live Arc confirmed payment 5 is Refunded 100 percent with matching hash 0x683e3c325e6e...bc650f, payment 6 is Denied with matching hash 0x87c2706fa4b2...421bb9, the evidence preset plus Photo changes the local result to Refunded under Rule 2, and the browser console has no warnings or errors.

Rules earned: none new. Reinforced R2 and R3 by importing the existing engine and deployment JSON directly.

---

## 2026-07-20: Session 9, demo state seeded and verified on Arc

Found: the public Arc RPC (rpc.testnet.arc.network) rate-limits hard and returns "request limit reached" as a JSON-RPC error that viem's transport does not retry, so the seed died on the first receipt poll across several attempts (each stranding a little USDC in a fresh funding address). Two other public endpoints answer without auth: dRPC (arc-testnet.drpc.org) and thirdweb (5042002.rpc.thirdweb.com).

Decided: D22, the seed wraps every RPC call in explicit backoff-retry that recognizes rate-limit and transient errors, reads counts once instead of per payment, and sleeps between txs; recommend running against dRPC rather than the official endpoint. D23, shrank seed amounts to 0.25 USDC per payment; the seed generates fresh (non-blocklisted) buyer and merchant keys on Arc and records their addresses in the pointer file.

Verified on Arc via dRPC: policyCount 1, paymentCount 8, payment 5 REFUNDED 100% (previewVerdict 10000/matched, status Settled, verdictBps 10000), payment 6 DENIED (previewVerdict 0, ruleIndex 255), payment 7 beneficiary == vault, vault.outstanding 0.25 USDC. Payment 5 settling a full refund without reverting confirms the underflow fix works on the live fixed contracts. Committed deployments/seed-arc-testnet.json (policyId 1, refund 5, deny 6, advanced 7).

Rules earned: none new.

---

## 2026-07-20: Session 8, redeploy with the fix and a viem seeder for Arc

Found: Arc's USDC is a native-token precompile (0x1800...0000). forge script executes run() locally to build its transaction list, and that local EVM cannot run the precompile, so any USDC movement reverts with StackUnderflow during forge's local execution. This is why the forge deploy worked (it moves no USDC) but the forge seed could not run on Arc, while cast send and the deploy's separate buffer transfer worked (they broadcast directly to the real node). The anvil dry-run hid it because local USDC is a plain ERC-20.

Decided: D21, the seeder is viem (direct RPC broadcast), not forge, so it runs on Arc; the forge Seed.s.sol was removed to avoid two seeders. Kept chain-aware funding (mint on local, deployer USDC transfer on Arc) and EIP-712 attestation via viem signTypedData against the same domain (RecourseAttestor / 1 / chainId / escrow). It lives in engine/scripts/seed.mjs to reuse the engine's viem dependency.

Built: engine/scripts/seed.mjs. Dry-ran end to end on anvil (deploy via forge, seed via viem): policyCount 1, paymentCount 8, payment 5 REFUNDED 100%, payment 6 DENIED, payment 7 beneficiary == vault, outstanding 1 USDC. Removed contracts/script/Seed.s.sol.

Redeployed the fixed contracts to Arc and verified on-chain: escrow 0x61Fd99789B28582882a3369E2024AeaE5b5D2DC0, registry 0x94f8551fbE43aB919D87c3951394b148c914430E, vault 0x5d8a3000866493f5D0B5B07a4Ad63ADE3B02054D, adapter 0x2336AaBE139b7F426aF63f713b9f93CD3FFC6204. escrow.adapter/vault/usdc all correct; 10 USDC buffer at the new adapter; escrow bytecode grew (clamp) and adapter bytecode grew (ceil), confirming the fix is on-chain. Updated deployments/arc-testnet.json to the new addresses.

Then, running the viem seed on Arc, hit a second Arc-specific gotcha: Circle's USDC on Arc has a blocklist, and the well-known anvil merchant key (0x7099...79C8) is on it, so the deployer's USDC transfer to it reverted with "Blocked address". Fixed: on Arc the seed defaults the buyer and merchant to fresh random keys (generatePrivateKey), which are not blocklisted and are funded in-script; local dry-runs still use the anvil keys, which have ETH gas and no blocklist on the mock USDC. Also shrank amounts (0.25 USDC per payment) so re-runs are cheap, and the seed now records the merchant and buyer addresses in the pointer file.

Rules earned: none new (reinforces R13: the anvil dry-run and the Arc run exercise different USDC implementations; here Arc added both a native-precompile constraint and a blocklist that local testing cannot surface).

---

## 2026-07-20: Session 7, seed script and a settlement-underflow fix it caught

Found: writing the seed and dry-running it on a local anvil surfaced a real bug in the deployed contracts. MockUSYCAdapter floored shares on deposit and assets on redeem, so a deposit made when the index was already above 1.0, then redeemed after a short hold, returned a wei less than principal. In resolve() a full refund then computed toBeneficiary = total - refund - fee with total < refund and underflowed, reverting the settlement. On Arc this would brick any refund resolved soon after payment. Simulation hid it because forge runs all script txs at one timestamp (no index drift); only the real broadcast, with advancing block timestamps, triggered it.

Decided: D20, fix at the source and defensively. The adapter now rounds shares up on deposit so redeem never returns less than principal (guarantee: floor(ceil(a*W/i)*i/W) >= a); the extra wei is covered by the yield buffer. resolve() also clamps: refund is capped at total and the fee at the remainder, so a settlement can round a wei short but never reverts. Release was already safe.

Built: src/Seed.s.sol (multi-key via per-actor broadcast blocks; reads deployments/<network>.json; chain-aware funding: mint on local, deployer USDC transfer on Arc which also credits native gas; one policy, eight payments, two disputes attested to opposite verdicts, one vault advance; writes deployments/seed-<network>.json pointers). Fixed the adapter and escrow, added a regression test (test_resolve_fullRefund_shortHold_noUnderflow) that warps the index above 1.0 before paying and resolves immediately. Verified on anvil end to end: deploy, seed, then cast reads confirm policyCount 1, paymentCount 8, payment 5 REFUNDED 100% (verdictBps 10000, Settled), payment 6 DENIED (default, ruleIndex 255), payment 7 beneficiary == vault with outstanding 1 USDC.

Consequence: the first Arc deploy (commit ca3a5d2) has the buggy contracts and is now stale. Redeploy with the fix before seeding or demoing; handoff.md carries the runbook and a STALE marker.

Rules earned: R13, verify money-moving scripts against a real node (anvil), not just forge simulation; simulation runs at a single timestamp and hides time-dependent rounding.

Green: forge 13 tests, vitest 15 unchanged.

---

## 2026-07-20: Session 6, live deployment to Arc testnet

Found: the deploy went through cleanly. The forge broadcast console summary mislabels which address is which contract, so the authoritative sources are deployments/arc-testnet.json (written by the script) and on-chain reads.

Built and verified: deployed PolicyRegistry, MockUSYCAdapter, RecourseEscrow, and SettlementVault to Arc testnet (chainId 5042002), wired escrow.setVault, and funded the adapter with a 10 USDC yield buffer. Addresses: escrow 0x18BfF4cF4c0843EF17c0f12e7E5C940683e930a1, registry 0x4b1A69eBEbBb3aF4dD8741c78065DE3d271C1483, vault 0x2Fa3Aa1BD0cBb04B0e68Ca97bbf53Aa08e44a163, adapter 0x53678a5aeBeACeed4A6Efc3a5F9c22DcFF4d772D. Verified every wire on-chain with cast: escrow.usdc/registry/adapter/vault all correct, resolveDelay 60, yieldFeeBps 1000, attestor and treasury both the deployer 0xD6c574461d96Ee708f58Fe553049aD4f48BB983A, adapter.index just above 1e18, registry.policyCount 0, and 10 USDC sitting at the adapter. The buffer transfer target matched arc-testnet.json.yieldAdapter, confirming it landed on the real adapter despite the console mislabel. Total deploy cost about 0.10 USDC.

Committed deployments/arc-testnet.json as the address source of truth. engine/src/addresses.ts stays gitignored (regenerated by codegen). This clears the deployed-core-contracts core of Checkpoint 2.

Rules earned: none new. Note: the deploy was run by the user with their funded throwaway key; Claude verified the result on-chain but ran no broadcast (R11).

---

## 2026-07-20: Session 5, Arc testnet config pulled and verified

Found: the Arc testnet endpoints and Circle contract addresses, pulled from docs.arc.io (contract-addresses and connect-to-arc pages) rather than guessed, then verified live over the RPC. RPC https://rpc.testnet.arc.network returns chainId 5042002; USDC 0x3600...0000 reports 6 decimals and symbol USDC; the USYC Teller 0x9fdF14c5B14173D74C08Af27AebFf39240dC105A has bytecode. USDC and EURC addresses match what the architecture already documented.

Decided: D19, the immutable Circle-provided network facts live in deployments/arc-config.json (rpc, chainId, explorer, faucet, USDC/EURC/USYC, USYC Teller, CCTP, Gateway), with a source-and-verification note; secrets and per-deploy env live in .env.example (keys blank, never committed). This satisfies "pulled from docs.arc.io into config, never guessed."

Built: deployments/arc-config.json, .env.example, and a deploy runbook in handoff.md. Reframed the deploy blocker honestly: the endpoints are no longer the blocker; a live deploy now only needs a funded throwaway DEPLOYER_PK and a go-ahead to broadcast (an outward action not fired unilaterally). USYC access is still pending, so MockUSYCAdapter stays wired; the Teller adapter is a redeploy once approved.

Rules earned: none new. Reinforced the docs-over-memory rule for chain addresses.

---

## 2026-07-20: Session 4, deploy and codegen pipeline

Found: a real Arc deploy is blocked on the RPC and the real USDC address, but the deploy wiring (constructor args, setVault, buffer funding) and the address codegen can be written and fully verified locally without Arc.

Decided: D16, the deploy script picks its output filename by chainId: Arc (5042002) writes deployments/arc-testnet.json and requires RECOURSE_USDC; any other chain writes deployments/local-<chainId>.json, so a local dry-run can never clobber the canonical Arc address book. D17, generated address books (engine/src/addresses.ts) and local dry-run deployments (deployments/local-*.json) are gitignored; the real deployments/arc-testnet.json is committed after an Arc deploy as the address source of truth. D18, codegen is a small node script (ops/codegen.mjs) rather than Solidity, since it emits typed TS; it takes the deployment JSON path as an argument and is structured to add backend and mobile targets later.

Built: contracts/script/Deploy.s.sol (env-driven: RECOURSE_USDC, RECOURSE_ATTESTOR, RECOURSE_TREASURY, RECOURSE_YIELD_FEE_BPS, RECOURSE_RESOLVE_DELAY, RECOURSE_ADAPTER_BUFFER; deploys registry, adapter, escrow, vault, wires setVault, funds the mock buffer on the local path, and writes the address book). ops/codegen.mjs (emits engine/src/addresses.ts). Added ../deployments to fs_permissions. Verified end to end with a local in-memory dry-run: deploy wrote deployments/local-31337.json, codegen produced engine/src/addresses.ts, and tsc accepted it. Dry-run artifacts removed and gitignored.

Rules earned: none new.

---

## 2026-07-20: Session 3, M1 stateful contract layer (escrow, adapter, vault)

Found: three design points the docs left implicit. One, a simulated yield adapter has no external yield source, so redeem can only pay principal plus yield if the adapter holds a USDC buffer. Two, the doc says assign is callable by "the current beneficiary," but at advance time the beneficiary is the merchant while the caller is the vault, so that phrasing cannot implement T+0. Three, distributing exactly the redeemed total without dust needs one payout computed as the residual.

Decided: D12, MockUSYCAdapter pays yield from a pre-funded USDC buffer (deploy and tests fund it) and tracks per-caller shares so it cannot be drained by a stranger; the real Teller has its own source and the swap stays a redeploy. D13, the escrow stores a trusted owner-set vault address and assign is vault-only; the vault's advance pays the merchant net and checks enrollment and caps first, so the merchant is never harmed. This is a deliberate refinement of the doc's "only current beneficiary." D14, resolve and release pay the buyer refund and the treasury yield fee, then the beneficiary receives the residual, guaranteeing buyer + protocol + beneficiary == redeemed total with no dust. D15, the vault carries advances at par in totalAssets (idle + outstanding); reconcile decrements outstanding after settle so realized PnL flows into share price, with a documented transient between the escrow payout and reconcile.

Built: src/interfaces/IYieldAdapter.sol, src/MockUSYCAdapter.sol (linear 4.5% APY index, deterministic per timestamp). src/RecourseEscrow.sol (pay sweeps into adapter; fileDispute derives evidence mask and root; submitAttestation verifies an EIP-712 signature from the attestor with an s-malleability guard; resolve computes the verdict via PolicyEngine, redeems, splits funds, emits Resolved with the verdictHash; release for the happy path; assign vault-only; previewVerdict is the eth_call surface; getPayment for the vault and backend). src/SettlementVault.sol (minimal ERC-4626-shaped shares; deposit, withdraw bounded by idle, enrollMerchant owner-gated, advance pays T+0 and takes assignment, reconcile realizes PnL). Installed OpenZeppelin v5.1.0 as a pinned submodule (ReentrancyGuard, Ownable, SafeERC20, ERC20 for the test USDC only). test/mocks/TestUSDC.sol (6 decimals). test/EscrowVault.t.sol: 7 integration tests asserting exact USDC movement and conservation across happy-path release, attested full refund, un-attested resolveDelay deny, and the vault advance / reconcile profit and loss paths.

Green: forge 12 tests (5 core plus 7 integration), vitest 15 unchanged.

Rules earned: none new. Reinforced R1 (all product USDC through the 6-decimal ERC-20 interface) and the security posture in architecture section 10 (nonReentrant on all fund movers, checks-effects-interactions, exposure caps, resolveDelay guard).

---

## 2026-07-20: Session 2, M2 TS engine mirror and hash parity

Found: M0 left the vectors carrying only expected verdict fields, not hashes, so parity could only be asserted on the decoded verdict, not on the keccak256 outputs the verify page relies on. verdictHash also needs a paymentId, which the vectors lacked.

Decided: D10, the canonical policyHash and verdictHash per case are generated from the Solidity engine (the source of truth) into packages/vectors/hashes.json by a forge script (script/GenVectorHashes.s.sol), kept as a separate generated file so verdicts.json stays hand-authored. Both suites assert against it: forge as a regression lock, vitest as the parity check. D11, each vector carries an explicit paymentId; it is not derived from iteration index because forge parseJsonKeys order and JS Object.entries order are not guaranteed equal.

Built: added paymentId to all 14 vectors. Factored the forge vector reader into test/VectorReader.sol (inherits CommonBase, shared by the test and the generator script). GenVectorHashes script writes hashes.json; extended the forge suite to assert policyHash and verdictHash against it. engine/ TypeScript package: types.ts (mirror structs, timestamps as bigint), engine.ts (compute, identical branch logic to Solidity), abi.ts (viem ABI param defs in Solidity struct order), hash.ts (policyHash/verdictHash via viem encodeAbiParameters + keccak256; merchant lowercased to bypass viem checksum validation without changing the encoded bytes), index.ts. vitest loads the same two golden files, rebuilds the SoA rules, and asserts verdict fields plus both hashes byte-for-byte. Green: forge 5 tests, vitest 15 tests, tsc clean.

Rules earned: none new; reinforced R2 (engine changes ship with regenerated vectors/hashes and both suites green in one commit).

---

## 2026-07-20: Session 1, M0 deterministic core

Found: clean slate, only docs/ present, no git repo, no scaffold. Toolchain available: forge 1.7.1 (solc 0.8.28), node v25.8.2, cargo nightly; Flutter not needed until M4. Foundry's vm.parseJson decodes arrays of structs by alphabetical key order, a known gotcha that makes the naive vector schema fragile.

Decided: D9, golden vector schema is a top-level JSON object keyed by case name, with each policy's rules stored struct-of-arrays (one array per Rule field). Confirmed by a throwaway probe that vm.parseJsonKeys(json, "$") iterates cases, vm.parseJsonUintArray and vm.parseJsonBoolArray read the SoA fields (empty arrays included), and scalar-by-path reads work. This sidesteps the alphabetical array-of-structs decode gotcha and maps trivially to Object.entries in the TS mirror. This is a deliberate deviation from the illustrative array-of-objects format shown in architecture section 4; the semantics and the expect fields are unchanged.

Built: monorepo scaffold (contracts, engine, packages/vectors, backend, web, mobile, deployments, ops). Foundry project in contracts/. Types.sol (ClaimType enum, Rule, Policy, VerdictInput, Verdict; field order fixed for hash parity). PolicyEngine.sol (canonical pure library: first-match-wins, evidence bitmask subset check, attestation type-and-value match, inclusive [paidAt, paidAt + claimWindow] window, filedAt-before-paidAt guard, NO_RULE = 255 default). PolicyRegistry.sol (immutable, ids from 1, 16-rule bound, policyHash = keccak256(abi.encode(merchant, disputeWindow, defaultRefundBps, rules))). Golden vectors v1: 14 cases covering match, superset evidence, missing evidence, late window, boundary-inclusive window, attestation satisfied/failed/missing, first-match-wins, unknown claim type, filed-before-paid, and nonzero default. forge suite green: 14 vectors via one iterating test plus 4 registry tests (id increment, round-trip, hash formula, TooManyRules revert).

Rules earned: R10, comment with purpose only, never restate the code. R11, no GitHub push and no Co-Authored-By: Claude trailer in commits. R12, confirm the approach (research, subagents) before writing non-trivial code.

---

## 2026-07-20: Session 0, project founding

Found: Circle Research published Refund Protocol (April 2025) with its open problems listed publicly; Arc testnet provides USYC via Teller, sub-cent USDC gas, and mainnet lands summer 2026. The hackathon rubric rewards a deployed prototype, Circle tool usage, path to production, and execution over complexity.

Decided: D1, project is Recourse, buyer protection for USDC on Arc (DeFi track). D2, four components: escrow, deterministic policy engine, USYC yield adapter, instant settlement vault. D3, stack fenced: Solidity canonical logic, TS engine mirror, thin Rust backend (index, evidence, attest), Next.js web, Flutter buyer-only mobile. D4, determinism spine: golden vectors shared by forge and vitest; Rust and Dart eth_call only. D5, addresses flow from deployments/arc-testnet.json via codegen only. D6, MockUSYCAdapter ships behind IYieldAdapter until Teller access approved. D7, stretch gate (Gateway pay-in, EIP-3009 pay, x402 agent dispute) opens Aug 4 only if core is done. D8, CP2 target Jul 26: deployed core contracts, public repo, verify-page clip.

Rules earned: R1, USDC through the ERC-20 interface (6 decimals) only, never native 18 for product logic. R2, engine changes ship with updated vectors and both suites green in one commit. R3, no em dashes in any copy, docs, or commits. R4, testnet keys are throwaways used nowhere else; no mainnet RPCs anywhere. R5, demo-only endpoints live behind DEMO_MODE.
