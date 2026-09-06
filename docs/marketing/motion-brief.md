# Motion brief: Recourse and Olien

For the motion designer. Everything here is true today on Arc testnet. Mainnet is
16 September 2026; nothing in a video says "live" or "mainnet" until then.

## What we are

**Recourse** is a money app for USDC on Arc, Circle's chain for dollars. Send by
name, no seed phrase, every payment signed by two keys. It is for people who get
paid in dollars and pay other people in dollars: freelancers, remote workers,
small teams. Not a trading app.

**Olien Multisig** is the treasury product: a shared account on Arc that a team
controls together. Propose, approve, execute, with rules the chain enforces (a
threshold, a 24-hour time lock on changes, a veto, spending limits). Members can
be a Recourse account by @handle, a passkey, or a hardware wallet. Squads on
Solana is the closest reference for what it is.

One line each:
- Recourse: "Dollars on your phone, sent by name."
- Olien: "The multisig platform to secure and manage USDC on Arc."

## Voice

Short sentences. Plain words. Say "dollars", not "crypto". No hype, no "revolution",
no rockets. Every claim is a thing the product does today. We would rather show
one screen doing one thing than a montage.

Words we use: account, send, request, cheque, invoice, convert, earn, keys, treasury,
member, approve. Words we avoid: wallet (in Recourse), token, DeFi, seed phrase
(except to say there is none), gas (we say "fees in USDC").

## Brand

Recourse
- Ink `#111B19` on white `#FFFFFF`. Ledger green `#075B46` for the one accent.
  Mint `#EDF3EF` for soft surfaces. Night `#070907` for the in-app dark world,
  with night green `#3ECF8E` on it.
- Onboarding and the website are white and green. The app interior is flat black.
- Type: Geist (sans) for the app and the site, Geist Mono for numbers and addresses.
- Mark: the cream R on ledger green (the app icon). Files in `web/public/brand`:
  `recourse-mark.png`, `pay-with-recourse.svg`, `pay-with-recourse-light.svg`.
  Partner marks there too: `arc-mark.svg`, `usdc.svg`, `circle-mark.png`.
- Social art already made, for reference of the look: `docs/social/images/`
  (`x-launch-1.png`, `x-launch-2.png`, `x-banner.png`).

Olien
- Same ink and green, but the console follows the device: light (white cards on
  warm grey `#F4F5F3`) or dark (`#0A0A0B` ground, `#131316` panels).
- Type: Inter. Wordmark: OLIEN in caps with a rounded square glyph and a green dot.
- The product page is at recourse-arc.vercel.app/olien; the console door at /olien/app.

Motion should feel like the product: calm, precise, a little weight. Ease-outs,
short durations, no bounces. Numbers that count up should land on the exact figure.

## The videos

### 1. Recourse launch film, 30 seconds, 9:16 and 16:9

The one argument, in order:
1. A balance on a phone. "Dollars on your phone."
2. Send to `@ade`, Face ID, done in one beat. "Sent by name."
3. The three keys: Device, iCloud, Recovery, then "Safe, 2 of 3". "No seed phrase.
   No single key that can lose the money."
4. Four quick beats, one screen each: Request, Cheque, Convert, Earn.
5. Close: the mark, "Recourse", "Beta on TestFlight", "@useRecourse".

Screen recordings do the work; motion frames them, adds the captions, and animates
the key diagram. The key diagram is the only fully animated scene.

### 2. Feature cuts, 10 to 15 seconds each, 9:16

One per feature, same template, captions only, for daily posting:
- Send by @handle.
- Request money and get paid when they sign.
- Write a cheque they cash later; void it before they do.
- Convert USDC to EURC, with the app checking the rate before you sign.
- Earn on idle dollars.
- A received-money alert landing on the lock screen.

### 3. Olien console, 45 seconds, 16:9

Screen-recorded on a Mac, framed like Squads' product shots (tablet slab, slight
tilt):
1. The dashboard: balance, chart, accounts, inflows.
2. Create an Olien in three steps: name, members, threshold, review, confirm.
3. Send: propose a payment.
4. On a phone: the alert arrives, the member approves with Face ID.
5. Back on the console: executed. Close on the OLIEN wordmark, "Treasuries for
   teams on Arc", the product URL.

## Deliverables

- Each film in 9:16 (1080 by 1920) and 16:9 (1920 by 1080); feature cuts 9:16 only.
- H.264 MP4 and a ProRes master. Burned-in captions on one version, clean on another.
- A 6-second loop of the key diagram, transparent background, for the website.
- Source files (After Effects or equivalent) and the fonts used.
- Music: licensed for social, or none. We are fine with no music and sound design only.

## What we will give you

Sent as a folder. Items marked "record" are screen recordings we will make on a
real iPhone 15 Pro at 60 fps, portrait, with a clean status bar, and on a Mac at
1920 by 1080 for the console.

Brand
- Marks and partner marks (folder above), the app icon at 1024, the OLIEN wordmark
  as SVG, the colour list above, the Geist and Inter font files.
- The existing social art for reference.

Recourse, record
- Onboarding: Continue with Apple, the two keys made, "Account ready".
- Home with a balance and a few movements in History.
- Send to @ade: amount, Face ID, the success screen.
- Request: create one, and the paying side signing it.
- Cheque: write one to @ade, then cash it from the other phone, then void one.
- Convert: type an amount, Review, the review sheet, Confirm.
- Earn: the product sheet and a deposit.
- Keys: the screen with both keys active.
- A "Received $10 from @olien" alert on the lock screen.
- The restore flow: Start your recovery process, the six-digit code, Finish.

Olien, record
- Sign in with a wallet; the dashboard for a treasury with a balance and history.
- Create an Olien, all three steps, on a treasury we prepare.
- Send: propose a payment; on a phone, the alert and the approval; the executed state.
- Members and Settings, one slow scroll each.

Access
- TestFlight invite, so you can capture anything else you need.
- A test account with a few test dollars, and the console open at localhost or on
  the site once we switch it on.

Copy
- Captions for every scene, final, in a text file, so nothing is retyped.
- The X handle @useRecourse, the site URL, and the TestFlight link.

## Constraints

- Real screens only. No mock UI, no invented numbers. If a number is needed that
  the screen does not show, ask.
- No em dashes in captions. Sentences end.
- Nothing says mainnet, real money, or a bank. On screen the network is "Arc
  Testnet" and that is fine to show.
- No partner logos larger than ours. Arc, USDC and Circle appear as "built on".

## Timeline

Week 1: the key diagram loop and the launch film cut for review. Week 2: the
feature cuts and the Olien film. We review on a shared link with timecoded notes.
