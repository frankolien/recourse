# X: launch thread and the first week

Account: @useRecourse. Voice matches the site: short sentences, plain words, dollars
not "crypto", no hype. Every claim below is true today on Arc testnet; nothing says
mainnet until 2026-09-16 has happened and the app points at chain 5042. Post the
thread first, then one post a day. Attach the phone screenshots from `web/public/app`
where a post names a screen.

## Launch thread

1. Dollars on your phone, sent by name.

   Recourse is a money app for USDC on Arc, Circle's chain. Type an @handle, an
   amount, a note. That is the whole payment.

   Beta on TestFlight now. [link]

2. No addresses. You pay @ada, not 0x7eae…263c. The app checks the name resolves to
   one account before you sign, and shows you who.

3. Fees come out of the dollars you already hold. Arc charges gas in USDC, so there is
   no second token to buy, run out of, or explain.

4. Two keys sign every payment: one in your phone, one in your iCloud Keychain.
   Neither works alone. Recourse never holds either. Lose the phone, sign in on a new
   one, and the keys come back through iCloud and a code to your email.

5. Write a cheque. The other person cashes it when they want, and they do not have to
   be online for you to write it. Void it any time before it is cashed. It costs
   nothing to write.

6. Send an invoice. It fixes the amount, the date and who pays. They answer with one
   signature, no gas on their side, and you collect when you like.

7. Earn on idle dollars. Put USDC into Earn and it earns while it sits. Take it out
   whenever.

8. Convert between dollars and euros. USDC to EURC at a rate the app checks against
   the market before you sign. If the pool is off market, the app says so and refuses.

9. Your money, your keys, and you can read the code. [repo link]

   Testnet today. Mainnet when Arc opens it. Try the beta and tell us what is wrong
   with it: [TestFlight link]

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
