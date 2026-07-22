# Recourse for iPhone

Native SwiftUI buyer app for protected USDC payments on Arc Testnet.

## Requirements

- Xcode 26 or newer
- Node.js, used by the deployment-address build phase
- Ruby with the `xcodeproj` gem, used by the deterministic project generator
- iOS 17 or newer

## Generate and build

```sh
node ../ops/codegen.mjs
ruby scripts/generate_project.rb
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/recourse-ios-derived \
  CODE_SIGNING_ALLOWED=NO build
```

## Run from Xcode

1. Open `Recourse.xcodeproj`, not an individual Swift file.
2. Select the shared `Recourse` scheme and an iPhone simulator in the toolbar.
3. Press `Command-R` or click the triangular Run button to build, install, and launch the app.

`Command-B` only builds the target. A successful build does not launch the simulator app. If the navigator ever becomes flat after adding files, run `ruby scripts/generate_project.rb` again and reopen the project.

The simulator expects the Recourse backend at `http://127.0.0.1:8080`. To use a
different local or deployed backend, add `RECOURSE_API_URL` under Scheme, Run,
Arguments, Environment Variables. A physical iPhone cannot reach your Mac through
`127.0.0.1`; use the Mac's LAN address or an HTTPS deployment.

`deployments/arc-testnet.json` is the only source of contract addresses. `deployments/arc-config.json` supplies the Arc testnet RPC URL. The Xcode build runs the same code generator before compiling.

The project pins web3swift 3.3.2 exactly in `Package.resolved`. Its `Web3Core` module performs reviewed ABI encoding, decoding, and legacy EIP-155 signing. `HTTPArcRPCTransport` performs typed read and transaction JSON-RPC requests, keeping chain access isolated from feature code and easy to fixture-test.

## Current slice

- Five-stage onboarding with welcome, animated product story, authentication, role selection, and ready states
- Bundled editorial payment photography with source attribution and the official Google sign-in mark
- Native iOS 26 Liquid Glass controls with material fallbacks for iOS 17 and later
- Spring transitions, symbol animation, and first-run persistence with an account-level replay action
- SwiftUI app shell and native design tokens
- Typed app routing
- Exact six-decimal USDC amount type
- Versioned QR payment-request validation
- Testnet-only local signer backed by an encrypted Ethereum V3 keystore in Keychain
- Face ID, Touch ID, or device-passcode confirmation before every transaction and EIP-712 signing operation
- Buyer-authorized evidence writes using the backend's challenge and single-use EIP-712 authorization contract
- Typed evidence upload and manifest publishing with exact request-body hashing
- Chain, evidence, and receipt repository protocols
- Minimal source-controlled ABI fixtures for reviewed ERC-20, PolicyRegistry, and RecourseEscrow calls
- Live Arc reads for USDC balance, allowance, policy, policy hash, payment, verdict preview, and resolve delay
- Signed approve, pay, fileDispute, and resolve transactions with receipt polling
- Checkout planning and approve-then-pay orchestration
- Dispute-window, evidence-upload, filing, and post-confirmation manifest orchestration
- Attestation readiness, resolution, and chain-preview verdict orchestration
- Unit tests for domain invariants, workflow failures, function calldata, signing, EIP-712 digest parity, evidence authorization, receipt polling, and raw Arc response decoding

The business workflows are UI-independent and tested with actor-based fakes. `ArcContractGateway` composes `ArcContractReader` and `ArcContractWriter` behind the workflow protocols. `EvidenceAPIClient` requests a fresh backend challenge for every write, hashes the exact HTTP body, signs the typed authorization, and sends its base64 JSON envelope in `X-Recourse-Auth`. Upload responses are rejected when the backend evidence hash does not match the locally computed hash. A manifest is published only after the dispute transaction is confirmed and the payment reconciles to the onchain disputed state.

The signer stores the encrypted keystore and its random password as separate `WhenUnlockedThisDeviceOnly` Keychain records. `DeviceOwnerTransactionAuthorizer` requires Face ID, Touch ID, or device passcode before credentials are loaded for each transaction or EIP-712 signing operation. The normal suite proves that denied authorization never loads signing credentials and broadcasts no live transaction.

The complete offline suite currently reports 36 passed, 2 intentionally skipped integration tests, and 0 failed.

## Tests

The normal suite keeps network access off. The Arc integration test is opt-in:

```sh
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/recourse-ios-derived \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO test

ARC_LIVE_TESTS=1 ARC_RPC_URL=https://arc-testnet.drpc.org \
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath /tmp/recourse-ios-derived \
  ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO \
  -only-testing:RecourseTests/ArcLiveReadTests test
```

The local write harness starts a disposable anvil node, deploys and seeds the protocol, injects a test-only preloaded account into the XCTest process, and runs the real Swift gateway through approve, pay, fileDispute, and resolve. It verifies every receipt, reconciles contract state after each transition, and confirms that a 100% refund restores the buyer's USDC balance:

```sh
mobile/scripts/verify_local_writes.sh
```

The harness result currently reports 1 passed, 0 skipped, and 0 failed. It temporarily adds local test variables to the generated Xcode scheme and restores the clean deterministic project on exit.
