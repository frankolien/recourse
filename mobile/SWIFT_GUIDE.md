# The Recourse iOS App: A Complete Swift + SwiftUI Guide

**From Zero Swift to Full Understanding of This Codebase**

Written for a developer who knows JavaScript/Dart but is learning Swift by understanding every line of the Recourse buyer protection app: a native SwiftUI wallet that pays USDC into escrow on Arc, signs evidence with Face ID, and recomputes onchain verdicts on the phone.

---

## Table of Contents

- [Part 1: Swift Fundamentals You Need](#part-1-swift-fundamentals-you-need)
- [Part 2: Project Structure](#part-2-project-structure)
- [Part 3: SwiftUI Deep Dive](#part-3-swiftui-deep-dive)
- [Part 4: Swift Concurrency: async/await, Actors, MainActor](#part-4-swift-concurrency-asyncawait-actors-mainactor)
- [Part 5: App Architecture: Environment, Routing, Stores](#part-5-app-architecture-environment-routing-stores)
- [Part 6: Auth and Security](#part-6-auth-and-security)
- [Part 7: Talking to Arc: web3swift and the Gateway Layer](#part-7-talking-to-arc-web3swift-and-the-gateway-layer)
- [Part 8: Determinism: Manifests, Hashes, Verdicts](#part-8-determinism-manifests-hashes-verdicts)
- [Part 9: QR Codes, the Camera, and Universal Links](#part-9-qr-codes-the-camera-and-universal-links)
- [Part 10: The Design System](#part-10-the-design-system)
- [Part 11: Testing](#part-11-testing)
- [Part 12: Xcode, the Generated Project, and Shipping](#part-12-xcode-the-generated-project-and-shipping)
- [Part 13: Common Patterns Reference](#part-13-common-patterns-reference)

---

# Part 1: Swift Fundamentals You Need

Swift will feel closer to Dart than Rust does, but it has ideas neither JavaScript nor Dart has: optionals enforced by the compiler, value semantics by default, and protocols as the backbone of every abstraction. These appear on virtually every line of this codebase.

## 1.1 Optionals: The End of null Crashes

In JavaScript, any value can be `null` or `undefined` and you find out at runtime. In Swift, a `String` is always a string. If a value might be absent, its type says so: `String?`.

```swift
// From Core/Auth/AccountSession.swift:
struct AuthenticatedAccount: Codable, Equatable, Sendable {
    let accountID: Int64
    let providerUserID: String
    let email: String?          // The backend may not have an email
    let givenName: String?
    let familyName: String?
}
```

You cannot use an optional directly. You must unwrap it, and the compiler makes sure you handled the `nil` case:

```swift
// if let: unwrap for one block
if let email = account.email {
    print(email)                // email is a plain String here
}

// guard let: unwrap or bail out early (the dominant style in this codebase)
guard let storedGrant = try await store.load() else { return }
// storedGrant is non-optional from here down

// Nil-coalescing: default value, like JS ?? 
email ?? displayName ?? "APPLE ACCOUNT"

// Optional chaining, like JS ?.
environment.accountSession.account?.accountLabel
```

**Where you see this in Recourse:** `AccountSession.swift` has the canonical chain. `accountLabel` is literally `email ?? displayName ?? "APPLE ACCOUNT"`, three fallbacks in one line, and `displayName` itself returns `String?` because a user may have no name at all.

`Option<T>` in Rust, `T?` in Dart, `T | undefined` in TypeScript: same idea. The difference from JS is that Swift will not compile if you forget the nil path.

## 1.2 Value Types vs Reference Types: struct vs class

This is the most important architectural decision in Swift, and this codebase is deliberate about it:

| | `struct` (value) | `class` (reference) |
|---|---|---|
| Assignment | Copies the value | Copies the pointer |
| Mutation visible to others? | No | Yes |
| Identity | None, only equality | Has identity |
| In this codebase | Data: `OrderManifest`, `PaymentRecord`, `USDCAmount`, every SwiftUI View | Long-lived state machines: `AccountSession`, `AppEnvironment`, `BuyerPaymentStore` |

Rule of thumb used throughout Recourse: **data is a struct, a thing with a lifecycle is a class**. A `PaymentRecord` is just facts, so copying it is safe and cheap. An `AccountSession` owns a keychain store and an in-flight network task; two copies of it would be a bug, so it is a class.

Dart comparison: Dart only has reference types (classes). Swift structs behave like Dart's records or freezed data classes, but they are the default, not the exception.

## 1.3 Enums With Payloads

Swift enums are full algebraic data types, like Rust enums or Dart sealed classes. The codebase uses them everywhere state has distinct shapes:

```swift
// From Features/Verdict/Domain/VerdictWorkflow.swift:
enum VerdictReadiness: Equatable, Sendable {
    case awaitingAttestation(until: UInt64)   // carries a timestamp
    case ready(VerdictPreview)                // carries a full preview
    case settled(VerdictPreview)
}

// From App/AppRouter.swift, every screen you can navigate to:
enum AppRoute: Hashable {
    case checkout(PaymentRequest)
    case payment(UInt64)
    case dispute(UInt64)
    case verdict(UInt64)
    case send
    case earn
    case account
}
```

You consume them with `switch`, and like Rust's `match` it is exhaustive: forget a case and the compiler stops you.

```swift
switch readiness {
case .awaitingAttestation(let until):
    // show the countdown
case .ready(let preview), .settled(let preview):
    // show the verdict
}
```

This is why adding a screen to `AppRoute` instantly produces a compile error in `RootView.destination(for:)` until you say what view it maps to. The compiler is the router's test suite.

## 1.4 Protocols: The Backbone of This Codebase

A protocol is an interface, but richer: it can require async methods, have default implementations via extensions, and be composed.

```swift
// From Core/Chain/ContractGateway.swift, the heart of the chain layer:
protocol ContractReading: Sendable {
    func payment(id: UInt64) async throws -> PaymentRecord
    func vaultState(of owner: EthereumAddress) async throws -> VaultState
    // ...
}

protocol ContractWriting: Sendable {
    func pay(request: PaymentRequest) async throws -> ChainHash
    // ...
}

// Protocol composition: a gateway is anything that can do both.
protocol ContractGateway: ContractReading, ContractWriting {}
```

Every feature workflow (`CheckoutWorkflow`, `DisputeWorkflow`, `VerdictWorkflow`, `SendWorkflow`) depends on `any ContractGateway`, never on the concrete `ArcContractGateway`. That single decision is why the entire app is testable without a network: tests hand the workflows a `FakeContractGateway` and the workflows cannot tell the difference.

The `any` keyword marks an **existential**: "some concrete type conforming to this protocol, decided at runtime". You will see `any ContractGateway`, `any BuyerSigner`, `any EvidenceRepository` on properties, because the concrete type is chosen at composition time in `AppEnvironment`.

## 1.5 Error Handling: throws, do/catch, and Typed Errors

Swift errors are thrown, but unlike JavaScript exceptions they are part of the function signature. A function that can fail says `throws`, and the caller must say `try`:

```swift
func makeContractGateway() throws -> any ContractGateway
let gateway = try environment.makeContractGateway()
```

Errors are just values conforming to `Error`, and this codebase gives each layer its own error enum so failures are precise:

```swift
// From Core/Chain/ArcContractReader.swift:
enum ContractReadError: Error, Equatable, Sendable {
    case missingABI(String)
    case invalidABI(String)
    case invalidRPCResponse
    case rpc(code: Int, message: String)
    case malformedResult(method: String)
    case unknownPaymentStatus(UInt8)
}
```

Catching looks like this:

```swift
do {
    let profile = try await api.me(accessToken: storedGrant.accessToken)
    try await accept(storedGrant.replacingAccount(profile))
} catch let error as AccountAPIError where error.isUnauthorized {
    // pattern-matched catch: only unauthorized errors land here
    let refreshed = try await api.refresh(refreshToken: storedGrant.refreshToken)
    try await accept(refreshed)
} catch {
    // everything else; `error` is implicitly in scope
}
```

That `catch let error as AccountAPIError where ...` line (from `AccountSession.swift`) is Swift's equivalent of Rust's `match` guard: catch by type AND condition.

Three try flavors:

| Form | Meaning | Analogy |
|---|---|---|
| `try` | Propagate the error to my caller | Rust `?` |
| `try?` | Convert failure to `nil` | "I do not care why it failed" |
| `try!` | Crash on failure | `unwrap()`; never used in this app's production paths |

Note the deliberate `try?` in `restore()`: `try? await store.clear()`. If clearing a dead session fails, there is nothing better to do, so the error is intentionally discarded. `try?` documents that decision in one character.

## 1.6 Closures and Trailing Closure Syntax

Closures are arrow functions with ownership rules lighter than Rust's. The syntax `{ parameters in body }`:

```swift
let doubled = amounts.map { $0 * 2 }     // $0 is the first argument
```

SwiftUI is built entirely on **trailing closures**: when the last parameter is a closure, it moves outside the parentheses. This is why SwiftUI looks like a markup language but is plain Swift:

```swift
Button {
    router.push(.earn)          // first closure: the action
} label: {
    Text("Earn")                // second closure: the label view
}
```

One capture rule matters here: closures capture references strongly. In long-lived callbacks you will see `[weak self]` to avoid retain cycles. SwiftUI views are value types so this rarely bites in this codebase, but `GoogleSignInCoordinator` and delegate-style code use it.

## 1.7 Codable: JSON Without a Parser

`Codable` is Swift's serde. Declare conformance and the compiler synthesizes encoding and decoding:

```swift
// From Core/Auth/AccountSession.swift:
struct AuthenticatedAccount: Codable, Equatable, Sendable {
    let accountID: Int64
    let providerUserID: String

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"          // maps Swift name to JSON name
        case providerUserID = "providerUserId"
    }
}
```

`CodingKeys` does what serde's `#[serde(rename)]` does. The session grant is persisted to the keychain as JSON through exactly this machinery:

```swift
let data = try JSONEncoder().encode(grant)     // struct -> Data
let grant = try JSONDecoder().decode(AccountSessionGrant.self, from: data)
```

The most important Codable trick in the whole project is in `OrderManifest` (Part 8): encoding with `.sortedKeys` so the JSON bytes are canonical enough to hash.

## 1.8 Common Derives: What Those Conformance Lists Mean

Swift's equivalent of Rust's `#[derive(...)]` is the conformance list after the type name. The compiler synthesizes the implementations:

| Conformance | What it gives you | Rust/JS analogy |
|---|---|---|
| `Equatable` | `==` comparison | `PartialEq` / `===` semantics for values |
| `Hashable` | Use as dictionary key, in `Set`, in `NavigationStack` paths | `Hash` |
| `Codable` | JSON encode + decode | `Serialize + Deserialize` |
| `Identifiable` | `id` property; required by SwiftUI `ForEach` | React `key` |
| `Sendable` | Safe to pass across concurrency domains | `Send` |
| `CaseIterable` | `.allCases` array on an enum | enumerating an enum |
| `Error` | Can be thrown | `std::error::Error` |

`Sendable` is the one with no JS analogy. It is a compile-time proof that a value can cross threads safely. Every domain struct in `Core/Domain` is `Sendable` on purpose: it lets actors hand them out freely (Part 4).

## 1.9 Extensions: Adding Behavior Anywhere

Extensions add methods to existing types, including types you do not own:

```swift
// From Core/Auth/AccountSession.swift, private helper on a domain type:
private extension AccountSessionGrant {
    func replacingAccount(_ account: AuthenticatedAccount) -> Self {
        AccountSessionGrant(accessToken: accessToken, refreshToken: refreshToken, account: account)
    }
}
```

The design system leans on this: `View` extensions like `.recourseGlassCapsule()` and `.recourseKeyboardDismissal()` are extensions on SwiftUI's `View` protocol, which is how the app grows its own modifier vocabulary.

## 1.10 Access Control and Naming You Will See Constantly

```swift
private(set) var account: AuthenticatedAccount?
```

`private(set)` means: anyone can read, only this type can write. `AccountSession` exposes `account`, `isRestoring`, `errorMessage` this way, so views can render state but never mutate it. That is the whole unidirectional data flow story in one keyword.

Other qualifiers: `private` (this type and file scope), `fileprivate` (rare), `internal` (default, module-wide), `public`/`open` (frameworks; unused here since the app is one module).

---

# Part 2: Project Structure

## 2.1 The Tree

```
mobile/
|-- scripts/generate_project.rb     # Generates Recourse.xcodeproj (Part 12)
|-- Recourse/
|   |-- App/                        # Composition root and app-level chrome
|   |   |-- RecourseApp.swift       # @main entry point
|   |   |-- AppEnvironment.swift    # Dependency container + BuyerPaymentStore
|   |   |-- RootView.swift          # Workspace routing, splash, deep links
|   |   |-- SplashView.swift        # Animated boot sequence
|   |   |-- AppRouter.swift         # AppRoute enum + navigation path
|   |   |-- AppShellView.swift      # Tab shell (buyer) + merchant counter
|   |
|   |-- Core/                       # Everything reusable, no feature knowledge
|   |   |-- API/                    # Backend clients (accounts, evidence, orders)
|   |   |-- Auth/                   # Session, keychain, signer, Face ID
|   |   |-- Chain/                  # web3swift gateway to Arc (Part 7)
|   |   |-- Config/                 # AppConfiguration (addresses, URLs)
|   |   |-- DesignSystem/           # Colors, typography, cards, glass
|   |   |-- Domain/                 # PaymentRecord, USDCAmount, ChainHash...
|   |   |-- Orders/                 # OrderManifest (hash-bound commerce data)
|   |   |-- QR/                     # PaymentRequest + decoder
|   |
|   |-- Features/                   # One folder per user-facing capability
|   |   |-- Checkout/Domain/        # CheckoutWorkflow
|   |   |-- Disputes/Domain/        # DisputeWorkflow
|   |   |-- Verdict/Domain/         # VerdictWorkflow (on-phone recompute)
|   |   |-- Send/                   # SendWorkflow + SendMoneyView
|   |   |-- Earn/                   # EarnView (settlement vault)
|   |   |-- Home/, Scan/, Receipts/, Profile/, Onboarding/
|   |
|   |-- Generated/Deployment.swift  # Contract addresses, generated from
|   |                               # deployments/arc-testnet.json. Never hand-edited.
|   |-- Resources/
|   |   |-- ABI/*.abi.json          # Contract ABIs bundled into the app
|   |   |-- Images.xcassets/        # Asset catalog (icons, cards, launch)
|   |-- Info.plist                  # Merged plist: URL scheme, launch screen
|-- RecourseTests/                  # XCTest suite (Part 11)
```

Two structural rules keep this sane:

1. **Core never imports Features.** Dependencies point one way: `Features -> Core`. A workflow can use the gateway; the gateway knows nothing about screens.
2. **Generated code is generated.** `Generated/Deployment.swift` comes from the repo-root `deployments/arc-testnet.json` via codegen. Addresses exist in exactly one place; the app cannot drift from what is actually deployed.

## 2.2 How Swift Finds Code (No Imports Between Files)

Coming from JS/Dart, the strangest thing: there are almost no imports of the app's own files. Swift compiles the whole module (target) together, so every file sees every other file's `internal` declarations. `import` is only for frameworks:

```swift
import SwiftUI          // Apple UI framework
import Foundation       // Strings, Data, URL, JSON
import Observation      // @Observable macro
@preconcurrency import BigInt   // third-party, pre-Sendable-audit
```

`@preconcurrency import` (seen in `ArcContractReader.swift`) means: this library predates strict concurrency checking, do not flag its types.

## 2.3 Third-Party Dependencies

The app uses Swift Package Manager (SPM), Apple's Cargo/npm. Notable packages: `web3swift` + `BigInt` + `Web3Core` for Ethereum-style RPC, ABI encoding, keystores, and EIP-712. Everything else is Apple frameworks: SwiftUI, AVFoundation (camera), LocalAuthentication (Face ID), AuthenticationServices (Sign in with Apple), CryptoKit, Security (keychain).

---

# Part 3: SwiftUI Deep Dive

## 3.1 The Mental Model: UI = f(State)

SwiftUI is React for native. A `View` is a struct with a `body` computed property that describes the UI for the current state. You never mutate the screen; you mutate state and the framework re-renders.

```swift
// From App/RecourseApp.swift, the whole program:
@main
struct RecourseApp: App {
    @State private var environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
                .tint(RecourseColor.ledger)
        }
    }
}
```

`@main` marks the entry point (like `fn main`). `some Scene` and `some View` are **opaque types**: "a concrete type the compiler knows but I will not name". Every `body` returns `some View`.

## 3.2 The State Toolbox

This is the part worth memorizing. Each property wrapper answers one question: **who owns this state?**

| Wrapper | Owner | Used for | Example in Recourse |
|---|---|---|---|
| `@State` | This view | Local, ephemeral UI state | `@State private var wordmarkIn = false` in `SplashView` |
| `@Binding` | A parent view | Two-way access to someone else's `@State` | Sheet visibility flags passed down |
| `@Observable` class | An object | Shared app state; views auto-track what they read | `AccountSession`, `BuyerPaymentStore`, `AppRouter` |
| `@Bindable` | An `@Observable` object | Make bindings into an observable | `@Bindable var router = environment.router` in `RootView` |
| `@AppStorage` | UserDefaults | Small persisted preferences | `@AppStorage("recourse.appearance") private var appearanceRaw = "dark"` |
| `@Environment` | The view tree | System values | `@Environment(\.colorScheme)` in `HomeView` |

The modern observation system (`@Observable`, iOS 17+) is what this app uses instead of the older `ObservableObject/@Published`. The magic: a view that reads `accountSession.isRestoring` re-renders when `isRestoring` changes, and ONLY then. No manual subscriptions, no `setState`.

```swift
// From Core/Auth/AccountSession.swift:
@Observable
final class AccountSession {
    private(set) var account: AuthenticatedAccount?
    private(set) var isRestoring = true
    // any view reading these properties re-renders on change
}
```

Dart comparison: this is Provider/Riverpod's job done by the language. React comparison: `@State` is `useState`, `@Observable` is a store with automatic selectors.

## 3.3 View Lifecycle: .task, .onAppear, .onChange

```swift
// From App/RootView.swift:
.task {
    await environment.accountSession.restore()
}
.task {
    try? await Task.sleep(for: .seconds(2.3))
    withAnimation(.easeInOut(duration: 0.45)) {
        isHoldingSplash = false
    }
}
```

`.task` is the async lifecycle hook: it starts when the view appears and is **automatically cancelled** when the view disappears. That cancellation is free structured-concurrency hygiene you would hand-roll in JS with AbortController.

`.onAppear` is the synchronous cousin (used in `SplashView` to kick off animations). `.onChange(of:)` observes a value and reacts (used in `AppShellView` to react to policy list changes).

## 3.4 Layout in 60 Seconds

Three primitives compose almost every screen in this app:

```swift
VStack(spacing: 12) { ... }    // vertical stack (Column in Flutter)
HStack(spacing: 8) { ... }     // horizontal stack (Row)
ZStack { ... }                 // depth stack (Stack); SplashView is one
Spacer()                       // flexible space that pushes siblings apart
```

Modifiers wrap views and order matters: `.padding().background(...)` pads then paints; the reverse paints then pads. A real composite from `OnboardingWelcomeView`:

```swift
HStack(spacing: 8) {
    Image("ArcMark")
        .resizable()
        .scaledToFit()
        .frame(height: 13)
    Text("ARC TESTNET")
        .font(.caption.weight(.bold))
        .tracking(0.8)
}
.foregroundStyle(.white)
.padding(.horizontal, 14)
.frame(height: 36)
.recourseGlassCapsule()        // custom modifier from the design system
```

One hard-won lesson encoded in `OnboardingReadyView`: `ignoresSafeArea(.top)` combined with a fixed frame height must add the safe area inset back (`proxy.size.height + proxy.safeAreaInsets.top`), and overlays inherit safe-area insets, so do not add them twice. Safe-area math is the number one source of "why is my button floating" bugs.

## 3.5 Navigation

Navigation is state, not calls. `AppRouter` holds a `NavigationPath`; pushing a screen is appending an enum value:

```swift
// RootView owns the stack:
NavigationStack(path: $router.path) {
    AppShellView(environment: environment)
        .navigationDestination(for: AppRoute.self) { route in
            destination(for: route)      // switch AppRoute -> view
        }
}

// Anywhere in the app:
environment.router.push(.verdict(paymentID))
```

Because `AppRoute` is `Hashable` data, deep linking is trivial: decoding a checkout QR just pushes `.checkout(request)` onto the same path a user tap would.

Sheets follow the same philosophy: `.sheet(isPresented: $showsReceive) { ReceiveSheet(...) }`. Boolean state in, sheet out.

## 3.6 Animations and Transitions

Everything animated in this app uses one of two forms:

```swift
// 1. Explicit: animate the consequences of this state change
withAnimation(.easeInOut(duration: 0.35)) {
    hasCompletedOnboarding = true
}

// 2. Declarative: this view animates whenever `value` changes
.animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false), value: ripples)
```

The splash sequence (`SplashView`) is a masterclass in the basics: state flips once (`wordmarkIn = true`), and four properties animate from it simultaneously (glyph opacity and offset, wordmark opacity, and a leading-aligned mask whose width goes 0 to 260 to sweep the word in from the left). `.transition(.opacity)` on container swaps handles the crossfade into the app.

---

# Part 4: Swift Concurrency: async/await, Actors, MainActor

This codebase is a clean showcase of modern Swift concurrency. If you learn this part well, you have learned the hardest and most valuable thing here.

## 4.1 async/await Basics

Like JS, but with two differences that matter:

```swift
func address() async throws -> EthereumAddress
let addr = try await signer.address()
```

1. `await` marks a **suspension point**: the thread is freed while waiting; nothing is blocked.
2. Async functions do not start until awaited from a task context; there is no floating promise problem. If you want fire-and-forget, you say so explicitly with `Task { ... }`.

## 4.2 Actors: Data Races Made Impossible

An `actor` is a class whose state can only be touched by one caller at a time. The compiler enforces that all external access goes through `await`:

```swift
// From Core/Chain/ArcContractReader.swift:
actor ArcContractReader: ContractReading {
    private let erc20: EthereumContract
    private let escrow: EthereumContract
    // ...
    func payment(id: UInt64) async throws -> PaymentRecord { ... }
}
```

Why an actor? `EthereumContract` objects and the RPC transport are not thread-safe, and payments refresh concurrently from several screens. Making the reader an actor means those concurrent calls are automatically serialized. No locks, no queues, no data races, checked at compile time.

The same pattern protects secrets: `TestnetLocalSigner` is an actor (a keystore must never be used from two places at once), and `AccountSessionStore` is an actor around the keychain.

Compare with Rust: an actor is roughly `Arc<Mutex<T>>` where the compiler writes and checks all the locking for you. Compare with JS: it is like each actor having its own single-threaded event loop.

## 4.3 @MainActor: The UI Thread as a Type

UI state must be touched on the main thread. Swift encodes that in the type system:

```swift
// From App/AppEnvironment.swift:
@MainActor
@Observable
final class AppEnvironment { ... }
```

`AppEnvironment`, `AccountSession`, `BuyerPaymentStore`, and all views are `@MainActor`. If background code tries to set `isRestoring` directly, it does not crash mysteriously like in UIKit days: it fails to compile. Crossing over is explicit: `await MainActor.run { ... }` or calling an actor-isolated method with `await`.

## 4.4 Structured vs Unstructured Tasks

```swift
// From AccountSession.restore(), the boot-critical pattern:
try await accept(storedGrant)                              // structured: awaited inline
profileRefreshTask = Task { await refreshProfile(from: storedGrant) }  // unstructured: runs in background
```

This is the app's cold-start fix in miniature. The keychain read is awaited because boot needs it. The network refresh is wrapped in `Task { }` because boot must NOT wait on the network: the app renders instantly with the cached session, and the refresh catches up. The task is stored in a property so tests can `await session.profileRefreshTask?.value` to make the background work deterministic.

`.task {}` on views is the third flavor: structured to the view's lifetime, cancelled on disappear.

## 4.5 Sendable: Why Every Domain Type Declares It

`Sendable` marks types safe to send between actors. Value types of Sendable parts get it automatically, but this codebase declares it explicitly on domain types and protocols (`protocol ContractReading: Sendable`) as documentation and enforcement. When you add a mutable class property to a struct and it stops compiling, Sendable just saved you from a race you had not met yet.

---

# Part 5: App Architecture: Environment, Routing, Stores

## 5.1 The Composition Root

There is no dependency-injection framework. There is one class that wires everything, with defaults for production and injection seams for tests:

```swift
// From App/AppEnvironment.swift:
init(
    configuration: AppConfiguration,
    router: AppRouter = AppRouter(),
    accountSession: AccountSession? = nil,
    buyerSigner: (any BuyerSigner)? = nil,
    paymentStore: BuyerPaymentStore? = nil
) {
    self.buyerSigner = buyerSigner ?? TestnetLocalSigner()
    self.paymentStore = paymentStore ?? BuyerPaymentStore(
        configuration: configuration, signer: self.buyerSigner
    )
    self.accountSession = accountSession ?? AccountSession(
        api: AccountAPIClient(baseURL: configuration.apiURL)
    )
}

static func live() -> AppEnvironment { AppEnvironment(configuration: .live) }
```

Every default parameter is a test seam. Production calls `.live()`; tests call the initializer with fakes. This "pure DI" style scales surprisingly far and is worth copying in every project you build.

Factories like `makeContractGateway()` build heavier objects on demand instead of at boot, so the app does not parse four ABIs before the first frame.

## 5.2 Workspace Routing: One Function Decides the Whole UI

`RootView` renders exactly one of four worlds, decided by a pure function:

```swift
// From App/RootView.swift:
private var workspaceDestination: WorkspaceDestination {
    WorkspaceRouting.destination(
        isRestoring: environment.accountSession.isRestoring || isHoldingSplash,
        isAuthenticated: environment.accountSession.isAuthenticated,
        hasCompletedOnboarding: hasCompletedOnboarding,
        storedRole: storedWorkspaceRole
    )
}

switch workspaceDestination {
case .restoring:    SplashView()
case .buyerApp:     NavigationStack(path: $router.path) { AppShellView(...) }
case .merchantWeb:  MerchantWorkspaceView(...)
case .onboarding:   OnboardingFlowView(...)
}
```

Because `WorkspaceRouting.destination` is a static pure function of five booleans and strings, it has direct unit tests (`WorkspaceRoutingTests`). The highest-stakes decision in the app (what do you see when it opens) is trivially testable. Steal this pattern.

Two more app-wide policies live here as one-liners: the background color per branch, and `preferredColorScheme` (buyer app follows the user's dark/light choice; onboarding and merchant are pinned light).

## 5.3 Stores: Where Server and Chain State Lives

`BuyerPaymentStore` (in `AppEnvironment.swift`) is the read model: it polls the backend indexer for the payments belonging to this wallet and exposes them as observable arrays that `HomeView` and `ReceiptsFoundationView` render. Refresh is a `while !Task.isCancelled` loop inside a `.task`, which means polling stops automatically when the screen goes away. Writes never go through the store: they go through workflows to the chain, and the store simply observes the aftermath.

## 5.4 Workflows: Feature Logic Without UI

Each feature's `Domain/` folder holds a struct that owns one use case end to end, taking protocol dependencies:

```swift
// From Features/Verdict/Domain/VerdictWorkflow.swift:
struct VerdictWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let timeProvider: any UnixTimeProvider

    func inspect(paymentID: UInt64) async throws -> VerdictReadiness {
        let payment = try await gateway.payment(id: paymentID)
        guard payment.status == .disputed || payment.status == .settled else {
            throw BuyerWorkflowError.paymentNotDisputed
        }
        // ...
    }
}
```

Note `timeProvider`: even "what time is it" is injected (`UnixTimeProvider` protocol with a `SystemUnixTimeProvider` default), because dispute windows are time math and time math must be testable. Views construct workflows, call one method, and render the result. No business logic in views, no UI in workflows.

---

# Part 6: Auth and Security

## 6.1 Two Keys, Two Jobs

The most important conceptual split in the app:

- **Account** = who you are to the backend (Apple/Google sign-in, session tokens). Lives in `AccountSession`, persisted in the keychain.
- **Wallet** = the device key that signs transactions. Lives in `TestnetLocalSigner`, generated on the device, never leaves it.

Same account on a new phone gets a new wallet; a different account on the same phone reuses the device wallet. Money is bound to the device key; identity is bound to the backend session.

## 6.2 The Keychain Layer

`KeychainStore` wraps Apple's Security framework C API (`SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`) into a small async `SecureDataStore` protocol. Values are stored per service + account name and survive app reinstalls. The wrapping pattern to notice: nasty C APIs get one tiny Swift protocol, and everything above depends on the protocol (tests use an in-memory fake: `AccountSessionMemoryStore`).

## 6.3 The Signer

```swift
// From Core/Auth/TestnetLocalSigner.swift:
actor TestnetLocalSigner: BuyerSigner {
    func address() async throws -> EthereumAddress
    func sign(_ transaction: UnsignedTransaction) async throws -> Data
    func signEIP712(_ typedData: Data) async throws -> Data
    private func loadOrCreateKeystore() async throws -> EthereumKeystoreV3
}
```

First use generates an `EthereumKeystoreV3` (an encrypted Ethereum key file) with a random password; both are stored in the keychain. `signEIP712` is what signs typed structured data: dispute evidence uploads are authorized by an EIP-712 signature proving the caller is the onchain buyer, which is how the backend authenticates uploads without passwords.

`TransactionAuthorizer` gates money movement behind Face ID via `LocalAuthentication`: the biometric prompt succeeds, then and only then does the signer sign.

## 6.4 Session Restore, the Production Pattern

`AccountSession.restore()` shows a pattern you will reuse forever: **trust cache, verify async**.

1. Load the grant from the keychain (fast, local).
2. Check Apple credential state (revoked means clear and sign out).
3. Accept the cached grant immediately so the UI renders.
4. Kick a background task that calls `/me`; on 401 it rotates the refresh token; on a dead token it signs out; on network failure it keeps the cached session.

Boot never waits on a network round trip. The 15-second frozen splash this replaced is the fate of every app that validates sessions synchronously on launch.

---

# Part 7: Talking to Arc: web3swift and the Gateway Layer

## 7.1 The Stack

```
Feature workflow (CheckoutWorkflow, VerdictWorkflow...)
        |  any ContractGateway
ArcContractGateway            # composes reader + writer
   |-- ArcContractReader      # actor: eth_call reads
   |-- ArcContractWriter      # actor: builds, signs, sends transactions
        |  any ArcRPCTransport
ArcRPCTransport               # JSON-RPC over URLSession to the Arc RPC node
```

Contract addresses come from `AppConfiguration` (which comes from `Generated/Deployment.swift`). ABIs are bundled JSON files loaded through the `ContractABI` enum:

```swift
// From Core/Chain/ContractABI.swift (pattern):
enum ContractABI: String {
    case erc20 = "ERC20.abi"
    case escrow = "RecourseEscrow.abi"
    case policyRegistry = "PolicyRegistry.abi"
    case settlementVault = "SettlementVault.abi"
    func load(from bundle: Bundle) throws -> String { ... }
}
```

A read is: encode the method call with the ABI, `eth_call` it through the transport, decode the result, map it into a domain struct (`PaymentRecord`, `VaultState`). Every decode failure has a named error case (`malformedResult(method:)`, `unknownPaymentStatus(UInt8)`) instead of a crash.

A write is: build an `UnsignedTransaction` (nonce, gas, calldata), have the signer sign it (behind Face ID), `eth_sendRawTransaction`, then poll for the receipt and return a `ChainReceipt` whose `Outcome` enum the UI renders as staged progress ("approve, then deposit" in `EarnView`'s `VaultActionSheet`).

## 7.2 Money Is Not a Double

```swift
// Core/Domain/USDCAmount.swift (concept):
// USDC has 6 decimals. All math happens in integer base units.
```

`USDCAmount` stores base units (`5_200_000` = $5.20) and formats for display only at the edge. The one rule: never put money in a `Double`. `BigInt`/`BigUInt` handle chain-sized numbers; `UInt64` handles payment IDs and timestamps.

---

# Part 8: Determinism: Manifests, Hashes, Verdicts

This is the soul of the product, and the Swift code mirrors the Solidity and TypeScript engines byte for byte.

## 8.1 The Order Manifest: JSON Bytes as Identity

```swift
// From Core/Orders/OrderManifest.swift:
func encodedForPublishing() throws -> (bytes: Data, orderReference: ChainHash) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let bytes = try encoder.encode(self)
    return (bytes, bytes.keccak256Hash)
}
```

The keccak256 of the exact JSON bytes IS the `bytes32 orderRef` stored by the escrow. When the phone fetches an order, it rehashes the received bytes and refuses to display anything whose hash does not match:

```swift
guard bytes.keccak256Hash.value.lowercased() == orderReference.value.lowercased() else {
    // tampered or corrupted order: reject before the user ever sees it
}
```

The backend is therefore just a byte courier. It cannot alter a price without breaking a hash the phone independently checks. A cross-language golden fixture (one manifest whose hash is asserted in Rust, Swift, and TypeScript) pins all three implementations to identical bytes.

## 8.2 The Verdict: Recomputed, Not Trusted

`VerdictWorkflow` reads the payment, the policy, and the attestation from chain, and computes the verdict with the same first-match-wins rule evaluation as the Solidity engine, then compares hashes. The receipt screen's "Two engines, one result" is literal: one hash computed onchain, one recomputed on your phone, shown matching. Golden vectors in the test suite assert the Swift engine agrees with the canonical vectors that forge and vitest also assert.

The discipline to copy: **any logic that exists in two languages gets a shared fixture file and tests in both languages against it.**

---

# Part 9: QR Codes, the Camera, and Universal Links

## 9.1 Three Doors into the Same Checkout

A checkout can arrive three ways, and all of them decode to the same `PaymentRequest`:

1. In-app scanner (`ScannerFoundationView`, AVFoundation camera).
2. iPhone Camera app scanning a universal link `https://<web>/pay?request=...`, which opens the app via `onContinueUserActivity`.
3. The `recourse://` custom scheme, the fallback the web /pay page uses, arriving via `onOpenURL`.

```swift
// From App/RootView.swift:
.onOpenURL { url in openIncomingCheckout(url) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    if let url = activity.webpageURL { openIncomingCheckout(url) }
}
```

`PaymentRequestDecoder` validates chain ID, addresses, and amounts before anything is shown; a QR that does not verify is rejected with a human error, not rendered. A checkout QR is a price tag, not a ticket: every scan that pays creates an independent escrowed payment.

## 9.2 Generating QR Codes

`ReceiveSheet` renders the wallet address as a QR with CoreImage's `CIFilter.qrCodeGenerator`, scaled with nearest-neighbor interpolation so it stays sharp, on a white tile in both themes because scanners want contrast, not aesthetics.

---

# Part 10: The Design System

## 10.1 Adaptive Color Tokens

The design system encodes the project's two visual laws: onboarding is white and green forever, and the in-app dark theme is flat black with no container-on-container nesting.

```swift
// From Core/DesignSystem/RecourseColor.swift:
static let night     = adaptive(light: (1.0, 1.0, 1.0),   dark: (0.027, 0.035, 0.03))
static let nightText = adaptive(light: (0.07, 0.09, 0.08), dark: (0.93, 0.95, 0.93))

private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(...) : UIColor(...)
    })
}
```

`night*` tokens resolve per color scheme automatically, so one sweep of the codebase (`ink -> nightText`, `canvas -> night`) made the whole buyer app theme-aware. The static palette (`ink`, `canvas`, `ledger`) stays fixed for onboarding. The user's choice is one `@AppStorage` string, applied at a single point in `RootView` via `preferredColorScheme`. Theme systems fail when color decisions are scattered; this one works because every color goes through `RecourseColor`.

## 10.2 The Card Faces

`WalletCardStyle` is a `CaseIterable` enum of thirteen faces. Each case knows its background image and, crucially, `prefersDarkText`, from which text, chip, and border colors derive. Adding a card face is adding one enum case; every screen rendering cards updates itself. When variation is finite and knowable, an enum beats a configuration object.

## 10.3 Asset Catalog Tricks Used Here

- **Appearance variants**: `ArcMark.imageset` has a light SVG (navy) and a dark SVG (white); `Image("ArcMark")` picks per theme with zero code. Forcing one variant is `.environment(\.colorScheme, .dark)` (done on the onboarding chip, which sits on photo glass).
- **Vector preservation**: `"preserves-vector-representation": true` keeps SVGs crisp at any size.
- **Launch screen**: no storyboard; `Info.plist` declares `UILaunchScreen` with an image + background color from the catalog. iOS caches a rendered snapshot of it, which is why launch-screen changes sometimes need a reinstall or reboot to appear.

---

# Part 11: Testing

## 11.1 The Shape of the Suite

`RecourseTests/` tests domain logic, not pixels: workflows, routing, session, engine vectors, manifest hashing. The enabler is that every dependency is a protocol, so `DomainTestDoubles.swift` provides fakes:

```swift
// Pattern from RecourseTests/DomainTestDoubles.swift:
final class FakeContractGateway: ContractGateway {
    var vault = VaultState(totalAssets: 11_251_250, totalShares: 7_998_750, ...)
    // records calls, returns canned values
}
```

## 11.2 Async Tests

XCTest supports async directly, and `@MainActor` on the test class matches the isolation of the code under test:

```swift
// From RecourseTests/AccountSessionTests.swift:
@MainActor
final class AccountSessionTests: XCTestCase {
    func testRestoresAnAuthorizedBackendSession() async throws {
        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .authorized),
            api: api
        )
        await session.restore()
        XCTAssertTrue(session.isAuthenticated)
    }
}
```

When `restore()` gained a background refresh task, the test for token rotation gained one line: `await session.profileRefreshTask?.value`. Exposing in-flight tasks as properties is the standard trick for making fire-and-forget work deterministic in tests.

## 11.3 Running Tests

```bash
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

Golden vectors deserve a highlight: the same 14 verdict fixtures asserted by forge (Solidity) and vitest (TypeScript) are asserted here in Swift. Cross-language behavior is pinned by shared data, not by hope.

---

# Part 12: Xcode, the Generated Project, and Shipping

## 12.1 Why the .xcodeproj Is Generated

`Recourse.xcodeproj` is produced by `scripts/generate_project.rb` (using the `xcodeproj` gem). The pbxproj file format is a merge-conflict machine; generating it from a script makes the project reproducible and reviewable. Build settings live in Ruby, including `INFOPLIST_KEY_*` entries that merge with `Info.plist`.

The workflow after adding or removing a Swift file:

```bash
cd mobile && ruby scripts/generate_project.rb && open Recourse.xcodeproj
```

## 12.2 Info.plist Things You Will Touch

- `CFBundleURLTypes`: registers the `recourse://` scheme.
- `UILaunchScreen`: the splash's static first frame.
- `ITSAppUsesNonExemptEncryption = false`: the export-compliance declaration that stops App Store Connect asking per build.
- Usage descriptions (camera, Face ID) live as `INFOPLIST_KEY_*` build settings in the generator script.

## 12.3 Command-Line Builds

```bash
# Build for a specific simulator (id from `xcrun simctl list devices`)
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'id=<SIMULATOR-UDID>' build

# Install + launch + screenshot on the simulator
xcrun simctl install <UDID> path/to/Recourse.app
xcrun simctl launch <UDID> com.recourse.buyer
xcrun simctl io <UDID> screenshot shot.png
```

If a build fails with inexplicable database errors, suspect DerivedData (Xcode's build cache): pass a fresh `-derivedDataPath` or delete the cache.

## 12.4 Shipping Checklist

Archive (Product > Archive) requires: a bundle ID matching App Store Connect, the encryption declaration, and no `#Preview` referencing DEBUG-only helpers (previews compile in Release too; wrap them in `#if DEBUG`). TestFlight is the low-ceremony distribution path while the app is testnet-only.

---

# Part 13: Common Patterns Reference

A cheat sheet of idioms this codebase uses that you will use in every Swift project.

## 13.1 guard: The Early Exit

```swift
guard payment.status == .disputed || payment.status == .settled else {
    throw BuyerWorkflowError.paymentNotDisputed
}
```

`guard` flips the if: state your requirement, handle failure in the else, and continue at the same indent level. Chains of guards read like a checklist and keep the happy path unindented.

## 13.2 defer: Cleanup That Cannot Be Forgotten

```swift
// From AccountSession.restore():
guard isRestoring else { return }
defer { isRestoring = false }     // runs on EVERY exit path from this function
```

Every return, throw, or fall-through flips `isRestoring` exactly once. This is Go's defer / Rust's Drop for a single scope.

## 13.3 Collection Transforms

```swift
[givenName, familyName]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }  // drop nils
    .filter { !$0.isEmpty }
    .joined(separator: " ")
```

`map`, `compactMap` (map + drop nils), `filter`, `first(where:)`, `contains(where:)`, `sorted(by:)`. These replace nearly every for-loop.

## 13.4 Computed Properties Over Functions

```swift
var isAuthenticated: Bool { account != nil }
```

If it takes no arguments and answers a question about current state, make it a computed property. SwiftUI bodies are full of these (`workspaceDestination`, `heroSubtitle`, `sharePrice`).

## 13.5 #if DEBUG and Previews

```swift
#if DEBUG
#Preview { SplashView() }
#endif
```

Previews render the view in Xcode's canvas with fake dependencies. The `#if DEBUG` guard matters: previews compile in all configurations, so referencing DEBUG-only helpers without the guard breaks Release archives (this repo learned that the expensive way).

## 13.6 Things You Will Meet Next (Not Yet in This Codebase)

- **AsyncSequence / AsyncStream**: for-await over event streams; the natural upgrade from the polling loops in `BuyerPaymentStore`.
- **TaskGroup**: structured fan-out (`withThrowingTaskGroup`) when you need N parallel chain reads with automatic cancellation.
- **Swift 6 strict concurrency**: turns every remaining data-race warning into an error; this codebase's actor + Sendable discipline is the preparation.
- **Macros**: `@Observable` is one; you can write your own for boilerplate.
- **SwiftData**: Apple's persistence layer, if the app ever needs an offline cache beyond the keychain.
- **widgets and App Intents**: the natural next surface for "protection status at a glance".

## 13.7 The Five Ideas Worth Stealing From This App

1. Protocols at every boundary, fakes in tests (`ContractGateway`, `BuyerSigner`, `SecureDataStore`).
2. Pure functions for high-stakes decisions (`WorkspaceRouting.destination`).
3. Actors around anything not thread-safe (RPC, keystore, keychain).
4. Trust cache, verify async: never block first render on a network call.
5. One source of truth per fact: colors through `RecourseColor`, addresses through `Generated/Deployment.swift`, money in integer base units.

---

Built alongside the Recourse protocol for the Build on Arc hackathon. The backend has a Rust guide of the same spirit; read the two together and you have the whole system.
