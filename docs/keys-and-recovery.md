# Keys and recovery: decision record

How a Recourse account holds its money once the wallet stops being one key on one
phone. Written 2026-09-03 against the code as it stands, after reading Fuse's key
model, Xend's decision record for the same problem, and probing Arc testnet directly.

Status: decided, not built. Supersedes the passkey-PRF plan in
`wallet-architecture.md` as the primary mechanism; PRF stays a later convenience.

## The problem

Today the wallet is one secp256k1 key in an `EthereumKeystoreV3`, scoped per account
and synced through iCloud Keychain (`TestnetLocalSigner`). A PIN-sealed copy can be
stored on the backend (`WalletBackup`). That gives:

- One key moves all the money. Whoever gets the keychain item, the iCloud account,
  or the PIN blob plus a guess, has everything.
- Signing in on a phone that is not on the same Apple ID mints a fresh, empty wallet,
  and the restore path is hidden behind a screen that only appears when there is no
  wallet yet (`WalletRecoveryView`), which after onboarding is never.

The product promise is the one on the sign-up screen: an account, not a wallet.
Recourse must not be able to move anyone's money, and losing a phone must not lose it.

## What Fuse does, and what we take from it

Fuse is a Squads smart account with two **Active Keys** that both sign every
transaction, and up to three **Recovery Keys** that can only help restore access.
From Fuse's own support pages (fusewallet.com/support/fuse-security,
/recovery-keys, /i-lost-or-changed-my-mobile-device):

| Key           | Where it lives                                              | Role                                          |
| ------------- | ----------------------------------------------------------- | --------------------------------------------- |
| Device Key    | on the phone, unlocked by Face ID                           | Active, signs every spend                     |
| 2FA Key       | iCloud by default, or a Ledger; called the Cloud Key in-app | Active, signs every spend                     |
| Recovery Keys | email (Turnkey), Phantom, Backpack or Ledger                | Approve only; can never create a transaction  |

Details that matter for copying it honestly:

- A fresh wallet is **1-of-2** until the first Recovery Key is added; it becomes
  2-of-3 then. Fuse lets you skip recovery. We do not.
- **Fuse holds no key.** The email Recovery Key is a Turnkey credential released by
  an emailed code against an ephemeral key made on the phone. Fuse's servers keep
  only device names and recovery email addresses.
- Losing the phone: recover the 2FA Key from iCloud, prove a Recovery Key (email
  code, or sign with the external wallet), mint a new Device Key on the new phone;
  the old phone resets. Losing the 2FA Key: Device Key plus a Recovery Key sets a
  new one.
- Every spend needs both active keys; a **Spending Limit** is an opt-in carve-out
  that lets small transfers go with one.
- **No delay** on recovery or key changes is documented anywhere.
- If Fuse disappears, the exported iCloud key plus an external-wallet Recovery Key
  opens the account through Squads' own interface.

What we keep: the three-key shape, the two-key floor on every spend, recovery keys
that never spend, the explainer sheets, and the Keys screen layout (Active Keys as
two cards, Recovery Keys as a list). What we change: the chain, who holds the
recovery key, no 1-of-2 phase, and the fact that our second active key is one the
app already has.

## The account

The account becomes a **Safe 1.4.1** on Arc with three owners and threshold 2, with
the **Safe 4337 module** (EntryPoint v0.7) enabled so the Safe submits its own
transactions and pays gas from its own USDC balance. Nothing else on Arc needs to
exist for this: everything below was found deployed and exercised on testnet on
2026-09-03.

| Piece                          | Address on Arc testnet                       | Proven how                                   |
| ------------------------------ | -------------------------------------------- | -------------------------------------------- |
| SafeL2 1.4.1 singleton         | `0x29fcB43b46531BcA003ddC8FCB67FFE91900C762` | Safe deployed through the proxy factory      |
| SafeProxyFactory 1.4.1         | `0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67` | same                                         |
| CompatibilityFallbackHandler   | `0xfd0732Dc9E303f09fCEf3a7388Ad10A83459Ec99` | `isValidSignature` answered `0x1626ba7e`     |
| Safe4337Module v0.3            | `0x75cf11467937ce3F2f357CE24ffc3DBF8fD5c226` | UserOp executed, gas paid from the Safe      |
| SafeModuleSetup v0.3           | `0x2dd68b007B46fBe91B9A7c3EDa5A7a1063cB5b47` | present; enables the module at setup         |
| EntryPoint v0.7                | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | same                                         |
| Pimlico bundler                | `https://public.pimlico.io/v2/5042002/rpc`   | estimated, sent, receipted the UserOp        |
| P-256 precompile (RIP-7212)    | `0x0000000000000000000000000000000000000100` | spec vector verifies; about 6,900 gas        |
| Daimo P256Verifier             | `0xc2b78104907F722DABAc4C69f826a522B2754De4` | present, fallback only                       |

The two facts that decided it:

1. **Arc's USDC accepts EIP-1271.** A cheque (`transferWithAuthorization` with the
   `bytes signature` overload) signed by a Safe cashed on-chain in
   `0x8cb01b030bdbd178f3c2b9819c70847bc1de7127df3300c81714977c361950a0`. Cheques
   and invoices survive the move; the payer just becomes a contract.
2. **A Safe pays its own gas in USDC.** Arc's gas token is USDC, and the Safe's
   USDC balance is the same pool the ERC-20 view reads, so the EntryPoint prefund
   comes straight from the account. No paymaster, no relayer, no gas tank on a
   separate key. UserOp
   `0x8ce87eee5c85d94de34662774d9e2a6e422d547854874ddd83eb63b62faaf3cd` cost
   0.0047 USDC at 25 gwei.

Costs at testnet gas prices: deploying the Safe about 0.007 USDC, a transfer about
0.005 USDC. Arc ships the P-256 precompile (Osaka, live since May 2026), so a Device
Key signature adds a few thousand gas, not the 330k a Solidity verifier would.

USDC on Arc is a `FiatTokenProxy` in front of `NativeFiatTokenV2_2`: the same Circle
contract family as everywhere else, with the native balance as its ledger. That is
why EIP-1271, EIP-2612 and EIP-3009 all behave as on Ethereum.

## The three keys

|            | Cloud Key                                  | Device Key                                            | Recovery Key                                    |
| ---------- | ------------------------------------------ | ----------------------------------------------------- | ----------------------------------------------- |
| Anchor     | Apple ID (iCloud Keychain)                 | this phone                                            | email inbox                                     |
| Curve      | secp256k1, plain owner                     | P-256 in the Secure Enclave, owner via a 1271 contract | secp256k1, plain owner                          |
| Holder     | the app, synced keychain item              | the Secure Enclave, non-exportable                    | Recourse, sealed at rest                        |
| Unlock     | device unlock                              | Face ID or passcode at every signature                | a code emailed to the account's address         |
| Present    | every spend                                | every spend                                           | owner rotation only                             |

**The Cloud Key is the key the app already has.** `TestnetLocalSigner` already scopes
it per account and already syncs it through iCloud Keychain; the PIN-sealed backup
already exists. It simply stops being able to spend alone.

**The Device Key is new.** A P-256 key generated with `kSecAttrTokenIDSecureEnclave`
and `.userPresence` access control, so it survives a Face ID re-enrolment and falls
back to the passcode. The Safe cannot hold a P-256 key as an owner directly, so each
Device Key is represented by a tiny contract, deployed at an address derived from its
public key, whose `isValidSignature` checks the signature through the P-256 precompile,
falling back to the Daimo verifier if a chain ever lacks it.
That contract is the Safe owner. `.userPresence` rather than `.biometryCurrentSet` is
a deliberate choice: the prompt is a UX affordance, and the security boundary is the
threshold, not the prompt.

**The Recovery Key is minted by the backend** when the account is created, sealed
under a server key that never leaves the environment, and only ever unsealed to sign
one kind of transaction: an owner change on the account's own Safe. The backend
refuses to sign anything else with it, and it holds one of three, so a full backend
compromise yields a vote and not a wallet. Xend made the same choice; Fuse hands
this role to Turnkey instead. Holding it ourselves is the Argent pattern: not pure
self-custody, and the copy should not claim it is. What it is, is a provider that
cannot spend. Every sealed key carries a key id so moving it to a KMS or a vendor
later is a migration, not a rewrite.

**Invariant:** no single compromise reaches two keys. Not the Apple ID (Cloud only),
not the phone (Device only, and behind Face ID), not the inbox (Recovery only), not
Recourse (Recovery only), not the PIN blob (Cloud only).

The one honest overlap: for someone whose Apple ID email is also their account email,
an Apple ID takeover reaches the inbox too. That pair can rotate the Device Key and
then spend. The mitigation is the security delay below, and it is why the delay is
not optional for long.

## What every day looks like

A send is one tap. The app builds the Safe operation, the Cloud Key signs it, the
Secure Enclave signs it behind Face ID, the two signatures go to the bundler, and
the Safe pays. Nothing in the flow mentions a key.

Cheques are signed the same way, as a Safe message wrapping the EIP-3009 digest, and
cashed with the `bytes signature` overload. `ChequeBook.committed` keeps working
because the Safe's balance is the one it reads.

Earn, Convert and protected checkouts route through the same path with the Safe as
the caller; approve plus deposit become one batched operation through MultiSend.

## Recovery

Losing a phone loses the Device Key and nothing else. Getting back in:

1. Sign in on the new phone as usual (Apple, Google or passkey).
2. The Cloud Key is already there if the phone shares the Apple ID. Otherwise the
   app asks for the recovery PIN and restores it from the sealed backup.
3. The app mints a new Device Key here and asks to swap it in.
4. Recourse emails a six-digit code to the account's address. On a correct code the
   backend co-signs the swap with the Recovery Key.
5. The Cloud Key adds the second signature and the swap executes. The old phone's
   key is out; this phone's is in.

"Sign in with Google or Apple on another device" therefore lands on the same wallet,
with the same balance, by design rather than by iCloud luck. No seed phrase, ever.

The pair used for recovery, Cloud plus Recovery, is also the pair a thief would need.
Both are remote anchors. So step 5 should wait out a **security delay** with a push
notification and a one-tap cancel from the old phone. Fuse documents no delay at
all; Xend chose 24 hours; Argent finalises recovery after 48 hours; Candide's Safe
recovery module defaults to 14 days. The Safe has no delay built in, so this needs
the Zodiac Delay modifier or a small module of our own. It ships in the second cut,
and until it does the copy says so plainly: recovery is instant, and so is theft by
someone who has both your Apple ID and your inbox. That is still exactly Fuse's
position today.

## Moving the money that already exists

The current wallet is an EOA with a real balance. The Safe address is counterfactual
(CREATE2 from a per-account salt), so it can be shown and receive before it is
deployed. The upgrade on first launch:

1. Predict the Safe address, mint the Device Key, ask the backend for the Recovery
   Key's address.
2. Deploy the Safe from the EOA (it pays that one fee), transfer the balance.
3. Re-point the handle at the Safe. `account_handles` was built expecting this:
   the address column is on the handle, not the account, because "the address is
   not durable".
4. Any cheque already written by the EOA stays cashable: the committed amount stays
   behind at the EOA until each cheque is cashed or voided, then sweeps.

The EOA does not disappear. It is the Cloud Key.

## What has to be built

**Contracts** (`contracts/`): `P256Owner` and its CREATE2 factory, verified by
Foundry tests against known P-256 vectors and against the Daimo verifier; deploy
scripts for testnet and mainnet. Nothing else on-chain is ours.

**Backend** (`backend/`): `smart_accounts` (safe address, salt, owner set, status),
`recovery_signers` (sealed key, address), `recovery_challenges` (hashed codes,
attempts, expiry, purpose); a mailer (Resend) behind an owned interface; endpoints
to provision an account, to request and verify a code, and to co-sign an owner
rotation once a code has been verified. New secrets: `RECOVERY_VAULT_KEY`,
`RESEND_API_KEY`. The signing policy lives in one place and is tested: the Recovery
Key signs `swapOwner`, `addOwnerWithThreshold` and `removeOwner` on the account's own
Safe and nothing else.

**Mobile** (`mobile/`): a `DeviceKey` over the Secure Enclave; `SmartAccount`
(address prediction, Safe transaction and SafeOp hashing, signature assembly with
owners sorted as the Safe requires); a `BundlerClient`; `ArcContractWriter` routing
through the Safe; the onboarding wallet step provisioning three keys instead of one;
the upgrade flow for existing wallets; a **Keys** screen in the Fuse layout with the
three explainer sheets; a **Restore this phone** flow with the emailed code.

**Verification**: the simulator fakes the Secure Enclave and returns keys
indistinguishable from real ones, so the Device Key is only proven on the physical
iPhone. Everything else is proven against the test Safe on Arc testnet first.

## Rejected

- **Keep one key and add PIN backup.** Already built; still one key.
- **Passkey as the second active key.** Passkeys sync through iCloud Keychain, the
  same anchor as the Cloud Key, so the pair collapses to one compromise.
- **A software secp256k1 device key.** Cheaper on-chain, extractable from a
  jailbroken phone. Fuse's property comes from the Secure Enclave.
- **Recourse holding a second sealed key released by Apple or Google sign-in.**
  Two server-held keys is custody with extra steps.
- **EIP-7702 to keep the EOA address.** Live on Arc: a type-4 transaction is accepted
  and Arc's docs say it behaves as on Ethereum, but a 400-block sample held zero of
  them. A delegated EOA running a Safe implementation is a newer and less audited
  shape than a plain Safe proxy, and the handle already absorbs an address change.
  Not worth it for one address.
- **Circle Modular Wallets.** Circle's own ERC-4337 account supports Arc testnet, has
  an iOS SDK with Arc mainnet pre-registered, and Gas Station sponsors gas in USDC.
  But the SDK exposes one passkey owner plus a recovery EOA, not a managed 2-of-3;
  the passkey is iCloud-anchored like our Cloud Key; and the weighted multisig plugin
  on-chain has no public API. The fallback if Safe ever becomes a problem, not the
  first choice.
- **A relayer that submits Safe transactions and takes a refund.** Works, but it is
  a service we would run and a point that can be censored or fall over. The bundler
  is the standard path and needs no key of ours.

## Between testnet and mainnet

Arc mainnet is not live: the docs say mainnet addresses are not yet available, and
chain id 5042 appears only as a placeholder in Circle's iOS SDK. Launch needs:

- **Safe 1.4.1 on mainnet.** The deployments are deterministic through the Safe
  singleton factory, so if Safe has not deployed by then we can, byte for byte at
  the same addresses.
- **A bundler on mainnet.** Pimlico lists Arc testnet with 7702 and paymaster
  support and sits on Arc's account-abstraction page, so mainnet coverage is likely
  but not promised. If it is missing on day one, the Safe's native gas refund lets
  our own relayer submit `execTransaction` and be repaid in USDC by the account,
  without any change to what the keys sign.
- **One cheque on day one.** Re-verify EIP-1271 on mainnet USDC with a cent before
  anyone writes a real cheque.

## Sources

- Fuse support pages: fusewallet.com/support/fuse-security, /recovery-keys,
  /i-lost-or-changed-my-mobile-device, /i-lost-access-to-my-2fa-key,
  /create-a-spending-limit, /what-if-fuse-is-removed-from-the-app-store;
  fusewallet.com/blog/wallet-recovery. Explainer sheets captured from a live account
  (Device Key, Cloud Key, Recovery Key, Add Recovery Key, Confirm email).
- Comparables: Daimo (1-of-n P-256 slots, no delay), Coinbase Smart Wallet (passkey
  plus an optional recovery signer), Argent (guardians, 48 hour recovery), Candide
  recovery module for Safe (guardians, grace period).
- Xend: `docs/specs/account-security-model-decisions.md`, ADR 0025, and
  `apps/backend/src/recovery` in `EntrypointLabs/xend-global`.
- Arc testnet probes and transactions listed above; the test Safe is
  `0xf8d3764050E364479a6695ef482d5B708FAc335E`. Arc docs: evm-differences (Osaka
  baseline, EIP-7702), gas-and-fees, tools/account-abstraction. Pimlico supported
  chains; Circle Modular Wallets supported blockchains and passkey recovery pages;
  safe-deployments v1.4.1 (`5042002: canonical`).
- Safe 1.4.1 and Safe4337Module v0.3 sources for message and SafeOp hashing.
