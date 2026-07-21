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

`deployments/arc-testnet.json` is the only source of contract addresses. `deployments/arc-config.json` supplies the Arc testnet RPC URL. The Xcode build runs the same code generator before compiling.

The project pins web3swift 3.3.2 exactly in `Package.resolved`. Its `Web3Core` module performs reviewed ABI encoding, decoding, and legacy EIP-155 signing. `HTTPArcRPCTransport` performs typed read and transaction JSON-RPC requests, keeping chain access isolated from feature code and easy to fixture-test.

## Current slice

- SwiftUI app shell and native design tokens
- Typed app routing
- Exact six-decimal USDC amount type
- Versioned QR payment-request validation
- Testnet-only local signer backed by an encrypted Ethereum V3 keystore in Keychain
- Face ID, Touch ID, or device-passcode confirmation before every signing operation
- Chain, evidence, and receipt repository protocols
- Minimal source-controlled ABI fixtures for reviewed ERC-20, PolicyRegistry, and RecourseEscrow calls
- Live Arc reads for USDC balance, allowance, policy, policy hash, payment, verdict preview, and resolve delay
- Signed approve, pay, fileDispute, and resolve transactions with receipt polling
- Checkout planning and approve-then-pay orchestration
- Dispute-window, evidence-upload, and filing orchestration
- Attestation readiness, resolution, and chain-preview verdict orchestration
- Unit tests for domain invariants, workflow failures, function calldata, signing, receipt polling, and raw Arc response decoding

The business workflows are UI-independent and tested with actor-based fakes. `ArcContractGateway` composes `ArcContractReader` and `ArcContractWriter` behind the workflow protocols. The signer stores the encrypted keystore and its random password as separate `WhenUnlockedThisDeviceOnly` Keychain records. `DeviceOwnerTransactionAuthorizer` requires Face ID, Touch ID, or device passcode before credentials are loaded for each signing operation. The normal suite proves that denied authorization never loads signing credentials and broadcasts no live transaction.

The complete offline suite currently reports 29 passed, 2 intentionally skipped integration tests, and 0 failed.

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
