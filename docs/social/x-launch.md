# X: launch thread and the first week

Account: @useRecourse. Voice matches the site: short sentences, plain words, dollars
not "crypto", no hype. Every claim below is true today on Arc testnet; nothing says
mainnet until 2026-09-16 has happened and the app points at chain 5042. Post the
thread first, then one post a day. Attach the phone screenshots from `web/public/app`
where a post names a screen.

## Launch thread

Shaped like Fuse's Solana launch thread (Dec 2023): one argument across six posts.
Image 1 is `images/x-launch-1.png`: a white card, the headline, three lines, the
Home screenshot in a phone frame, "Built on Safe, on Arc" at the foot. Image 2 is
`images/x-launch-2.png`: the three-key diagram, Device, iCloud, Recovery key, then
"Safe 2 of 3", then "Safe contracts on Arc". Both 3200 by 1800, X's 16:9.

1/ Money on your phone needs an upgrade.

Recourse is a money app for USDC on Arc, Circle's chain for dollars. Send by name,
no seed phrase, and every payment signed by two keys.

Beta on TestFlight: [link]

[image 1]

2/ Every Recourse account is a Safe, the most used smart account contracts in
Ethereum, deployed on Arc with three keys and a 2 of 3 threshold. One key lives in
the phone's Secure Enclave, one in your iCloud Keychain, and a third can only get
you back in and can never spend.

[image 2]

3/ There is no seed phrase to write down and no single key that can lose the money.
Lose the phone: sign in on a new one, the iCloud key comes back on its own, and a
code to your email swaps the device key over. Lose the iCloud key: your recovery
PIN brings it back. Recourse never holds a key that can spend.

4/ We are building Recourse for people who get paid in dollars and pay other
people in dollars. Not a trading app. A balance, the people you pay, and the
things that happen between people: a payment, a request, a cheque, a conversion.

5/ What it does today, on testnet:
Send to an @handle, no addresses.
Request money and collect when they sign.
Write a cheque they cash later, void it before they do.
Earn on idle dollars.
Convert USDC to EURC at a rate the app checks before you sign.
Fees in USDC. No second token.

6/ The code is public: [repo link]. Testnet now; mainnet when Arc opens it on
September 16.

Apply for the beta: [TestFlight link]

## The first week

Day 1, after the thread. Screenshot: Home.
> One screen. Your balance, what is in motion, and four things you can do with it:
> Send, Request, Cheque, Convert. Nothing else on it.

Day 2. Screenshot: Send.
> Why names and not addresses. An address is 42 characters and one wrong one loses
> the money. A name is checked before you sign and shown back to you as the person.
> We are not going to ask people to copy hex strings in 2026.

Day 3. Screenshot: Keys.
> Where your keys are. One in the phone's Secure Enclave, one in your iCloud
> Keychain. Every payment needs both. We hold a third key that can only help you get
> back in and can never spend. The screen in the app shows you all three.

Day 4. Screenshot: Cheques.
> Cheques, in a money app. You write one, they cash it later. They are paid without
> needing to be online for it. You can void it up until the moment it is cashed. This
> is how most payments between people actually happen: not at the same time.

Day 5.
> Gas in dollars. On Arc, the fee for a payment is paid in USDC. Recourse shows the
> fee in the same number as the amount. No "you need 0.002 of something else first".

Day 6. Screenshot: Convert.
> Dollars to euros, with a check. The app prices your conversion against the market
> before it lets you sign. If the on-chain rate is worse than it should be, the button
> stays grey and the screen tells you why. A wallet should refuse a bad trade, not
> just warn about it.

Day 7.
> Teams next. The same two-key idea, grown up: a treasury with a threshold, a spending
> limit that does not need a vote, a time lock on changes and a veto for the people
> who did not sign. It is called Olien and it runs on Arc. More soon.

## Replies to keep ready

- "Is it custodial?" No. Two keys sign every payment and both are yours. The one key
  we hold cannot spend; it can only help you recover.
- "Which chain?" Arc, the chain Circle built for dollars. Fees are in USDC.
- "Mainnet?" Testnet now. Arc mainnet opens 2026-09-16 and the app moves after we
  have verified the deployments on it.
- "Android?" iOS first. Android when the iOS one is right.
- "Is the code public?" Yes: [repo link].

## Not to say yet

- Anything that implies real money moves today.
- Yield numbers. Earn is a testnet vault; there is no rate worth quoting.
- Olien as available. It is a console behind a coming-soon page until Phase 3 is
  run on a phone.
