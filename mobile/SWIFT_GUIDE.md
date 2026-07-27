# The Recourse iOS App: A Complete Swift + SwiftUI Guide

**From Zero Swift to Full Understanding of This Codebase**

Written for a developer who knows JavaScript/Dart (and now some Rust, from the backend guide) and is learning Swift by understanding every line of the Recourse buyer protection app: a native SwiftUI wallet that pays USDC into escrow on Arc, signs evidence with Face ID, and recomputes onchain verdicts on the phone.

Read Part 1 slowly, even if it feels basic. Every later part assumes it. The style follows the Rust backend guide: core language first, one concept at a time, with JavaScript, Dart, and Rust as mirrors, and with real lines from this codebase showing where each concept earns its keep.

----

## Table of Contents

- [Part 1: Core Swift, The Language](#part-1-core-swift-the-language)
- [Part 2: Project Structure](#part-2-project-structure)
- [Part 3: SwiftUI, The UI Framework](#part-3-swiftui-the-ui-framework)
- [Part 4: Swift Concurrency: async/await, Actors, MainActor](#part-4-swift-concurrency-asyncawait-actors-mainactor)
- [Part 5: The App, Layer by Layer](#part-5-the-app-layer-by-layer)
- [Part 6: Auth and Security](#part-6-auth-and-security)
- [Part 7: Talking to Arc: the Chain Layer](#part-7-talking-to-arc-the-chain-layer)
- [Part 8: Determinism: Manifests, Hashes, Verdicts](#part-8-determinism-manifests-hashes-verdicts)
- [Part 9: QR Codes, the Camera, and Universal Links](#part-9-qr-codes-the-camera-and-universal-links)
- [Part 10: The Design System](#part-10-the-design-system)
- [Part 11: Testing](#part-11-testing)
- [Part 12: Xcode, the Generated Project, and Shipping](#part-12-xcode-the-generated-project-and-shipping)
- [Part 13: Common Patterns Reference](#part-13-common-patterns-reference)
- [Part 14: UIKit and Interop (What Big Apps Are Really Made Of)](#part-14-uikit-and-interop-what-big-apps-are-really-made-of)
- [Part 15: Networking at Scale](#part-15-networking-at-scale)
- [Part 16: Media: Camera, Video, and the TikTok Feed](#part-16-media-camera-video-and-the-tiktok-feed)
- [Part 17: Persistence and Offline](#part-17-persistence-and-offline)
- [Part 18: Performance for a Billion Users](#part-18-performance-for-a-billion-users)
- [Part 19: Push, Background Work, and System Surfaces](#part-19-push-background-work-and-system-surfaces)
- [Part 20: Swift for Blockchain Beyond EVM: Solana and Jupiter](#part-20-swift-for-blockchain-beyond-evm-solana-and-jupiter)
- [Part 21: Architecture at Scale](#part-21-architecture-at-scale)
- [Part 22: Release Engineering](#part-22-release-engineering)
- [Part 23: The 80 Percent Roadmap](#part-23-the-80-percent-roadmap)

----

# Part 1: Core Swift, The Language

Before touching a single view or a single blockchain call, you need the language itself. Swift sits somewhere between Dart and Rust: friendlier than Rust (no borrow checker, no lifetimes), stricter than Dart (optionals are enforced, value types are real). If you rushed through this part you would be able to *read* the codebase but not *predict* it. So do not rush it.

## 1.1 Variables and Constants: let and var

In JavaScript you have `let` and `const`. In Swift the equivalents are `var` and `let`, and the meanings are swapped in a way that trips people up for a week:

```swift
var count = 0          // variable, can be reassigned (like JS `let`)
let name = "Frank"     // constant, can NEVER be reassigned (like JS `const`)

count = 1              // fine
// name = "Olien"      // COMPILE ERROR: cannot assign to value: 'name' is a 'let' constant
```

Compare all four languages:

| Concept | JavaScript | Dart | Rust | Swift |
|---|---|---|---|---|
| Reassignable variable | `let x = 0` | `var x = 0` | `let mut x = 0` | `var x = 0` |
| Constant | `const x = 0` | `final x = 0` | `let x = 0` | `let x = 0` |

Notice that Swift's `let` is Rust's `let`: immutable by default is the culture in both languages. The Swift community treats `var` the way Rust treats `mut`: a small signal that says "watch this one, it changes."

**Where you see this in Recourse:** open almost any file and count. In `Core/Config/AppConfiguration.swift`, every property is `let`:

```swift
struct AppConfiguration: Sendable {
    let rpcURL: URL
    let chainID: UInt64
    let chainName: String
    let escrowAddress: EthereumAddress
    // ...
}
```

Configuration never changes after boot, so every field is a constant. The compiler now guarantees that nothing anywhere in the app can quietly rewrite the escrow address. In a money app, that one keyword is a security feature.

## 1.2 Types and Type Inference

Swift is statically typed like Rust and Dart, not dynamically typed like JavaScript. Every value has exactly one type, known at compile time. But you rarely *write* the type, because the compiler infers it:

```swift
let city = "Lagos"           // inferred as String
let year = 2026              // inferred as Int
let price = 5.20             // inferred as Double
let isLive = true            // inferred as Bool

let chainID: UInt64 = 5042002   // explicit, because we want UInt64, not Int
```

That last line matters. When the default inference would pick the wrong type, you annotate with `: Type` after the name. `5042002` would infer as `Int`; the chain protocol wants an unsigned 64-bit integer, so the codebase says so explicitly.

The core types you will meet constantly:

| Swift type | What it is | JS equivalent | Rust equivalent |
|---|---|---|---|
| `String` | Unicode text | `string` | `String` |
| `Int` | Platform integer (64-bit on iPhone) | `number` (sort of) | `i64` |
| `UInt64` | Unsigned 64-bit integer | none (BigInt-ish) | `u64` |
| `Double` | 64-bit float | `number` | `f64` |
| `Bool` | true/false | `boolean` | `bool` |
| `Data` | Raw bytes | `Uint8Array` | `Vec<u8>` |
| `[String]` | Array of strings | `string[]` | `Vec<String>` |
| `[String: Int]` | Dictionary | `Record<string, number>` | `HashMap<String, i64>` |
| `Set<String>` | Unique unordered values | `Set<string>` | `HashSet<String>` |

Two things to burn in early:

**1. Swift never converts numbers implicitly.** In JavaScript, `1 + 1.5` just works. In Swift, adding an `Int` to a `Double` is a compile error; you must convert explicitly with `Double(myInt)` or `UInt64(myInt)`. This feels pedantic until you remember what this app does: it moves money. Silent numeric conversion is exactly the class of bug you want the compiler to refuse.

**2. String interpolation uses `\( )`.**

```swift
let amount = "5.20"
let sentence = "You paid \(amount) USDC"   // JS: `You paid ${amount} USDC`
```

**Where you see this in Recourse:** `Core/Domain/USDCAmount.swift` exists precisely because of point 1. USDC has 6 decimal places, and the app NEVER stores money as `Double` (floats cannot represent 0.1 exactly; add enough of them and cents go missing). Instead, amounts live as integer base units: $5.20 is stored as `5_200_000`. The underscores in number literals are just for readability, like `5_200_000` in Rust. Money as integers, formatting only at the display edge: the same rule the Qent backend follows with kobo.

## 1.3 Functions

The basic shape:

```swift
func add(a: Int, b: Int) -> Int {
    return a + b
}

let sum = add(a: 2, b: 3)    // note: you WRITE the parameter names at the call site
```

Three Swift-specific things to understand:

**1. Argument labels are part of the function.** Unlike JS or Rust, calling `add(2, 3)` is a compile error; the call must say `add(a: 2, b: 3)`. This reads strangely for arithmetic but beautifully for real APIs:

```swift
// From Core/Chain: reads like a sentence
try await gateway.payment(id: 13)
try await signer.signEIP712(typedData)
```

If a label would be noise, the author suppresses it with an underscore:

```swift
func sign(_ transaction: UnsignedTransaction) async throws -> Data
// call site: signer.sign(tx)   not   signer.sign(transaction: tx)
```

**2. Single-expression functions can omit `return`.**

```swift
func double(_ x: Int) -> Int { x * 2 }    // no `return` needed
```

**3. Default parameter values** work like Dart:

```swift
init(
    configuration: AppConfiguration,
    router: AppRouter = AppRouter(),          // default: make a fresh one
    accountSession: AccountSession? = nil     // default: nil, filled in later
) { ... }
```

This exact snippet is from `App/AppEnvironment.swift` and it is the backbone of how the whole app is tested: production code calls the initializer with no extras and gets real objects; tests pass fakes for any parameter they care about. Hold that thought until Part 5.

## 1.4 Control Flow

`if` needs no parentheses but always needs braces:

```swift
if balance > 0 {
    print("funded")
} else {
    print("empty")
}
```

`for` loops iterate over sequences, like Rust's `for x in`:

```swift
for payment in payments { ... }
for i in 0..<5 { ... }       // 0,1,2,3,4  (half-open range)
for i in 1...5 { ... }       // 1,2,3,4,5  (closed range)
```

`switch` is Rust's `match` wearing a different jacket. It is EXHAUSTIVE: you must handle every possible case or the code does not compile, and there is no fall-through by default:

```swift
switch payment.status {
case .paid:
    print("in escrow")
case .disputed:
    print("window open, claim filed")
case .settled:
    print("verdict executed")
case .none:
    print("does not exist")
}
```

If the enum gains a new case tomorrow, every `switch` over it in the entire app becomes a compile error until each one says what to do. In JavaScript, a forgotten `case` is a silent bug found in production. In Swift (and Rust), it is a red squiggle found in the editor. This is the single feature that makes big refactors in this codebase safe.

You can match several cases at once, bind values, and add conditions:

```swift
case .ready(let preview), .settled(let preview):   // two cases, same handling
    show(preview)
case .awaitingAttestation(let until) where until > now:
    showCountdown(until)
```

`guard` is the one control-flow keyword you have not met in any of your languages. We give it its own section (1.6) because the codebase leans on it everywhere.

## 1.5 Optionals: The Concept That Runs the Whole Language

This is the most important section of Part 1. Everything else in Swift is negotiable; optionals are not.

### The problem optionals solve

In JavaScript, any variable can be `null` or `undefined` at any time, and you find out when it explodes at runtime:

```javascript
const user = findUser(id);      // might be null, nothing warns you
console.log(user.email);        // TypeError: Cannot read properties of null
```

Rust solved this with `Option<T>`: a value is either `Some(value)` or `None`, and the compiler forces you to handle both. Swift has exactly the same idea with lighter syntax. A `String` is always, definitely, a string. If a value might be absent, its type says so with a question mark: `String?`.

```swift
var email: String? = nil        // "String or nothing"; starts as nothing
email = "gkenny896@gmail.com"   // now it holds a value
```

Under the hood `String?` literally IS an enum, just like Rust:

```swift
// What the compiler sees:
enum Optional<Wrapped> {
    case none              // Rust: None
    case some(Wrapped)     // Rust: Some(value)
}
```

The crucial rule: **you cannot use an optional as if it were the plain value.** `email.count` does not compile when `email` is `String?`. You must unwrap it first, and Swift gives you five ways, each with its own job.

### Unwrapping tool 1: if let

```swift
if let email = email {
    // inside these braces, `email` is a plain String
    print("email is \(email)")
} else {
    // it was nil
}
```

Let me break this down piece by piece:

1. `if let email = email` means: "if the optional on the right contains a value, copy that value into a new non-optional constant on the left, and enter the braces."
2. Shadowing the same name (`email = email`) is idiomatic; since Swift 5.7 you can even shorten it to `if let email`.
3. If the optional is nil, the whole block is skipped and the `else` runs.

This is Rust's `if let Some(email) = email` with less punctuation, or Dart's `if (email != null)` with actual compiler enforcement.

### Unwrapping tool 2: guard let (the codebase favorite)

`if let` indents your happy path deeper and deeper. `guard let` flips it: state what you need, bail out if you do not have it, and continue at the SAME indent level:

```swift
// From Core/Auth/AccountSession.swift, the restore function:
guard let storedGrant = try await store.load() else { return }
// from this line to the end of the function, storedGrant is non-optional
```

Read it as: "I require a stored grant. If there is none, we are done here." The `else` block of a `guard` MUST exit (return, throw, continue, or break); the compiler checks that too, so there is no way to sneak past a failed guard.

A chain of guards reads like a checklist, which is why workflows in this codebase are so legible:

```swift
guard let request = decoder.decode(qrPayload) else { throw ScanError.notACheckout }
guard request.chainID == configuration.chainID else { throw ScanError.wrongChain }
guard request.amount.baseUnits > 0 else { throw ScanError.zeroAmount }
// happy path continues, un-indented, with everything validated
```

### Unwrapping tool 3: nil-coalescing with ??

Provide a default, exactly like JS `??` or Rust's `unwrap_or`:

```swift
// From AccountSession.swift, the label shown in the merchant header:
var accountLabel: String {
    email ?? displayName ?? "APPLE ACCOUNT"
}
```

Piece by piece: try `email`; if nil, try `displayName`; if that is nil too, fall back to the literal. Three fallbacks, one line, impossible to forget a case.

### Unwrapping tool 4: optional chaining with ?.

Reach through an optional; if anything on the way is nil, the whole expression is nil:

```swift
environment.accountSession.account?.accountLabel
// if account is nil, the result is nil (type String?), no crash
```

Same as JS `?.` and Dart `?.`. You will see this constantly in SwiftUI code that renders "whatever we have."

### Unwrapping tool 5: force unwrap with ! (almost never)

```swift
let url = URL(string: "https://api.frankolien.com")!
```

The `!` means "I promise this is not nil; crash the app if I am wrong." It is Rust's `.unwrap()`. The codebase allows it in exactly one situation: compile-time constants that cannot fail, like a hard-coded URL that you can see is valid. Force-unwrapping anything that came from the network, the user, or the chain is how apps end up in crash reporters. When in doubt, `guard let`.

### Where optionals live in this codebase

`Core/Auth/AccountSession.swift` models the signed-in account:

```swift
struct AuthenticatedAccount: Codable, Equatable, Sendable {
    let accountID: Int64
    let providerUserID: String
    let email: String?          // backend may not have an email for this account
    let givenName: String?      // Apple only shares the name on FIRST sign-in
    let familyName: String?
}
```

Look at which fields are optional and which are not. An account ALWAYS has an ID and a provider ID, so those are plain types. Email and name genuinely may not exist, so the type admits it. This mirrors exactly how the Rust guide mapped `Option<f64>` to NULLABLE database columns: the type system is documenting reality, not being difficult.

And the session itself:

```swift
private(set) var account: AuthenticatedAccount?
var isAuthenticated: Bool { account != nil }
```

"Signed in" is not a separate boolean that could drift out of sync; it is DEFINED as "the optional has a value." One source of truth.

## 1.6 Structs vs Classes: Value Types vs Reference Types

This is the deepest difference between Swift and every language you have used except Rust. Get this one right and half the architecture of the app explains itself.

### The behavior difference

```swift
struct PointS { var x: Int }
class  PointC { var x: Int; init(x: Int) { self.x = x } }

var s1 = PointS(x: 1)
var s2 = s1            // COPY: s2 is a brand-new, independent value
s2.x = 99
print(s1.x)            // 1   (s1 untouched)

let c1 = PointC(x: 1)
let c2 = c1            // REFERENCE: c2 points at the SAME object
c2.x = 99
print(c1.x)            // 99  (there is only one object)
```

A picture of what just happened in memory:

```
 STRUCT (value semantics)             CLASS (reference semantics)

  s1: [ x: 1 ]                          c1 ----+
                                               +----> [ x: 99 ]  one object
  s2: [ x: 99 ]   two values            c2 ----+
```

Dart and JavaScript only have the right-hand column: every object is a reference. Rust has both, but makes you manage references with the borrow checker. Swift has both and copies are automatic and cheap (the compiler copies lazily behind the scenes, a trick called copy-on-write).

### How this codebase decides which to use

The rule, applied with total consistency:

| | Use a `struct` when... | Use a `class` when... |
|---|---|---|
| The thing is | data, facts, a snapshot | a living object with a lifecycle |
| Identity | two equal copies are interchangeable | THIS one matters, copies would be a bug |
| Examples here | `OrderManifest`, `PaymentRecord`, `USDCAmount`, `ChainHash`, every SwiftUI view | `AccountSession`, `AppEnvironment`, `BuyerPaymentStore`, `AppRouter` |

Think about why `AccountSession` must be a class: it owns a keychain store and an in-flight network task. If you copied it, which copy owns the keychain? Which copy's `isRestoring` is the real one? Reference semantics say: there is one session, everyone points at it.

And why `PaymentRecord` must be a struct: it is a row of facts read from the chain. Hand a copy to three screens; if one screen could mutate the shared object underneath the other two (as would happen with a class), you get the spooky action-at-a-distance bugs that plague JS state management. Value semantics make that impossible: your copy is yours.

One more difference: structs get a free memberwise initializer (`PointS(x: 1)` just works), classes make you write `init` yourself. You can see this in the snippet above.

## 1.7 Enums: States That Cannot Be Wrong

Swift enums are Rust enums: full algebraic data types where each case can carry its own payload. This is much stronger than C-style or Dart enums.

Start simple:

```swift
enum Theme {
    case dark
    case light
}
let current: Theme = .dark   // note: type known, so you can write .dark, not Theme.dark
```

Now the real power, straight from `Features/Verdict/Domain/VerdictWorkflow.swift`:

```swift
enum VerdictReadiness: Equatable, Sendable {
    case awaitingAttestation(until: UInt64)   // carries a deadline timestamp
    case ready(VerdictPreview)                // carries a computed preview
    case settled(VerdictPreview)              // carries the final one
}
```

Let me break down why this is better than the JavaScript way. In JS you would model this as:

```javascript
{ state: "ready", until: undefined, preview: {...} }   // hope nobody reads `until`
```

Every field exists in every state, and discipline alone keeps you from reading `until` when the state is `ready`. In the Swift version, `until` PHYSICALLY DOES NOT EXIST unless the case is `.awaitingAttestation`. The compiler will not let you ask for a preview from a case that has none. Illegal states are unrepresentable; an entire category of bugs is deleted at the type level.

Consuming it, with the exhaustive `switch` from 1.4:

```swift
switch readiness {
case .awaitingAttestation(let until):
    showCountdown(endingAt: until)
case .ready(let preview), .settled(let preview):
    show(preview)
}
```

**The second big example** is navigation. `App/AppRouter.swift` defines every screen you can navigate to as an enum:

```swift
enum AppRoute: Hashable {
    case checkout(PaymentRequest)   // going to checkout REQUIRES a request
    case payment(UInt64)            // a payment screen REQUIRES a payment id
    case dispute(UInt64)
    case verdict(UInt64)
    case send
    case earn
    case account
}
```

You cannot navigate to a payment screen without a payment ID, because the case will not construct without one. Add a new screen and the compiler walks you to every place that must handle it. Compare that with string-based routing ("/payment/13") where a typo is a blank screen.

Enums can also have raw values (`enum ContractABI: String`), computed properties, and methods. `Core/DesignSystem/WalletCardStyle.swift` is an enum of thirteen card faces where each case knows its background image and whether it wants dark text; adding a fourteenth face is adding one case, and every screen updates itself.

## 1.8 Protocols: The Backbone of This Codebase

A protocol is an interface: a list of requirements with no implementation. Dart's `abstract class`, TypeScript's `interface`, Rust's `trait`. In this codebase, protocols are not a nice-to-have; they are THE architectural tool.

```swift
// From Core/Chain/ContractGateway.swift, trimmed:
protocol ContractReading: Sendable {
    func payment(id: UInt64) async throws -> PaymentRecord
    func vaultState(of owner: EthereumAddress) async throws -> VaultState
}

protocol ContractWriting: Sendable {
    func pay(request: PaymentRequest) async throws -> ChainHash
}

// Protocol composition: a gateway is anything that can do BOTH.
protocol ContractGateway: ContractReading, ContractWriting {}
```

Piece by piece:

1. `protocol ContractReading` declares a capability: "things that can read contract state."
2. `: Sendable` means anything conforming must also be safe to pass between threads (Part 4 explains Sendable).
3. The functions have signatures but no bodies. `async throws` says every implementation will be asynchronous and can fail.
4. `ContractGateway: ContractReading, ContractWriting {}` composes two protocols into one and adds nothing else. Rust readers: this is `trait ContractGateway: ContractReading + ContractWriting {}`.

A type conforms by declaring it and implementing the requirements:

```swift
actor ArcContractReader: ContractReading {
    func payment(id: UInt64) async throws -> PaymentRecord { /* real RPC call */ }
    func vaultState(of owner: EthereumAddress) async throws -> VaultState { /* ... */ }
}
```

### Why the codebase worships this pattern

Every feature workflow depends on the PROTOCOL, never the concrete type:

```swift
// From Features/Verdict/Domain/VerdictWorkflow.swift:
struct VerdictWorkflow: Sendable {
    private let gateway: any ContractGateway      // "some conforming type, whoever you are"
    private let timeProvider: any UnixTimeProvider
}
```

Because the workflow only knows the protocol, tests hand it a `FakeContractGateway` that returns canned data instantly, with no network, no chain, no keys. The workflow cannot tell the difference. Every domain test in `RecourseTests/` exists because of this one design decision. It is the same move the Qent backend makes with its `service` modules, taken further.

Note the `UnixTimeProvider`: even "what time is it now" is behind a protocol, because dispute windows are time math and time math must be testable with a frozen clock.

### any and some

Two keywords appear in front of protocol names and confuse everyone at first:

- `any ContractGateway` is an **existential**: a box holding some conforming value decided at runtime. Slightly slower (a pointer indirection), maximally flexible. Used for stored dependencies, as above.
- `some View` is an **opaque type**: one specific conforming type, known to the compiler, hidden from you. Fast, and it is how every SwiftUI `body` is declared (Part 3).

Rule of thumb: `any` when the concrete type varies at runtime (dependency injection), `some` when it is fixed but ugly to spell (SwiftUI).

### Extensions: adding behavior to anything

An `extension` adds methods, computed properties, or protocol conformances to a type, even one you do not own:

```swift
// From AccountSession.swift: a private helper grafted onto a domain type
private extension AccountSessionGrant {
    func replacingAccount(_ account: AuthenticatedAccount) -> Self {
        AccountSessionGrant(accessToken: accessToken,
                            refreshToken: refreshToken,
                            account: account)
    }
}
```

The design system uses extensions on SwiftUI's own `View` protocol to grow the app's private vocabulary: `.recourseGlassCapsule()`, `.recourseKeyboardDismissal()`. When you see a modifier you do not recognize in this codebase, it is an extension in `Core/DesignSystem/`.

## 1.9 Closures: Functions as Values

A closure is an anonymous function you can store and pass around: JS arrow functions, Dart lambdas, Rust closures. The syntax compresses in stages, and you need to recognize every stage because SwiftUI uses the shortest one relentlessly.

Watch the same closure shrink:

```swift
let numbers = [1, 2, 3]

// Stage 1: fully explicit
let a = numbers.map({ (n: Int) -> Int in return n * 2 })

// Stage 2: types inferred from context
let b = numbers.map({ n in return n * 2 })

// Stage 3: single expression, `return` dropped
let c = numbers.map({ n in n * 2 })

// Stage 4: positional shorthand ($0 = first argument)
let d = numbers.map({ $0 * 2 })

// Stage 5: trailing closure, parentheses gone
let e = numbers.map { $0 * 2 }
```

The `in` keyword in stages 1 to 3 separates the parameter list from the body (an odd historical choice; just memorize it). Stage 5 is the **trailing closure** rule: when the last argument to a function is a closure, it can move outside the parentheses. When a function takes SEVERAL closures, they stack with labels:

```swift
Button {
    router.push(.earn)          // first closure: what tapping does
} label: {
    Text("Earn")                // second closure, labeled: what it looks like
}
```

Read that again until it stops looking like magic syntax: `Button` is just a function taking two closures. ALL of SwiftUI is this. The "markup language" you will see in Part 3 is plain Swift closures all the way down.

The collection combinators you will use daily, with the Rust names you already know:

| Swift | What it does | Rust |
|---|---|---|
| `map { }` | transform each element | `map` |
| `compactMap { }` | transform, dropping nils | `filter_map` |
| `filter { }` | keep matching elements | `filter` |
| `first(where:)` | first match as an optional | `find` |
| `contains(where:)` | does any match | `any` |
| `sorted(by:)` | sorted copy | `sorted_by` |
| `reduce(0) { }` | fold to one value | `fold` |

A real chain from `AccountSession.swift`, computing a display name from optional parts:

```swift
[givenName, familyName]                                            // [String?]
    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) } // drop nils, trim
    .filter { !$0.isEmpty }                                        // drop empties
    .joined(separator: " ")                                        // "Frank Olien"
```

## 1.10 Error Handling: throws, try, do/catch

Swift errors look like exceptions but behave like Rust results: a function that can fail SAYS SO in its signature, and callers are forced to acknowledge it at the call site.

### Defining errors

Any type can be an error by conforming to `Error`; in practice you use enums, one per layer, so failures are precise:

```swift
// From Core/Chain/ArcContractReader.swift:
enum ContractReadError: Error, Equatable, Sendable {
    case missingABI(String)
    case invalidRPCResponse
    case rpc(code: Int, message: String)
    case malformedResult(method: String)
    case unknownPaymentStatus(UInt8)
}
```

Compare with the Rust guide's approach of matching on `sqlx::Error`: same philosophy, each failure is a named, typed case, not a string.

### Throwing and catching

```swift
func load(from bundle: Bundle) throws -> String { ... }   // "I can fail"

do {
    let abi = try loader.load(from: bundle)   // `try` marks the risky call
    use(abi)
} catch let error as ContractReadError {
    // typed catch: only ContractReadError lands here
    handleChainProblem(error)
} catch {
    // everything else; `error` is implicitly in scope
    print("unexpected: \(error)")
}
```

Piece by piece:

1. `throws` in the signature is the contract. Without it, a function CANNOT throw. (JS: any function might throw and nothing warns you.)
2. `try` at the call site is mandatory. It does nothing at runtime; it exists so a reader can see every line that can fail. Rust's `?` plays the same "visible risk" role.
3. `do { } catch { }` is the handling block. Catches can pattern-match on type and even add conditions.

The most instructive real catch in the codebase, from `AccountSession.swift`:

```swift
do {
    let profile = try await api.me(accessToken: storedGrant.accessToken)
    try await accept(storedGrant.replacingAccount(profile))
} catch let error as AccountAPIError where error.isUnauthorized {
    // ONLY unauthorized errors land here: the token died, rotate it
    let refreshed = try await api.refresh(refreshToken: storedGrant.refreshToken)
    try await accept(refreshed)
} catch {
    // network down, server hiccup: keep the cached session, do nothing drastic
}
```

The `where error.isUnauthorized` clause is a guard on the catch: 401 means "rotate the token," while a timeout means "leave the user signed in." Collapsing those two into one generic catch (the JS reflex) would sign users out every time the train goes through a tunnel.

### The three flavors of try

| Form | On failure | Rust equivalent | When this codebase uses it |
|---|---|---|---|
| `try` | propagates to the caller (which must be `throws` or catch it) | `?` | the default, everywhere |
| `try?` | swallows the error, result becomes nil | `.ok()` | when failure genuinely has no better handling: `try? await store.clear()` |
| `try!` | crashes | `.unwrap()` | never in production paths |

`try?` deserves respect rather than suspicion: in `restore()`, if clearing an already-dead session fails, there is nothing smarter to do, and `try?` documents that decision in one character instead of an empty catch block.

## 1.11 Generics in Sixty Seconds

You have seen generics in every language you know; Swift's look like Rust's:

```swift
func firstAndLast<T>(_ items: [T]) -> (T, T)? {
    guard let first = items.first, let last = items.last else { return nil }
    return (first, last)
}
```

`<T>` declares a placeholder type; the function works for arrays of anything. Constraints use `where` or `: Protocol`:

```swift
func allEqual<T: Equatable>(_ items: [T]) -> Bool { ... }
```

This codebase mostly CONSUMES generics (arrays, optionals, `Task<Void, Never>`, `Result<T, Error>`) rather than defining elaborate ones. When you write app code, that is usually the right balance; generics are a library author's power tool.

## 1.12 Properties: Stored, Computed, Observed, Lazy

Swift properties come in flavors, and the codebase uses all of them deliberately.

**Stored** properties hold a value. **Computed** properties run code on every access:

```swift
// From AccountSession.swift:
var isAuthenticated: Bool { account != nil }        // computed, no stored bool to drift

// From Core/Chain/ContractGateway.swift, VaultState:
var sharePrice: Double { ... }                       // derived from totals on demand
```

The rule of thumb: if it answers a question about current state and takes no arguments, make it a computed property, not a function. `session.isAuthenticated` reads better than `session.isAuthenticated()`.

**private(set)** splits read and write access:

```swift
private(set) var isRestoring = true
```

Anyone can READ `isRestoring`; only `AccountSession` itself can WRITE it. This one keyword is the entire "views render state but never mutate it" discipline, enforced by the compiler instead of a style guide.

**Property observers** run when a stored property changes:

```swift
var cardStyleRaw: String = "ink" {
    didSet { persistSelection() }    // runs after every assignment
}
```

**lazy** delays expensive initialization until first use. You will meet it in bigger codebases more than here; `AppEnvironment` gets the same effect with factory methods (`makeContractGateway()`) that build the heavy web3 stack only when a screen actually needs it, so app boot stays instant.

## 1.13 Memory: ARC, and the One Bug It Cannot Catch

JavaScript and Dart free memory with a garbage collector that runs "sometimes." Rust frees it with ownership rules checked at compile time. Swift uses **ARC, Automatic Reference Counting**: every class object carries a count of how many references point at it; the count hits zero, the object is freed instantly. No GC pauses, no borrow checker. Structs and enums are not even reference-counted; they live and die with their scope.

ARC has exactly one failure mode you must know: the **retain cycle**. If object A strongly references B and B strongly references A, both counts can never reach zero, and both objects leak forever:

```
   A  ── strong ──▶  B
   ▲                 │
   └──── strong ─────┘        neither can ever be freed
```

The classic real-world version is a closure: closures capture references strongly, so an object storing a closure that captures `self` has built the cycle in one line. The fix is a **capture list** making the capture weak:

```swift
service.onEvent = { [weak self] event in
    guard let self else { return }     // weak means self is now optional
    self.handle(event)
}
```

`[weak self]` means: capture self without incrementing its count; if self has been freed, the closure sees nil. The `guard let self` line upgrades it back to a strong reference for the duration of the call, or exits quietly.

Why this codebase almost never needs `[weak self]`: it is mostly structs (no reference counts at all), its closures are short-lived SwiftUI view builders, and its long-lived work uses structured concurrency that ends when views disappear (Part 4). The architecture designed the bug away, which is the best fix. But interviewers ask about retain cycles at every iOS interview ever conducted, so know the diagram.

## 1.14 The Conformance List: Swift's derive Macros

In the Rust guide you learned `#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]`. Swift does the same thing with the list after a type's name, and the compiler synthesizes the implementations:

```swift
struct PaymentRecord: Equatable, Hashable, Sendable { ... }
```

The full translation table:

| Swift conformance | What the compiler writes for you | Rust derive | Why this codebase uses it |
|---|---|---|---|
| `Equatable` | `==` comparing all fields | `PartialEq` | comparing payment records, test assertions |
| `Hashable` | hash of all fields | `Hash` | putting `AppRoute` in a `NavigationStack`, dictionary keys |
| `Codable` | JSON encode AND decode | `Serialize + Deserialize` | keychain persistence, API bodies, order manifests |
| `Identifiable` | requires an `id` property | none | SwiftUI lists need stable identity per row |
| `Sendable` | proof it can cross threads | `Send` | every domain type, so actors can hand them out |
| `CaseIterable` | `.allCases` array on an enum | strum's `EnumIter` | the card face picker iterates all 13 styles |
| `Error` | throwable | `std::error::Error` | every error enum |

`Codable` is the workhorse and deserves its own example, because you will write it weekly. Given:

```swift
struct AuthenticatedAccount: Codable {
    let accountID: Int64
    let providerUserID: String

    private enum CodingKeys: String, CodingKey {
        case accountID = "accountId"          // Swift name = JSON name
        case providerUserID = "providerUserId"
    }
}
```

you get both directions for free:

```swift
let data  = try JSONEncoder().encode(account)                      // struct -> bytes
let back  = try JSONDecoder().decode(AuthenticatedAccount.self, from: data)  // bytes -> struct
```

`CodingKeys` is serde's `#[serde(rename)]`: the backend speaks camelCase JSON (`accountId`), Swift convention wants `accountID`, and the enum maps between them. If the names already match, you delete the enum entirely and `Codable` alone is enough.

The single most important `Codable` trick in this entire project is in `OrderManifest` (Part 8): encoding with sorted keys so the SAME bytes come out every time, because those bytes get hashed and the hash goes on the blockchain. Serialization stops being plumbing and becomes cryptography. Keep that in mind as a preview.

## 1.15 Part 1 Self-Check

Before moving on, you should be able to answer these from memory. If any feels shaky, re-read that section; Parts 3 to 8 assume all of them.

1. Why is `let` used for `AppConfiguration`'s fields, and what bug class does that eliminate?
2. What is the difference between `String` and `String?`, and name the five ways to unwrap the latter.
3. A `PaymentRecord` is a struct and `AccountSession` is a class. Swap them: what concretely goes wrong in each direction?
4. Why can `VerdictReadiness.ready` never have a countdown timestamp attached to it?
5. What does `any ContractGateway` mean, and why do workflows store that instead of `ArcContractGateway`?
6. What does `catch let error as AccountAPIError where error.isUnauthorized` catch, and what falls through to the next catch?
7. Draw the retain cycle diagram and write the capture list that breaks it.

----

# Part 2: Project Structure

## 2.1 The Full Project Tree

Hold this map in your head; every later part references it.

```
mobile/
|
|-- scripts/generate_project.rb     # Generates Recourse.xcodeproj (see Part 12)
|
|-- Recourse/                       # The app target: all production code
|   |
|   |-- App/                        # Composition root and app-level chrome
|   |   |-- RecourseApp.swift       # @main entry point (the whole file is 12 lines)
|   |   |-- AppEnvironment.swift    # Dependency container + BuyerPaymentStore
|   |   |-- RootView.swift          # Decides WHICH world renders: splash, onboarding,
|   |   |                           #   buyer app, or merchant workspace. Deep links too.
|   |   |-- SplashView.swift        # The animated glyph-to-wordmark boot sequence
|   |   |-- AppRouter.swift         # AppRoute enum + NavigationPath
|   |   |-- AppShellView.swift      # Buyer tab shell + merchant counter UI
|   |
|   |-- Core/                       # Reusable machinery. NEVER imports from Features/.
|   |   |-- API/                    # Backend HTTP clients (accounts, evidence, orders)
|   |   |-- Auth/                   # AccountSession, KeychainStore, TestnetLocalSigner,
|   |   |                           #   Face ID authorizer, Google sign-in coordinator
|   |   |-- Chain/                  # Everything that talks to Arc (Part 7)
|   |   |-- Config/                 # AppConfiguration (addresses, URLs, chain id)
|   |   |-- DesignSystem/           # Colors, typography, card faces, glass styles
|   |   |-- Domain/                 # Pure data: PaymentRecord, USDCAmount, ChainHash,
|   |   |                           #   EthereumAddress, BuyerWorkflowError
|   |   |-- Orders/                 # OrderManifest: hash-bound commerce data (Part 8)
|   |   |-- QR/                     # PaymentRequest + decoder for scanned checkouts
|   |
|   |-- Features/                   # One folder per user-facing capability.
|   |   |-- Checkout/Domain/        #   Each has UI files and often a Domain/ folder
|   |   |-- Disputes/Domain/        #   holding a Workflow struct with the logic.
|   |   |-- Verdict/Domain/
|   |   |-- Send/
|   |   |-- Earn/
|   |   |-- Home/  Scan/  Receipts/  Profile/  Onboarding/
|   |
|   |-- Generated/Deployment.swift  # Contract addresses, GENERATED from the repo's
|   |                               #   deployments/arc-testnet.json. Never hand-edited.
|   |-- Resources/
|   |   |-- ABI/*.abi.json          # Contract ABIs bundled into the app binary
|   |   |-- Images.xcassets/        # Asset catalog: icons, card art, launch assets
|   |-- Info.plist                  # URL scheme, launch screen, encryption declaration
|
|-- RecourseTests/                  # XCTest suite: workflows, routing, session, vectors
|-- SWIFT_GUIDE.md                  # You are here
```

Two structural laws keep 11,000 lines navigable:

**Law 1: dependencies point one way.** `Features` may use `Core`; `Core` never knows `Features` exists. A workflow can call the chain gateway; the gateway has no idea screens exist. When you wonder "where should this file go," ask: could two different features use it? Then `Core`. Is it one feature's business? Then that feature's folder.

**Law 2: generated code is generated.** `Generated/Deployment.swift` is produced by codegen from `deployments/arc-testnet.json` at the repo root, the same file the web app and ops scripts read. Contract addresses exist in exactly ONE place. The alternative (an address pasted into Swift, drifting from what is actually deployed) is how testnet demos die on stage.

## 2.2 How Swift Finds Code: Modules, Not Files

Coming from JS, Dart, or Rust, the strangest thing about this codebase: **no file imports any other file in the app.** There is no `import "./AccountSession"`, no `use crate::auth::AccountSession;`, nothing.

Swift compiles a whole **module** (here, the app target `Recourse`) as one unit. Every file in the target automatically sees every other file's `internal` (default visibility) declarations. `HomeView.swift` uses `AccountSession` with zero ceremony because they live in the same module.

`import` statements are only for OTHER modules, meaning frameworks and packages:

```swift
import SwiftUI              // Apple's UI framework
import Foundation           // strings, Data, URL, JSON, dates
import Observation          // the @Observable macro
import CryptoKit            // hashing, keys
@preconcurrency import BigInt   // third-party; the prefix is explained in Part 4
```

So how do you find where something is defined, without imports as a trail? Command-click the name in Xcode (jump to definition), or Cmd-Shift-O (open quickly by name). Muscle memory for both is worth thirty minutes of practice.

The visibility levels, since there are no file walls by default:

| Keyword | Visible to | This codebase uses it for |
|---|---|---|
| `private` | this type + same file | helpers, internal state |
| `private(set)` | read anywhere, write privately | observable state, per 1.12 |
| `fileprivate` | this file | rare |
| (nothing) = `internal` | whole module | the default for everything |
| `public` / `open` | other modules | unused here; matters when you split into packages (Part 21) |

## 2.3 Dependencies: SPM Is Your Cargo.toml

Swift Package Manager (SPM) is Swift's Cargo/npm, and the dependency list is deliberately tiny:

| Package | Why it is here |
|---|---|
| `web3swift` + `Web3Core` + `BigInt` | Ethereum-style RPC, ABI encoding/decoding, keystores, EIP-712 signing, arbitrary-precision integers |

That is the whole third-party list. Everything else is Apple frameworks: SwiftUI (UI), AVFoundation (camera), LocalAuthentication (Face ID), AuthenticationServices (Sign in with Apple), Security (keychain), CryptoKit (hashing). The Qent backend guide made the same argument about crates: every dependency is code you now maintain but did not write. A wallet holding keys should be paranoid about that list. The dependencies live in the project definition generated by `scripts/generate_project.rb`, and Xcode resolves and pins them (the equivalent of `Cargo.lock` is `Package.resolved`).

----

# Part 3: SwiftUI, The UI Framework

You now know the language. SwiftUI is where it starts looking like an app. Take this part slowly too, because SwiftUI's mental model is genuinely different from "call functions to change the screen," and once it clicks, 40 of this codebase's 60 files become readable in an afternoon.

## 3.1 The Mental Model: The UI Is a Function of State

In UIKit (Apple's older framework) and in raw DOM JavaScript, you mutate the screen imperatively: find the label, set its text, hope you remembered every place that needs updating. SwiftUI, like React and Flutter, flips this:

```
        state changes
             |
             v
   body is recomputed        (you DESCRIBE the UI for the current state)
             |
             v
   SwiftUI diffs old vs new  (framework's job, not yours)
             |
             v
   screen updates minimally
```

You never say "update the balance label." You say "the balance text IS the wallet balance," and when the balance changes, the framework re-renders the difference. If you know Flutter, `body` is `build()`. If you know React, `body` is the render function.

## 3.2 Your First View, Dissected

The entire program entry point, from `App/RecourseApp.swift`:

```swift
import SwiftUI

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

Let me break this down piece by piece:

1. `@main` marks the program's entry point, like `fn main()` in Rust. There is exactly one per app.
2. `struct RecourseApp: App` conforms to the `App` protocol. Note: a STRUCT. Views and apps are value types in SwiftUI; the framework creates and destroys these cheap descriptions constantly.
3. `@State private var environment = ...` creates and OWNS the app-wide dependency container. `@State` is explained in the next section; here it means "SwiftUI, keep this alive across re-renders."
4. `var body: some Scene` is the one requirement of `App`: describe the scene. `some Scene` is the opaque type from 1.8: "a specific concrete type, do not make me spell it."
5. `WindowGroup { ... }` is the app's window, and the closure inside is trailing-closure syntax from 1.9 holding the root of the view tree.
6. `.tint(...)` is a **modifier**: a method that wraps the view in a new view with an attribute changed. The app-wide accent color becomes ledger green.

A minimal custom view has the same shape:

```swift
struct BalanceBadge: View {
    let amount: String              // plain input, passed in by the parent

    var body: some View {
        Text("\(amount) USDC")
            .font(.headline)
            .foregroundStyle(RecourseColor.ledger)
    }
}
```

A view is a struct, its inputs are properties, and `body` describes what it looks like RIGHT NOW. SwiftUI may create and throw away this struct sixty times a second; that is fine, it is just a lightweight description, not the pixels themselves.

## 3.3 Modifier Order Matters

Modifiers wrap; each returns a NEW view around the previous one. Therefore order changes meaning:

```swift
Text("Pay")
    .padding()                 // 1: add space around the text
    .background(Color.green)   // 2: paint behind text AND padding

Text("Pay")
    .background(Color.green)   // 1: paint behind the text only
    .padding()                 // 2: add transparent space around the painted box
```

The first is a green pill; the second is a green sliver with empty margin. When a layout looks "almost right," the first suspect is modifier order.

## 3.4 Layout: Three Stacks and a Spacer

Almost every screen in this app is composed from four primitives:

```swift
VStack(spacing: 12) { ... }    // vertical    (Flutter: Column)
HStack(spacing: 8)  { ... }    // horizontal  (Flutter: Row)
ZStack { ... }                 // depth, back to front (Flutter: Stack)
Spacer()                       // flexible emptiness that pushes siblings apart
```

A real composite from `Features/Onboarding/OnboardingWelcomeView.swift`, the "ARC TESTNET" chip:

```swift
HStack(spacing: 8) {
    Image("ArcMark")               // 1. the Arc logo from the asset catalog
        .resizable()               // 2. allow it to scale at all
        .scaledToFit()             // 3. keep its aspect ratio while scaling
        .frame(height: 13)         // 4. constrain to 13 points tall
    Text("ARC TESTNET")
        .font(.caption.weight(.bold))
        .tracking(0.8)             // letter-spacing
}
.foregroundStyle(.white)           // applies to EVERYTHING inside the HStack
.padding(.horizontal, 14)
.frame(height: 36)
.recourseGlassCapsule()            // custom modifier from the design system
```

Notice how modifiers on the HStack cascade to children (`foregroundStyle`), while modifiers on `Image` shape just the image. And notice steps 2 to 4 on the image: `resizable` then `scaledToFit` then `frame` is THE incantation for "put this image here at this size, undistorted." You will type it hundreds of times.

`SplashView.swift` shows `ZStack` doing real work: a white background layer, the glyph layer, and the wordmark layer, stacked in depth so the animation can crossfade between them.

One scar this codebase carries, so you do not earn it yourself: safe areas. `ignoresSafeArea(.top)` combined with a fixed `frame(height:)` silently loses the notch inset, and overlays INHERIT safe-area insets, so adding them manually counts them twice. `OnboardingReadyView` fixes this with `height: proxy.size.height + proxy.safeAreaInsets.top`. When a button floats mysteriously mid-screen, safe-area math is the culprit.

## 3.5 State: Who Owns This Value?

Here is the section to read three times. Every state tool in SwiftUI answers one question: **who owns this piece of state?** Choose by ownership and the tools stop being confusing.

### @State: this view owns it

```swift
struct SplashView: View {
    @State private var wordmarkIn = false        // owned by SplashView, dies with it

    var body: some View {
        ZStack { ... }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).delay(1.0)) {
                    wordmarkIn = true            // mutating state triggers re-render
                }
            }
    }
}
```

Piece by piece: `@State` tells SwiftUI to store this value OUTSIDE the struct (remember, the struct is recreated constantly) and to re-run `body` whenever it changes. Without `@State`, assigning to a property of a struct inside `body` would not even compile. Use it for small, local, throwaway UI state: is a sheet showing, has the animation started, what is in this text field.

React reader: `useState`. Flutter reader: `setState` in a `StatefulWidget`, minus the boilerplate.

### @Binding: a parent owns it, I can edit it

```swift
struct AmountField: View {
    @Binding var amount: String                 // NOT mine; a live pipe to the owner's @State

    var body: some View {
        TextField("0.00", text: $amount)        // edits flow UP to the owner
    }
}

// The parent:
@State private var amount = ""
AmountField(amount: $amount)                    // $ creates the Binding from the @State
```

The `$` prefix is the syntax to remember: `amount` is the value, `$amount` is a read-write reference to it. This is how a child edits a parent's state without owning it, and it is how every `TextField`, `Toggle`, and `Picker` works.

### @Observable: a shared object owns it

For state that outlives any one view (the session, the payment list, the router), the owner is a class marked `@Observable`:

```swift
// From Core/Auth/AccountSession.swift:
@Observable
final class AccountSession {
    private(set) var account: AuthenticatedAccount?
    private(set) var isRestoring = true
    private(set) var errorMessage: String?
    // methods mutate these; views just read them
}
```

The magic contract: any view whose `body` READS `session.isRestoring` is automatically subscribed to changes of `isRestoring`, and ONLY of the properties it actually read. No subscriptions to write, no `notifyListeners()`, no selectors. The `@Observable` macro rewrites the class's property accesses to do the tracking.

Dart reader: this is Provider/Riverpod's job, absorbed into the language. If you read the Qent Flutter chapter, `@Observable` classes are your `Notifier`s, and reading a property in `body` is `ref.watch`.

`@Bindable` is the small bridge you will see once in `RootView`: it lets you make `$router.path` bindings into an `@Observable` object, the way `$` works for `@State`.

### @AppStorage: UserDefaults owns it

```swift
// From App/RootView.swift:
@AppStorage("recourse.hasCompletedOnboarding") private var hasCompletedOnboarding = false
@AppStorage("recourse.appearance") private var appearanceRaw = "dark"
```

Reads and writes go straight to UserDefaults (the tiny key-value store iOS gives every app, the same idea as the SharedPreferences the Flutter guide covered), AND the view re-renders on change. One line replaces load-on-launch, save-on-change, and observe-for-updates. Used for exactly what it should be: small preferences. The theme choice and the onboarding flag are strings and bools here; the SESSION is not, because secrets belong in the keychain (Part 6).

### @Environment: the view tree provides it

```swift
@Environment(\.colorScheme) private var colorScheme   // light or dark, injected by system
```

Values flow DOWN the tree invisibly; any descendant can ask. `HomeView` uses this to gate its dark-mode-only glow effect.

### The decision table

| You need... | Tool | Who owns it |
|---|---|---|
| a toggle, a text field, "is this sheet up" | `@State` | this view |
| child edits parent's value | `@Binding` | the parent |
| session, stores, router, anything shared | `@Observable` class | the object |
| a persisted preference | `@AppStorage` | UserDefaults |
| system values (theme, locale) | `@Environment` | the framework |

## 3.6 Lists and Identity

Rendering collections:

```swift
ForEach(payments) { payment in
    PaymentRow(payment: payment)
}
```

For this to work, `payments` elements must be `Identifiable` (have a stable `id`). Identity is how SwiftUI knows WHICH row changed instead of rebuilding all of them, and it is how animations know what moved where. The classic mistake is `ForEach(items, id: \.self)` on unstable data: identity churns, rows rebuild constantly, scrolling stutters. Payment records here use their onchain payment ID, an identity that can never lie.

For long content use `LazyVStack` inside a `ScrollView` (rows built only when scrolled near), which is what the Home screen's receipt sections do.

## 3.7 Navigation as Data

Navigation in this codebase is not "call a push function and hope." It is state, like everything else:

```swift
// RootView owns the stack:
NavigationStack(path: $router.path) {
    AppShellView(environment: environment)
        .navigationDestination(for: AppRoute.self) { route in
            destination(for: route)          // a switch mapping enum -> view
        }
}

// Anywhere in the app:
environment.router.push(.verdict(paymentID))
```

Walk the flow: `router.path` is a list of `AppRoute` values (the enum from 1.7). Pushing appends a value; the `NavigationStack` sees the path change and presents the matching screen; the back button pops the value off. Because navigation is DATA, a deep link (a scanned QR arriving from the Camera app) navigates by appending the same enum value a tap would. One code path, no special cases.

Sheets follow the same philosophy: `.sheet(isPresented: $showsReceive) { ReceiveSheet(...) }`. A boolean goes true, a sheet appears; it goes false (or the user swipes down), it disappears.

## 3.8 View Lifecycle: .task, .onAppear, .onChange

```swift
// From App/RootView.swift:
.task {
    await environment.accountSession.restore()      // async work tied to view lifetime
}
.onAppear {
    startAnimations()                                // synchronous, on appear
}
.onChange(of: merchantPolicies) { _, newValue in
    reactTo(newValue)                                // observe a value, run a side effect
}
```

`.task` is the one to appreciate: it starts an async job when the view appears and AUTOMATICALLY CANCELS it when the view disappears. The polling loop in `BuyerPaymentStore` runs inside a `.task`; navigate away and the polling just stops, no cleanup code, no leaked timers. In JS you would be wiring an `AbortController` by hand; here the lifetime management is structural. This connects directly to Part 4.

## 3.9 Animation

Two forms cover this whole codebase:

```swift
// Form 1: explicit. Animate the consequences of THIS change.
withAnimation(.easeInOut(duration: 0.45)) {
    isHoldingSplash = false
}

// Form 2: declarative. This view animates whenever `value` changes.
.animation(.easeOut(duration: 1.9).repeatForever(autoreverses: false), value: ripples)
```

The splash sequence is the worked example worth reading in full (`App/SplashView.swift`, 40 lines): ONE state flip (`wordmarkIn = true`) drives four simultaneous animated properties: the glyph's opacity and x-offset, the wordmark's opacity, and a leading-aligned mask whose width animates from 0 to 260 so the word sweeps in from the left. State changes; everything derived from it animates. That is the whole SwiftUI animation philosophy in one file.

`.transition(.opacity)` handles the other case: views being INSERTED or REMOVED (the splash crossfading into the app) rather than properties changing.

----

# Part 4: Swift Concurrency: async/await, Actors, MainActor

This is the hardest part of the guide and the most valuable. This codebase is a clean, modern showcase of Swift concurrency, and the concepts here are what senior iOS interviews actually probe.

## 4.1 async/await: The Familiar Part

You know async/await from JS and Dart. Swift's version reads the same:

```swift
func payment(id: UInt64) async throws -> PaymentRecord    // async AND can fail

let record = try await gateway.payment(id: 13)
```

Note the keyword order at the call site: `try await`, always in that order, marking that this line can fail AND can suspend.

Two mental upgrades from the JS model:

**1. `await` frees the thread.** While the RPC round-trip is in flight, the thread is not blocked; it goes off and runs other work, and this function resumes later, possibly on a different thread. That is why a phone with six cores can run hundreds of concurrent operations.

**2. There are no floating promises.** In JS, calling an async function starts it whether or not you `await` it, and forgotten promises fail silently. In Swift, async functions only run inside a task context, and unhandled results are compiler warnings. Fire-and-forget must be EXPLICIT (`Task { }`, section 4.4).

Running two things at once uses `async let`:

```swift
async let payment = gateway.payment(id: 13)        // starts immediately
async let vault = gateway.vaultState(of: owner)    // starts immediately, in parallel
let (p, v) = try await (payment, vault)            // wait for both
```

## 4.2 The Problem Actors Solve

Before showing the tool, feel the bug it kills. Imagine a plain class shared by two screens:

```swift
final class Counter {
    var value = 0
    func increment() { value += 1 }     // read, add, write: THREE steps
}
```

Two threads call `increment()` at the same moment. Both read `0`, both add 1, both write `1`. One increment is lost. That is a **data race**: no crash, no error, just corrupted state that reproduces once a week. In a wallet, replace "counter" with "nonce" and the corrupted state is a stuck transaction.

JS avoids this by having one thread. Rust prevents it with the borrow checker and `Mutex`. Swift's answer is the **actor**.

## 4.3 Actors: A Class With a Front Door

Change one keyword:

```swift
actor Counter {
    var value = 0
    func increment() { value += 1 }
}
```

An actor is a reference type (like a class) whose state can only be touched by ONE caller at a time. All outside access goes through `await`, and calls queue up like customers at a single counter:

```
   caller A ──┐
   caller B ──┼──▶ [ actor mailbox: one at a time ] ──▶ state
   caller C ──┘
```

```swift
await counter.increment()     // the await is mandatory; you may wait your turn
```

The compiler ENFORCES this. Touch `counter.value` from outside without `await` and the code does not compile. The data race is not found in review or in production; it is impossible to write.

**Where you see this in Recourse, and why each one is an actor:**

```swift
// Core/Chain/ArcContractReader.swift
actor ArcContractReader: ContractReading { ... }
```

The web3 contract objects and the RPC transport inside are not thread-safe, and payment refreshes fire concurrently from several screens. The actor serializes them automatically. No locks, no queues, no `DispatchQueue.sync` archaeology.

```swift
// Core/Auth/TestnetLocalSigner.swift
actor TestnetLocalSigner: BuyerSigner { ... }
```

A signing keystore must NEVER be used by two operations at once. Actor.

```swift
// Core/Auth/AccountSession.swift
actor AccountSessionStore { ... }
```

The keychain read/write path. Same reasoning.

Rust translation: an actor is roughly `Arc<Mutex<T>>` where the compiler writes the locking, checks you never forgot it, and releases across await points correctly. JS translation: each actor is its own tiny single-threaded event loop.

## 4.4 Task: Structured vs Fire-and-Forget

A `Task` is a unit of async work. The distinction that matters is whether its lifetime is TIED to something.

**Structured** (tied to a view, cancelled automatically):

```swift
.task {
    await environment.accountSession.restore()
}
```

**Unstructured** (explicitly detached from the current flow):

```swift
// From AccountSession.restore(), the cold-start fix you watched happen:
try await accept(storedGrant)                                        // awaited: boot needs this
profileRefreshTask = Task { await refreshProfile(from: storedGrant) } // NOT awaited: boot must not wait
```

Read those two lines as a policy decision written in syntax. The keychain read is on the boot path, so it is awaited. The network validation is NOT allowed to block boot (this exact line is why the 15-second frozen splash became instant), so it is wrapped in `Task { }` and runs in the background. And the task is STORED in a property rather than discarded, so tests can `await session.profileRefreshTask?.value` to deterministically wait for the background work before asserting. That one property is the difference between a testable design and a flaky test suite.

Cancellation is cooperative: a cancelled task keeps running until it checks. Long loops in this codebase poll politely:

```swift
while !Task.isCancelled {
    await refresh()
    try? await Task.sleep(for: .seconds(10))     // sleep throws immediately if cancelled
}
```

## 4.5 @MainActor: The UI Thread as a Type

iOS law: UI state must be touched on the main thread. Historically this was enforced by crashes. Swift encodes it in the type system with a special global actor:

```swift
// From App/AppEnvironment.swift:
@MainActor
@Observable
final class AppEnvironment { ... }
```

`@MainActor` on a class means "all of this runs on the main thread." `AppEnvironment`, `AccountSession`, `BuyerPaymentStore`, and every SwiftUI view are main-actor isolated. If background code tries to set `session.isRestoring` directly, that is now a COMPILE error, not a heisenbug. Crossing over is explicit and visible:

```swift
let record = try await reader.payment(id: 13)   // hop TO the reader actor (background)
self.latest = record                             // back ON MainActor automatically after await
```

## 4.6 Sendable: Proof It Can Cross the Border

When a value hops between actors, could it smuggle shared mutable state across the border? `Sendable` is the compile-time proof that it cannot:

```swift
struct PaymentRecord: Hashable, Sendable { ... }        // all-value fields: safe, checkable
protocol ContractReading: Sendable { ... }               // implementations must be safe too
```

Structs of Sendable parts are automatically Sendable. Classes usually are not (shared mutable state is their whole deal), which is exactly why the domain layer here is all structs: actors can hand them out freely with zero copying anxiety.

One loose end from Part 2: `@preconcurrency import BigInt`. That prefix says "this library predates Sendable checking; do not flag its types." It is the pragmatic bridge for older dependencies, and you will type it in any codebase using pre-2022 libraries.

## 4.7 The Concurrency Map of This App

```
              MainActor (UI world)                     Background world
  ┌──────────────────────────────────────┐   ┌────────────────────────────────┐
  │  SwiftUI views                       │   │  actor ArcContractReader       │
  │  AppEnvironment   (@MainActor)       │   │  actor ArcContractWriter       │
  │  AccountSession   (@MainActor)       │◀─▶│  actor TestnetLocalSigner      │
  │  BuyerPaymentStore(@MainActor)       │   │  actor AccountSessionStore     │
  │  AppRouter        (@MainActor)       │   │  URLSession network calls      │
  └──────────────────────────────────────┘   └────────────────────────────────┘
              every crossing is an explicit `await`, and
              everything that crosses is Sendable
```

If you internalize this one diagram, you understand the app's entire threading story, and you can answer the interview question "how do you avoid data races" with something better than "I use DispatchQueue."

----

# Part 5: The App, Layer by Layer

Language: done. UI framework: done. Concurrency: done. Now we walk the actual application the way the Qent guide walked `main.rs`: from the entry point downward, explaining why each layer exists.

## 5.1 Boot: From Tap to First Frame

```
 user taps the icon
      |
      v
 iOS shows the STATIC launch screen        (Info.plist UILaunchScreen: the bare
      |                                     green R on white; no code runs yet)
      v
 @main RecourseApp                          creates AppEnvironment.live()
      |                                     (cheap: no network, no ABI parsing)
      v
 RootView renders                           first frame! static launch fades out
      |                                     destination = .restoring -> SplashView
      |-- .task 1: accountSession.restore() keychain read (milliseconds),
      |                                     background profile refresh spawned
      |-- .task 2: sleep 2.3s               minimum splash hold so the
      |                                     glyph-to-wordmark animation lands
      v
 both tasks done -> workspaceDestination recomputes
      |
      +--> .onboarding    (no session)      white/green welcome flow
      +--> .buyerApp      (buyer session)   dark wallet home
      +--> .merchantWeb   (merchant role)   light merchant workspace
```

The load-bearing decision, worth repeating from Part 4: NOTHING on this path waits on the network. The app renders from cached state and lets the network catch up. Every app that feels instant does this; every app with a ten-second splash does not.

## 5.2 AppEnvironment: Dependency Injection Without a Framework

There is no DI library. There is one class that wires the object graph, with defaults for production and a seam for every test:

```swift
// App/AppEnvironment.swift:
@MainActor
@Observable
final class AppEnvironment {
    let configuration: AppConfiguration
    let router: AppRouter
    let accountSession: AccountSession
    let buyerSigner: any BuyerSigner
    let paymentStore: BuyerPaymentStore

    init(
        configuration: AppConfiguration,
        router: AppRouter = AppRouter(),
        accountSession: AccountSession? = nil,
        buyerSigner: (any BuyerSigner)? = nil,
        paymentStore: BuyerPaymentStore? = nil
    ) {
        self.configuration = configuration
        self.router = router
        self.buyerSigner = buyerSigner ?? TestnetLocalSigner()
        self.paymentStore = paymentStore ?? BuyerPaymentStore(
            configuration: configuration,
            signer: self.buyerSigner
        )
        self.accountSession = accountSession ?? AccountSession(
            api: AccountAPIClient(baseURL: configuration.apiURL)
        )
    }

    static func live() -> AppEnvironment { AppEnvironment(configuration: .live) }
}
```

Read the init slowly; it is the whole DI story:

1. Every dependency is a parameter with a default of `nil`.
2. Each `?? ` fallback constructs the REAL implementation.
3. Production calls `.live()` and thinks about none of this.
4. A test calls `AppEnvironment(configuration: .test, buyerSigner: FakeSigner())` and substitutes exactly the pieces it cares about.

Note also which types the properties are: `any BuyerSigner`, not `TestnetLocalSigner`. Protocols at the boundary (1.8) is what makes the substitution possible at all.

Heavier objects (the web3 gateway, the evidence client) are NOT built in init; factory methods like `makeContractGateway()` build them when a screen first needs one. Boot cost stays flat as the app grows.

## 5.3 RootView and the Workspace Decision

The highest-stakes UI decision in the app is "what do you see when it opens." `RootView` reduces it to a pure function plus a switch:

```swift
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

`WorkspaceRouting.destination` is static, takes five plain values, returns an enum, touches nothing. Because it is pure, `WorkspaceRoutingTests` exercises every combination in microseconds. When you build your own apps, steal exactly this: extract the scary decision into a function of plain values, test the function to death, keep the switch dumb.

RootView also carries two app-wide policies as single lines: the background color per branch, and `preferredColorScheme` (the buyer app follows the user's dark/light preference from `@AppStorage`; onboarding and merchant are pinned light, which is how the "onboarding stays white and green" rule is enforced structurally rather than by memory).

## 5.4 Stores: Server State In, Rendered Out

`BuyerPaymentStore` (in `AppEnvironment.swift`) is the read model for "my payments." Its loop:

1. Ask the signer for the wallet address.
2. Poll the backend indexer for payments belonging to that address.
3. Decode into domain structs, store them in `@Observable` arrays.
4. Home and Receipts screens read those arrays; SwiftUI re-renders on change.

The poll runs in a view's `.task`, so it stops when the screen goes away (4.4). And note the trust model inherited from the protocol: the indexer only ACCELERATES reads; anything that matters is verifiable against the chain itself, which is what the receipt screens do when they recompute verdicts (Part 8).

Writes never pass through the store. Money movement goes through workflows to the chain, and the store simply observes the aftermath at the next poll.

## 5.5 Workflows: One Use Case, One Struct

Each feature's `Domain/` folder holds a struct that owns one use case end to end:

```swift
// Features/Verdict/Domain/VerdictWorkflow.swift:
struct VerdictWorkflow: Sendable {
    private let gateway: any ContractGateway
    private let timeProvider: any UnixTimeProvider

    init(gateway: any ContractGateway, timeProvider: any UnixTimeProvider) {
        self.gateway = gateway
        self.timeProvider = timeProvider
    }

    func inspect(paymentID: UInt64) async throws -> VerdictReadiness {
        let payment = try await gateway.payment(id: paymentID)
        guard payment.status == .disputed || payment.status == .settled else {
            throw BuyerWorkflowError.paymentNotDisputed
        }
        let preview = try await gateway.previewVerdict(paymentID: paymentID)
        // ... decide: awaiting attestation, ready, or settled
    }
}
```

Everything from Part 1 is on display in twelve lines: a struct (value semantics, no lifecycle), `any` protocol dependencies (testable), `guard` for preconditions (readable), a typed throw (precise failure), an enum payload return (illegal states unrepresentable). Views construct a workflow, call one method, and render the returned enum. No business logic in views; no UI in workflows; tests need neither a screen nor a network.

The same shape repeats: `CheckoutWorkflow` (verify order, approve USDC, pay), `DisputeWorkflow` (file claim with evidence), `SendWorkflow` (plain transfer), each a struct with gateway plus whatever narrow dependencies it needs.

----

# Part 6: Auth and Security

## 6.1 Two Keys, Two Jobs

The most important conceptual split in the app, and the one to internalize before touching any wallet code:

| | Account | Wallet |
|---|---|---|
| Answers | "who are you to the backend" | "who signs transactions" |
| Created by | Apple / Google sign-in | generated on this device, first use |
| Lives in | `AccountSession` + keychain session grant | `TestnetLocalSigner` + keychain keystore |
| On a new phone | same account after sign-in | a DIFFERENT wallet |
| Leaves the device | tokens go to the backend | never, ever |

Same device, two accounts: both see the same wallet. Same account, two devices: two different wallets. Identity and money are deliberately decoupled; the demo you saw on the simulator (signed out, empty wallet) versus the physical phone (signed in, funded) is this table in action.

## 6.2 KeychainStore: Wrapping a C API Once

The keychain is iOS's encrypted credential store, surviving reinstalls, guarded by the Secure Enclave. Its API is C from another era: `SecItemAdd`, `SecItemCopyMatching`, `SecItemDelete`, driven by `CFDictionary` queries.

`Core/Auth/KeychainStore.swift` wraps that hostility ONCE behind a civilized async protocol:

```swift
protocol SecureDataStore {
    func save(_ data: Data, account: String) async throws
    func load(account: String) async throws -> Data?
    func delete(account: String) async throws
}
```

Everything above depends on the protocol; tests substitute an in-memory dictionary (`AccountSessionMemoryStore`). The pattern to copy into every codebase you ever touch: ugly platform APIs get one small adapter conforming to one small protocol, and the ugliness never spreads.

## 6.3 The Signer

```swift
// Core/Auth/TestnetLocalSigner.swift:
actor TestnetLocalSigner: BuyerSigner {
    func address() async throws -> EthereumAddress
    func sign(_ transaction: UnsignedTransaction) async throws -> Data
    func signEIP712(_ typedData: Data) async throws -> Data
    private func loadOrCreateKeystore() async throws -> EthereumKeystoreV3
}
```

First use generates an `EthereumKeystoreV3` (an encrypted Ethereum key file) with a random password; both are stored in the keychain. Every signature after that is: load keystore, decrypt with the stored password, sign, done, all serialized by the actor so two payments can never race the keystore.

`signEIP712` is the quietly clever one. EIP-712 is Ethereum's standard for signing STRUCTURED data (typed fields, not opaque bytes). The app uses it to authorize evidence uploads: the backend challenges, the phone signs a typed message proving "I am the onchain buyer of payment N," and the backend verifies the signature against the chain. Password-free authentication where the wallet key IS the identity.

`TransactionAuthorizer` adds the human gate: LocalAuthentication (Face ID) must succeed before the signer is even asked. Biometric prompt, then signature, in that order, every time money moves.

## 6.4 Session Restore, Step by Step

You watched this function get rebuilt during the session; now read it as a finished pattern, because you will reimplement it in every app you ever ship:

```swift
func restore() async {
    guard isRestoring else { return }              // run once
    defer { isRestoring = false }                  // ALL exits flip the flag (1: defer!)

    do {
        guard let storedGrant = try await store.load() else { return }   // 2: cache read
        let credentialState = try? await credentialChecker.credentialState(
            for: storedGrant.account.providerUserID
        )
        if credentialState == .revoked || credentialState == .notFound {
            try await store.clear()                // 3: Apple says dead: sign out
            return
        }
        try await accept(storedGrant)              // 4: TRUST CACHE: render signed-in NOW
        profileRefreshTask = Task {                // 5: VERIFY ASYNC: network catches up
            await refreshProfile(from: storedGrant)
        }
    } catch {
        grant = nil
        account = nil
        try? await store.clear()
    }
}
```

The five numbered beats:

1. `defer` guarantees `isRestoring` flips on EVERY exit path: success, early return, throw. One line, no forgotten branch, splash always ends.
2. Keychain load: local, milliseconds, allowed on the boot path.
3. The one early sign-out: Apple explicitly revoked the credential.
4. The cached grant is accepted immediately. The UI renders the signed-in world.
5. Validation (`/me`, token rotation on 401, sign-out on dead refresh token) happens in a background task that boot never waits for, stored in a property for tests.

Name the pattern and keep it: **trust cache, verify async.** Synchronous session validation on the boot path is the single most common cause of slow app launches in the wild.

----

# Part 7: Talking to Arc: the Chain Layer

## 7.1 The Stack, Top to Bottom

```
  Feature workflow            "pay this request" / "read payment 13"
        |            depends on: any ContractGateway
        v
  ArcContractGateway          thin composer: routes reads and writes
        |                     
        +-- actor ArcContractReader     eth_call reads, ABI decode -> domain structs
        +-- actor ArcContractWriter     build tx, Face ID sign, send, poll receipt
        |            depends on: any ArcRPCTransport
        v
  ArcRPCTransport             JSON-RPC 2.0 over URLSession
        |
        v
  Arc testnet RPC node        chain id 5042002
```

Addresses come from `AppConfiguration` (which comes from `Generated/Deployment.swift`, which comes from the deploy artifacts: one source of truth, Part 2). ABIs are JSON files bundled in `Resources/ABI/`, loaded through an enum so a missing file is a named error, not a crash:

```swift
enum ContractABI: String {
    case erc20 = "ERC20.abi"
    case escrow = "RecourseEscrow.abi"
    case policyRegistry = "PolicyRegistry.abi"
    case settlementVault = "SettlementVault.abi"
}
```

## 7.2 Anatomy of a Read

What actually happens when the home screen shows your USDC balance:

1. The store asks the reader: `balance(of: address)`.
2. The reader looks up `balanceOf` in the ERC-20 ABI and encodes the call data (function selector + padded address, the EVM's binary calling convention; web3swift does the byte-packing).
3. The transport POSTs a JSON-RPC `eth_call` to the node.
4. The node executes the view function and returns hex-encoded bytes.
5. The reader decodes through the ABI, range-checks, and wraps the result in a domain type (`USDCAmount`).

Every step that can fail has a named case in `ContractReadError` (1.10): `missingABI`, `rpc(code:message:)`, `malformedResult(method:)`, `unknownPaymentStatus`. When a read breaks, the error TELLS you which layer lied. Compare with the alternative you see in most hobby wallet code: `try! result as! BigUInt` and a crash log.

## 7.3 Anatomy of a Write

A payment is a small state machine, and `EarnView`'s deposit sheet shows it to the user honestly:

```
 build UnsignedTransaction (nonce, gas, calldata)
      |
      v
 Face ID prompt  ──denied──▶ stop, nothing signed
      |
      v
 signer.sign(tx)             (actor-serialized, key never leaves device)
      |
      v
 eth_sendRawTransaction  ──▶ tx hash immediately
      |
      v
 poll receipt until mined ──▶ ChainReceipt with an Outcome enum
```

For the vault deposit, TWO writes chain: `approve` (let the vault pull USDC) then `deposit`, each with its own receipt await, each surfaced as a stage string in the UI ("Approving...", "Depositing..."). Users forgive slow chains; they do not forgive silent ones.

## 7.4 Money Is Integers. Always.

Worth its own heading because it is the most transferable rule in the whole guide. `USDCAmount` stores base units (`5_200_000` = $5.20, six decimals), arithmetic happens on integers, and formatting to "5.20" happens only at the display edge. `BigUInt` handles chain-scale numbers; `UInt64` handles IDs and timestamps. `Double` appears exactly nowhere near value. The Qent backend does the same with kobo; Part 20 does the same with lamports. Three ecosystems, one rule: **floats never touch money.**

----

# Part 8: Determinism: Manifests, Hashes, Verdicts

This part is the soul of the product, and it is where "serialization" stops being plumbing and becomes cryptography. Read it after Part 1's Codable section.

## 8.1 The Idea in One Sentence

If two parties can both compute a hash of the same bytes, neither has to trust the other's copy of the data: they compare hashes.

## 8.2 The Order Manifest, Worked Example

When a merchant creates a product, the app builds an exact JSON document:

```json
{"amountBaseUnits":"5200000","description":"Fresh catch","imageHash":"0x9c1a...","title":"Fish"}
```

and hashes those EXACT bytes with keccak256 (Ethereum's standard hash). That 32-byte hash IS the `orderRef` the escrow contract stores when the buyer pays. Now look at the encoding code and spot the detail that makes it work:

```swift
// Core/Orders/OrderManifest.swift:
func encodedForPublishing() throws -> (bytes: Data, orderReference: ChainHash) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let bytes = try encoder.encode(self)
    return (bytes, bytes.keccak256Hash)
}
```

`.sortedKeys` is the entire trick. JSON key order is normally arbitrary; `{"a":1,"b":2}` and `{"b":2,"a":1}` mean the same thing but hash DIFFERENTLY. Sorting keys makes the encoding canonical: same manifest, same bytes, same hash, in Swift, in TypeScript on the web, and in Rust on the backend. A shared golden fixture (one manifest whose hash all three languages assert in their test suites) pins them together forever; if any implementation drifts by a single byte, a test goes red in that language.

## 8.3 Verification on the Phone

When the buyer's phone fetches an order to display, it does not trust the backend:

```swift
guard bytes.keccak256Hash.value.lowercased() == orderReference.value.lowercased() else {
    // hash mismatch: tampered or corrupted; refuse to even display it
}
```

Walk the consequence chain: the backend stores and serves the manifest bytes, but the HASH the phone compares against came from the chain. If the backend altered a price, the recomputed hash would not match the onchain `orderRef`, and the phone rejects the order before the user ever sees it. The backend is thereby demoted from "trusted authority" to "byte courier." This is the deepest design idea in the codebase: **make the server unable to lie, instead of promising it will not.**

## 8.4 The Verdict, Recomputed

The same philosophy applies to dispute outcomes. The verdict is a pure function (policy, claim, evidence, attestation, timing) implemented three times: Solidity (canonical, moves the funds), TypeScript (the public verifier in your browser), and Swift (right here, on the phone). `VerdictWorkflow` reads the inputs from the chain, recomputes the verdict locally, and the receipt screen shows both hashes side by side: the one the chain computed and the one your phone computed, matching. Fourteen shared golden vectors are asserted by forge, vitest, and XCTest in the same commit whenever the engine changes.

The pitch of the whole product is literal in the code: do not trust the verdict, recompute it.

----

# Part 9: QR Codes, the Camera, and Universal Links

## 9.1 Three Doors, One Checkout

A checkout can reach the app three ways, and all three funnel into the SAME decoder and the SAME route:

```
 1. In-app scanner            AVFoundation camera reads the QR string
 2. iPhone Camera app         QR encodes https://<web>/pay?request=...
                              iOS recognizes the universal link, opens the app,
                              delivers it via onContinueUserActivity
 3. recourse:// scheme        the web /pay page's fallback if the app
                              did not intercept; arrives via onOpenURL
        |
        v
   PaymentRequestDecoder      validate chain id, addresses, amount
        |
        v
   router.push(.checkout(request))
```

```swift
// App/RootView.swift, both doors wired in two modifiers:
.onOpenURL { url in openIncomingCheckout(url) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    if let url = activity.webpageURL { openIncomingCheckout(url) }
}
```

Because navigation is data (3.7), the deep-link path IS the tap path: decode, push the enum, done. The decoder rejects wrong-chain and malformed payloads with human-readable errors before anything renders; a QR is untrusted input exactly like a network response.

One product subtlety encoded here: a checkout QR is a PRICE TAG, not a ticket. Every scan that completes payment creates an independent escrowed payment with its own protection window. Two buyers scanning the same product QR is the normal case, not a conflict.

## 9.2 Generating QR Codes

The receive screen renders the wallet address as a QR with CoreImage:

```swift
let filter = CIFilter.qrCodeGenerator()
filter.message = Data(address.utf8)
// scale up with nearest-neighbor so squares stay crisp, not blurry
```

And one deliberate design-system exception: the QR tile stays WHITE even in dark mode, because scanners want contrast, not aesthetics.

----

# Part 10: The Design System

## 10.1 Two Laws, Enforced by Structure

The project has two visual laws, and both are enforced by code rather than memory:

1. **Onboarding is white and green, forever.** Onboarding screens use the static light palette (`ink`, `canvas`, `ledger`), and RootView pins their color scheme to light. No system dark mode, no user toggle, can touch them.
2. **In-app dark is flat black.** Content sits directly on the `night` background: no cards floating on cards, no gray containers. Chips and dividers exist; boxes-in-boxes do not.

## 10.2 Adaptive Tokens: One Name, Two Colors

```swift
// Core/DesignSystem/RecourseColor.swift:
static let night     = adaptive(light: (1.0, 1.0, 1.0),    dark: (0.027, 0.035, 0.03))
static let nightText = adaptive(light: (0.07, 0.09, 0.08), dark: (0.93, 0.95, 0.93))

private static func adaptive(light: (Double, Double, Double),
                             dark: (Double, Double, Double)) -> Color {
    Color(UIColor { trait in
        trait.userInterfaceStyle == .dark ? UIColor(...) : UIColor(...)
    })
}
```

Piece by piece: `UIColor { trait in ... }` is a UIKit color that RESOLVES ITSELF differently per appearance, wrapped in a SwiftUI `Color`. A view says `RecourseColor.nightText` once and is correct in both themes with zero conditional code. The entire dark theme migration of this app was a mechanical sweep (`ink` to `nightText`, `canvas` to `night`) precisely because every color already flowed through this one file. Theme systems die when hex values scatter through views; this one lives because the palette has a single home.

The user's dark/light choice is one `@AppStorage` string applied at ONE point (`preferredColorScheme` in RootView). Setting, application, and tokens: three small pieces, cleanly separated.

## 10.3 The Card Faces: an Enum as a Design System

`WalletCardStyle` is a `CaseIterable` enum of thirteen faces. Each case knows its background image name and one derived fact, `prefersDarkText`, from which text, chip, and border colors all follow. The picker grid is `ForEach(WalletCardStyle.allCases)`; the persisted selection is the enum's raw value in `@AppStorage`. Adding face fourteen is: add a case, drop the art in the asset catalog. Every screen updates itself. When variation is finite and knowable, an enum IS the design system.

## 10.4 Asset Catalog Tricks Used Here

- **Appearance variants:** `ArcMark.imageset` contains a navy SVG (for light) and a white SVG (for dark); `Image("ArcMark")` picks automatically. Forcing one variant is `.environment(\.colorScheme, .dark)`, used on the onboarding chip that sits on photo glass.
- **Vector data:** `"preserves-vector-representation": true` keeps SVGs sharp at any render size.
- **The launch screen** is not code: `Info.plist` declares `UILaunchScreen` with an image and background color from the catalog. iOS caches a rendered snapshot aggressively, which is why launch-screen changes sometimes need a delete-and-reinstall (or reboot) to appear, as you saw firsthand.

----

# Part 11: Testing

## 11.1 XCTest Anatomy

XCTest is Apple's built-in framework. A test class extends `XCTestCase`; every method starting with `test` is a test:

```swift
import XCTest
@testable import Recourse        // import the app module, including internal symbols

final class USDCAmountTests: XCTestCase {
    func testFormatsBaseUnits() {
        let amount = USDCAmount(baseUnits: 5_200_000)
        XCTAssertEqual(amount.formatted, "5.20")
    }
}
```

`@testable import` is the one piece of magic: it lets the test target see the app's `internal` declarations without making everything `public`.

The assertion vocabulary:

| Assertion | Checks |
|---|---|
| `XCTAssertEqual(a, b)` | `a == b` (needs Equatable, from 1.14) |
| `XCTAssertTrue(x)` / `XCTAssertFalse(x)` | booleans |
| `XCTAssertNil(x)` / `XCTAssertNotNil(x)` | optionals |
| `XCTAssertThrowsError(try f())` | the call throws |
| `XCTUnwrap(x)` | unwraps an optional or fails the test cleanly |

## 11.2 Async Tests and Actor Isolation

Tests can be `async` and can be `@MainActor`, matching the code under test:

```swift
// From RecourseTests/AccountSessionTests.swift:
@MainActor
final class AccountSessionTests: XCTestCase {
    func testRestoresAnAuthorizedBackendSession() async throws {
        let sessionStore = AccountSessionStore(secureStore: AccountSessionMemoryStore())
        try await sessionStore.save(grant(account: expected))

        let session = AccountSession(
            store: sessionStore,
            credentialChecker: FixedAppleCredentialChecker(state: .authorized),
            api: AccountAPIMock(profile: expected, refreshedGrant: storedGrant)
        )

        await session.restore()

        XCTAssertEqual(session.account, expected)
        XCTAssertFalse(session.isRestoring)
    }
}
```

Read the arrange step and count the fakes: an in-memory keychain, a fixed Apple credential checker, a canned API. Every one exists because the real dependency hides behind a protocol (1.8, 6.2). No network, no keychain entitlements, no Apple servers: the test runs in milliseconds and cannot flake.

And the detail you watched get built: when `restore()` gained a background refresh task, the token-rotation test gained ONE line before its assertions:

```swift
await session.profileRefreshTask?.value    // wait for the background work, deterministically
```

Exposing in-flight tasks as properties is the standard trick for testing fire-and-forget work. File it away; you will need it within a month of writing production Swift.

## 11.3 What This Suite Chooses to Test

Look at what `RecourseTests/` covers and, just as instructively, what it skips:

- **Workflows** (checkout, dispute, verdict, send) against `FakeContractGateway`: the business rules.
- **WorkspaceRouting**: every combination of the five boot inputs (5.3).
- **AccountSession**: restore, rotation, revocation.
- **Golden vectors**: the Swift verdict engine against the same fixtures forge and vitest assert.
- **Manifest hashing**: the cross-language fixture (8.2).

No pixel tests, no scrolling simulators. The suite tests DECISIONS, not appearances, which is why 58 tests run in seconds and why they caught real regressions during this project instead of breaking on every UI tweak.

Run it yourself:

```bash
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

----

# Part 12: Xcode, the Generated Project, and Shipping

## 12.1 Why the .xcodeproj Is Generated

`Recourse.xcodeproj` is not hand-maintained; `scripts/generate_project.rb` produces it (using the `xcodeproj` Ruby gem). The pbxproj format inside is a merge-conflict machine that has ruined more pair-programming afternoons than any other file format in iOS history. Generating it makes the project reproducible, reviewable (build settings live in readable Ruby), and conflict-free.

The one workflow rule this imposes: **after adding, deleting, or renaming a Swift file, regenerate:**

```bash
cd mobile && ruby scripts/generate_project.rb && open Recourse.xcodeproj
```

If Xcode was open during regeneration, close and reopen the project. Half the "my new file does not compile" confusion is a stale open project.

## 12.2 Info.plist: the Five Entries That Matter Here

| Key | What it does |
|---|---|
| `CFBundleURLTypes` | registers the `recourse://` scheme (Part 9, door 3) |
| `UILaunchScreen` | the static splash: LaunchMark image + LaunchBackground color |
| `ITSAppUsesNonExemptEncryption = false` | export-compliance declaration; stops App Store Connect asking on every build |
| camera / Face ID usage strings | the permission-prompt texts, set as `INFOPLIST_KEY_*` in the generator |
| associated domains (entitlement) | lets `https://<web>/pay` links open the app (door 2) |

## 12.3 Command-Line Builds and the Simulator

The commands used throughout this very project, worth keeping on a card:

```bash
# list simulators and their UDIDs
xcrun simctl list devices

# build for a specific simulator
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -destination 'id=<UDID>' build

# install, launch, screenshot
xcrun simctl install <UDID> path/to/Recourse.app
xcrun simctl launch  <UDID> com.recourse.buyer
xcrun simctl io      <UDID> screenshot shot.png
```

Two field-tested debugging facts: DerivedData (Xcode's build cache) occasionally corrupts, and the fix is pointing `-derivedDataPath` somewhere fresh; and the launch-screen snapshot cache survives reinstalls until iOS feels like refreshing it (12.2 of your memory, 10.4 of this guide).

## 12.4 Shipping Checklist

Archive (Product > Archive) requires: a bundle ID matching App Store Connect, the encryption declaration above, and, the one that bit this project, **no `#Preview` referencing DEBUG-only helpers.** Previews compile in Release too; wrap them:

```swift
#if DEBUG
#Preview { SplashView() }
#endif
```

TestFlight is the low-ceremony distribution path while the app is testnet-only, and Apple's guideline 3.1.5 (crypto features and organizational accounts) belongs in your review notes before a reviewer discovers it themselves.

----

# Part 13: Common Patterns Reference

The cheat sheet to keep open while writing Swift. Everything here appears in this codebase.

## 13.1 guard: the Early Exit

```swift
guard payment.status == .disputed || payment.status == .settled else {
    throw BuyerWorkflowError.paymentNotDisputed
}
```

State the requirement, exit on failure, continue unindented. Chains of guards read as checklists.

## 13.2 defer: Cleanup That Cannot Be Forgotten

```swift
guard isRestoring else { return }
defer { isRestoring = false }        // runs on EVERY exit: return, throw, fall-through
```

## 13.3 The Optional Toolbox, One Screen

```swift
if let x = maybe { ... }                 // unwrap for a block
guard let x = maybe else { return }      // unwrap or bail
let x = maybe ?? fallback                // default
let y = maybe?.property                  // chain, result optional
let z = definitely!                      // crash if nil; constants only
```

## 13.4 Collection Transforms Instead of Loops

```swift
let names = accounts.compactMap { $0.email }.filter { !$0.isEmpty }.sorted()
let total = amounts.reduce(0) { $0 + $1.baseUnits }
let match = payments.first(where: { $0.id == target })
```

## 13.5 Computed Properties Over Functions

```swift
var isAuthenticated: Bool { account != nil }     // question about state: property
func refresh() async { ... }                     // does work: function
```

## 13.6 How to Add a New Screen (this codebase's recipe)

1. Add a case to `AppRoute` (with payload if the screen needs input).
2. The compiler now errors in `RootView.destination(for:)`: map the case to your view.
3. Create `Features/<Name>/<Name>View.swift`; if there is logic, `Features/<Name>/Domain/<Name>Workflow.swift` taking `any ContractGateway` or whatever protocols it needs.
4. Navigate with `environment.router.push(.yourCase(...))`.
5. `ruby scripts/generate_project.rb`, reopen Xcode, build.
6. Test the workflow with the fakes in `DomainTestDoubles.swift`.

## 13.7 Common Compile Errors, Decoded

| Error | What it means | Fix |
|---|---|---|
| "Value of optional type 'X?' must be unwrapped" | you used an optional as a plain value | `if let` / `guard let` / `??` (1.5) |
| "Cannot assign to property: 'self' is immutable" | mutating a struct's property from a non-mutating context, often inside a View | in views: route it through `@State`; in structs: mark the method `mutating` |
| "Cannot assign to value: 'x' is a 'let' constant" | assigning to a constant | make it `var`, or reconsider: should it change? |
| "Expression is 'async' but is not marked with 'await'" | calling async code without await | add `try await`, and make the caller `async` |
| "Sending 'x' risks causing data races" | a non-Sendable value crossing actors | make the type a struct / conform to `Sendable` (4.6) |
| "Call to main actor-isolated property in a synchronous nonisolated context" | background code touching UI state | hop with `await MainActor.run { }` or mark the caller `@MainActor` |
| "Type 'X' does not conform to protocol 'View'" | `body` is missing or returns inconsistent types | check `body`; wrap branches in `Group` if needed |
| "Generic parameter 'T' could not be inferred" | usually a closure's type is ambiguous | annotate one type explicitly and rebuild |

## 13.8 Exercises Against This Codebase

Do these in order; each is a rung.

1. **Read a file cold.** Open `Features/Send/Domain/SendWorkflow.swift`. For every line, name the Part 1 concept it uses. If you hit one you cannot name, that section gets a re-read.
2. **Add a computed property.** Give `VaultState` a `utilization: Double` (outstanding over totalAssets, guarding division by zero). Write the two-line test first.
3. **Add a card face.** Follow 10.3: new `WalletCardStyle` case, asset, and watch the picker grow a cell with no other edits.
4. **Break the router on purpose.** Add `case history` to `AppRoute` and follow the compile errors until the app builds with a placeholder screen. Count how many places the compiler walked you to; that is exhaustiveness working for you.
5. **Write a fake.** Build `FailingRPCTransport: ArcRPCTransport` that always throws `.rpc(code: -32000, message: "out of gas")`, hand it to `ArcContractReader` in a test, and assert the workflow surfaces a readable error, not a crash.
6. **Trace a deep link.** Start at `.onOpenURL` in RootView and follow a `/pay` URL all the way to the checkout screen, writing down every type it passes through. This exercise builds the codebase map faster than any amount of reading.

## 13.9 The Five Ideas Worth Stealing From This App

1. Protocols at every boundary, fakes in tests (`ContractGateway`, `BuyerSigner`, `SecureDataStore`).
2. Pure functions for high-stakes decisions (`WorkspaceRouting.destination`).
3. Actors around anything not thread-safe (RPC, keystore, keychain).
4. Trust cache, verify async: never block first render on a network call.
5. One source of truth per fact: colors through `RecourseColor`, addresses through `Generated/Deployment.swift`, money in integer base units.

----
# Part 14: UIKit and Interop (What Big Apps Are Really Made Of)

Recourse is pure SwiftUI. TikTok, Instagram, and Snapchat are not: they are UIKit apps with SwiftUI islands, because their feeds and cameras predate SwiftUI and demand frame-level control. To work on an app used by billions you must be bilingual.

## 14.1 The Two Bridges

```swift
// SwiftUI inside UIKit: how legacy apps adopt SwiftUI screen by screen
let vc = UIHostingController(rootView: SettingsView())
navigationController.pushViewController(vc, animated: true)

// UIKit inside SwiftUI: how SwiftUI apps get UIKit power
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        return view
    }
    func updateUIView(_ view: PreviewView, context: Context) {}
}
```

`UIViewRepresentable` (and `UIViewControllerRepresentable` for whole screens like image pickers) is the escape hatch you will use for cameras, maps, rich text, and anything SwiftUI does not expose yet. Recourse already crosses this bridge quietly: `RecourseColor.adaptive` wraps a trait-reading `UIColor`, and the scanner sits on AVFoundation.

## 14.2 UIKit Essentials You Must Recognize

- **UIViewController lifecycle**: `viewDidLoad`, `viewWillAppear`, `viewDidLayoutSubviews`, `deinit`. Interview staple, debugging staple.
- **UICollectionView + compositional layout + diffable data source**: the engine of every infinite feed on the App Store. SwiftUI's `LazyVStack` is fine to millions of users; at TikTok scale teams still reach for `UICollectionView` because it gives cell prefetching, precise reuse, and per-cell display callbacks (start video when 60 percent visible, stop when scrolled off).
- **CALayer and Core Animation**: every view is backed by a layer; animations you see are layer properties interpolated off the main thread. `CADisplayLink` gives you a per-frame callback (scrubbers, waveform meters).
- **Auto Layout**: constraint math (`NSLayoutConstraint`, anchors). You will read it more than write it.

The rule of thumb in hybrid codebases: **new leaf screens in SwiftUI, high-performance containers in UIKit**, bridged both directions.

---

# Part 15: Networking at Scale

`URLSession` is the entire networking story; libraries like Alamofire are conveniences on top, and big shops mostly use raw URLSession behind their own protocol layer (exactly like `ArcRPCTransport` and `AccountAPIClient` here).

## 15.1 URLSession Beyond the Basics

```swift
// A tuned session, not the shared default:
var config = URLSessionConfiguration.default
config.waitsForConnectivity = true               // queue instead of fail when offline
config.timeoutIntervalForRequest = 15
config.requestCachePolicy = .useProtocolCachePolicy
config.urlCache = URLCache(memoryCapacity: 50_000_000, diskCapacity: 500_000_000)
let session = URLSession(configuration: config)

let (data, response) = try await session.data(for: request)
```

Know the three session types: `.default`, `.ephemeral` (no disk traces; good for wallets), and **background sessions** (`URLSessionConfiguration.background`), which keep uploads and downloads running after your app is suspended. TikTok uploads your video through a background session.

## 15.2 Retry With Backoff (The Snippet Every Backend Client Needs)

```swift
func withRetry<T>(attempts: Int = 3, _ op: () async throws -> T) async throws -> T {
    var delay: Double = 0.5
    for attempt in 1...attempts {
        do { return try await op() }
        catch where attempt < attempts {
            try await Task.sleep(for: .seconds(delay + .random(in: 0...0.3)))
            delay *= 2                            // exponential backoff + jitter
        }
    }
    fatalError("unreachable")
}
```

Retry only idempotent operations. A payment POST is not one; a balance read is.

## 15.3 Streaming and Real Time

```swift
// WebSockets, first party:
let ws = URLSession.shared.webSocketTask(with: url)
ws.resume()
let message = try await ws.receive()

// Server-sent bytes (chat streams, live counters):
for try await line in url.lines { handle(line) }
```

At scale you will also meet **Protocol Buffers and gRPC** (`swift-protobuf`, `grpc-swift`): binary schemas replacing JSON for chat, feeds, and telemetry. Codable skills transfer directly; the schema just lives in `.proto` files.

## 15.4 The Image Pipeline

Feeds die by image decoding, not downloading. The professional move is downsampling with ImageIO so a 12 MP photo becomes a cell-sized bitmap without ever inflating fully in memory:

```swift
func downsampled(at url: URL, to size: CGSize, scale: CGFloat) -> UIImage? {
    let opts = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
    let thumbOpts = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * scale,
        kCGImageSourceCreateThumbnailWithTransform: true
    ] as CFDictionary
    return CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts).map(UIImage.init)
}
```

Libraries doing this for you: Nuke, Kingfisher, SDWebImage. Learn one, but understand the trick above; it is an interview favorite and the reason feed memory graphs stay flat.

---

# Part 16: Media: Camera, Video, and the TikTok Feed

This is the Snapchat/TikTok engineering core. It is all AVFoundation.

## 16.1 The Capture Pipeline

```
AVCaptureDevice (camera/mic hardware)
   -> AVCaptureDeviceInput
      -> AVCaptureSession                  # the hub; start/stop on a background queue
         -> AVCaptureVideoPreviewLayer     # what the user sees
         -> AVCaptureVideoDataOutput       # raw frames (CMSampleBuffer) for filters/ML
         -> AVCapturePhotoOutput           # stills
         -> AVCaptureMovieFileOutput       # simple video recording
```

```swift
let session = AVCaptureSession()
session.sessionPreset = .high
let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)!
session.addInput(try AVCaptureDeviceInput(device: device))

let output = AVCaptureVideoDataOutput()
output.setSampleBufferDelegate(self, queue: videoQueue)   // frames arrive here
session.addOutput(output)
session.startRunning()   // never on the main thread
```

Snapchat lenses and TikTok filters are that delegate callback feeding each `CMSampleBuffer` through **Core Image** or **Metal** shaders and rendering the result. The vocabulary to learn next: `CVPixelBuffer`, `CIFilter`, `MTKView`, and Vision (face landmarks) for AR-ish effects.

## 16.2 Playback: Why TikTok Feels Instant

```swift
let player = AVQueuePlayer()
let item = AVPlayerItem(url: hlsURL)          // HLS: .m3u8 adaptive streams
item.preferredForwardBufferDuration = 2       // buffer just enough
player.replaceCurrentItem(with: item)
player.play()
```

The feed pattern behind every short-video app:

1. Videos ship as **HLS** (adaptive bitrate; the server offers multiple qualities, the player switches seamlessly).
2. A small pool of `AVPlayer` instances is **reused**, never one per cell.
3. The next two or three items are **preloaded** (create the `AVPlayerItem`, let it buffer, do not play).
4. Cell visibility callbacks decide play/pause; audio session category is configured once (`AVAudioSession.sharedInstance().setCategory(.playback)`).

## 16.3 Editing and Export

`AVMutableComposition` stitches clips, `AVVideoComposition` applies transforms and filters per frame, `AVAssetExportSession` renders the final MP4. Add `PHPickerViewController` (modern photo picker, no permission prompt needed) and `PhotoKit` for library writes, and you can build the whole "record, trim, filter, post" loop.

---

# Part 17: Persistence and Offline

Recourse persists almost nothing locally on purpose (chain and backend are the truth). Consumer apps at scale are the opposite: the feed must open instantly from disk on a subway.

## 17.1 The Ladder

| Layer | Use for | In Recourse |
|---|---|---|
| `UserDefaults` / `@AppStorage` | Tiny preferences | theme, card face, onboarding flags |
| Keychain | Secrets | session grant, wallet keystore |
| Files (`FileManager`, caches dir) | Blobs, media | evidence images before upload |
| `URLCache` / `NSCache` | Transparent HTTP and object caching | image thumbnails |
| SQLite via **GRDB**, or **SwiftData/Core Data** | Structured, queryable, observable data | not needed yet |

## 17.2 SwiftData in Ten Lines

```swift
@Model
final class CachedPost {
    @Attribute(.unique) var id: String
    var author: String
    var likedAt: Date?
    init(id: String, author: String) { self.id = id; self.author = author }
}

let container = try ModelContainer(for: CachedPost.self)
let context = ModelContext(container)
context.insert(CachedPost(id: "1", author: "dapper"))
try context.save()
let liked = try context.fetch(FetchDescriptor<CachedPost>(predicate: #Predicate { $0.likedAt != nil }))
```

Core Data is the older engine underneath the same ideas (managed objects, contexts, migrations); big codebases still run on it, so recognize `NSManagedObject` when you see it. Teams that want SQL control (Jupiter-style token lists, DEX caches) often pick GRDB instead.

## 17.3 Offline-First in One Paragraph

The pattern: render from the local store always; fetch, diff, and write back on a schedule or push; queue user mutations in a persistent outbox and replay them with retry when connectivity returns; resolve conflicts server-side with versions or timestamps. That is nine tenths of "the app works on the subway", and it is architecture, not any specific database.

---

# Part 18: Performance for a Billion Users

At billion-user scale, performance is a feature team. The vocabulary:

## 18.1 Launch Time

Launch = **pre-main** (dyld loading your binary and frameworks) + **main to first frame**. You already lived this: Recourse's boot was slow because session restore blocked first render; the fix (render cached state, verify async) is the universal one. Other levers: fewer dynamic frameworks (static linking), lazy singletons, defer everything not needed for the first frame. Apple's target: interactive in under 400 ms.

## 18.2 The Instruments You Will Actually Use

| Instrument | Question it answers |
|---|---|
| Time Profiler | Where is CPU going? Whose stack is hot? |
| Allocations / Leaks | What is using memory? What never deallocates? |
| Hangs | What blocked the main thread more than 250 ms? |
| Core Animation / Animation Hitches | Why did scrolling drop frames? |
| Network | What requests fired, when, how big? |
| os_signpost | Your own custom spans on the timeline |

```swift
import OSLog
let log = OSLog(subsystem: "app.recourse", category: "checkout")
os_signpost(.begin, log: log, name: "verify-manifest")
// ... work ...
os_signpost(.end, log: log, name: "verify-manifest")
```

In production you cannot attach Instruments, so **MetricKit** delivers daily payloads of real-user launch times, hang rates, memory, and crash diagnostics. Big apps graph these per release and block rollouts on regressions.

## 18.3 Scroll Performance Rules

1. Stable identity in `ForEach` (`Identifiable` with real ids; never `id: \.self` on unstable data).
2. `LazyVStack`/`List` for long content; plain `VStack` builds everything eagerly.
3. Decode and downsample images off the main thread (Part 15.4); cells should receive ready bitmaps.
4. Cheap `body`: no sorting, no formatting, no hashing inside `body`; precompute in the store.
5. Measure, do not guess: one Animation Hitches run tells you more than a week of intuition.

## 18.4 Memory

ARC (automatic reference counting) frees objects when the last strong reference dies; there is no GC pause, but there are **retain cycles**: two objects strongly holding each other live forever. The classic is a closure capturing `self` that `self` stores. Break it with `[weak self]`. Instruments' Memory Graph shows cycles visually. Value types and actors (this codebase's diet) mostly design the problem away.

---

# Part 19: Push, Background Work, and System Surfaces

## 19.1 Push Notifications (APNs)

The flow: app requests permission, iOS hands you a device token, you ship it to your backend, your backend posts to Apple's APNs with that token, iOS displays the notification. Two special powers matter at scale:

- **Silent pushes** (`content-available: 1`) wake your app in the background for a few seconds to prefetch, so the app is fresh when opened.
- **Notification Service Extensions**: a tiny separate process that can rewrite a push before display. This is how Snapchat decrypts end-to-end content and how apps attach media to pushes.

## 19.2 Background Execution

iOS suspends apps aggressively. Sanctioned lanes:

```swift
// Periodic refresh, scheduled and budgeted by the system:
BGTaskScheduler.shared.register(forTaskWithIdentifier: "app.recourse.refresh", using: nil) { task in
    Task {
        await store.refresh()
        task.setTaskCompleted(success: true)
    }
}
```

Plus background URLSessions (Part 15.1) for transfers, and push-triggered wakeups. There is no "run a thread forever"; design around wakeups and budgets.

## 19.3 Surfaces Beyond the App

- **Widgets** (WidgetKit): timeline-based mini views; a natural "protection status" surface.
- **Live Activities**: lock-screen live state (a dispute countdown would be perfect).
- **App Intents / Shortcuts / Siri**: expose actions to the system.
- **Share and Action Extensions**: appear in other apps' share sheets.

Each runs in its own process with its own (tiny) memory budget; they share code with the app through local SPM packages (Part 21).

---

# Part 20: Swift for Blockchain Beyond EVM: Solana and Jupiter

Recourse taught you the EVM shape: secp256k1 keys, ABI encoding, nonces, `eth_call`. Solana (Jupiter's world) is a different machine. Here is the translation table:

| Concept | EVM (this app) | Solana |
|---|---|---|
| Signature curve | secp256k1 | **ed25519** |
| Derivation path | m/44'/60'/... | m/44'/501'/... |
| State model | Contract storage | **Accounts** owned by programs; you pass every account a tx touches |
| Transaction | to + calldata + nonce | Message of **instructions** + **recent blockhash** (expires in about a minute) |
| Token balance | ERC-20 `balanceOf(you)` | An **Associated Token Account** per (wallet, mint) |
| Fees | Gas auction | Flat lamports + **priority fee** via compute budget instruction |
| Read API | `eth_call` | JSON-RPC `getAccountInfo`, `getBalance` + **WebSocket subscriptions** |

## 20.1 ed25519 Signing Is in Apple's CryptoKit

You do not even need a crypto library for the core operation:

```swift
import CryptoKit

let key = Curve25519.Signing.PrivateKey()                  // a Solana-compatible keypair
let publicKey = key.publicKey.rawRepresentation            // 32 bytes = the address bytes
let signature = try key.signature(for: message)            // 64-byte ed25519 signature
```

Base58-encode the public key and you have a Solana address. Libraries like **SolanaSwift** add the rest: transaction message building, SPL token helpers, RPC clients, and BIP-39 mnemonic derivation.

## 20.2 A Jupiter Swap From Swift, Conceptually

```swift
// 1. Quote: GET https://quote-api.jup.ag/v6/quote?inputMint=...&outputMint=...&amount=...
// 2. Swap:  POST /v6/swap with the quote + your pubkey -> returns a serialized transaction
// 3. Deserialize, sign with your ed25519 key, send via RPC sendTransaction
// 4. Poll getSignatureStatuses until confirmed (or resubmit with a fresh blockhash)
```

Notice what carries over from Recourse verbatim: the actor-guarded signer, the transport protocol, typed RPC errors, receipt polling, integer-only amounts (lamports and token decimals instead of USDC's 6), and simulate-before-send (`simulateTransaction` is Solana's version of the `simulateContract` guard used in this repo's ops scripts).

## 20.3 Wallet Engineering Realities

- **Secure Enclave only speaks P-256.** Neither secp256k1 nor ed25519 keys can live inside it. Real wallets store raw keys in the **keychain with an access-control flag requiring biometrics** (what this app does), or split the key with **MPC** (Coinbase-style), or use **passkey-backed** custody. Know all three; interviews at wallet companies ask.
- **Deep-link wallet flows**: on iOS, dapp-to-wallet communication is universal links + callback URLs (Solana's Mobile Wallet Adapter standard is Android-first; iOS wallets embed the dapp browser instead).
- **Never let money touch Double, ever, on any chain.** Lamports are UInt64; token amounts are integer + decimals, exactly like `USDCAmount`.

---

# Part 21: Architecture at Scale

A billion-user app is hundreds of engineers in one repo. The survival tools:

## 21.1 Modularization With Local SPM Packages

The app becomes a thin shell importing feature packages:

```swift
// Packages/DesignSystem/Package.swift
let package = Package(
    name: "DesignSystem",
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    targets: [.target(name: "DesignSystem"), .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])]
)
```

Benefits: enforced boundaries (a package physically cannot import what it does not declare), parallel builds, per-team ownership, and extensions/widgets reusing the same modules. Recourse's `Core/` vs `Features/` split is this idea one step before it becomes packages.

## 21.2 Feature Flags and Experiments

Every big app wraps new code in flags fetched from a remote config service, rolled out by percentage, and measured as A/B experiments before 100 percent launch. The Swift shape is an injected protocol (`FeatureFlags`) with a remote-backed live implementation and a dictionary-backed test one; the exact pattern `AppEnvironment` already uses for everything else.

## 21.3 Patterns You Will Meet

- **MVVM**: view model objects own screen state; this codebase's stores + workflows are a close cousin.
- **TCA (The Composable Architecture)**: Redux-like reducers and effects; popular in serious SwiftUI shops; its testability obsession will feel familiar after Part 11.
- **Coordinator pattern**: navigation extracted into objects; `AppRouter` is a lightweight one.

## 21.4 The Table Stakes Trio

- **Localization**: String Catalogs (`.xcstrings`); never concatenate translated fragments; test with pseudolocalization and right-to-left.
- **Accessibility**: VoiceOver labels (`.accessibilityLabel`, already on the Arc toolbar mark here), Dynamic Type (prefer `.font(.body)` over fixed sizes on text-heavy screens), contrast, hit targets of at least 44 points.
- **Privacy**: purpose strings, App Privacy questionnaire, and privacy manifests (`PrivacyInfo.xcprivacy`) declaring required-reason API usage; third-party SDKs must ship their own.

---

# Part 22: Release Engineering

## 22.1 Code Signing, Demystified

Three artifacts: a **certificate** (proves you), a **provisioning profile** (binds certificate + app ID + devices/distribution), and **entitlements** (capabilities baked into the binary: push, associated domains for universal links, keychain groups). Ninety percent of signing pain is a mismatch among the three. `xcodebuild -allowProvisioningUpdates` and Xcode's automatic signing handle the common path.

## 22.2 CI/CD

```bash
# The archive pipeline in two commands:
xcodebuild -project Recourse.xcodeproj -scheme Recourse \
  -configuration Release -archivePath build/Recourse.xcarchive archive
xcodebuild -exportArchive -archivePath build/Recourse.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/
```

**fastlane** wraps this (plus screenshots, TestFlight upload, dSYM upload) into lanes run by GitHub Actions or Xcode Cloud on every merge. Big apps cut a release branch weekly ("release train"), ship to TestFlight, then use **phased release** (1, 2, 5, 10... percent over seven days) with the ability to halt on a crash spike.

## 22.3 Observability in Production

- **Crashes**: upload dSYMs so stack traces symbolicate; watch crash-free-user rate per release (Crashlytics, Sentry, or Apple's organizer).
- **Metrics**: MetricKit dashboards (Part 18) for launch, hangs, memory.
- **App size**: app thinning ships per-device slices; asset catalogs enable it; teams budget size like memory.
- **Crypto app review notes**: Apple's guideline 3.1.5 requires crypto exchange/wallet features to come from appropriately registered organizations; testnet-only demos should say so loudly in review notes, exactly as this project's App Store submission does.

---

# Part 23: The 80 Percent Roadmap

How the parts map to the jobs you named:

| Target | Must be fluent in | This guide's parts |
|---|---|---|
| Any senior iOS role | Fundamentals, SwiftUI, concurrency, testing, UIKit interop, performance | 1-5, 11, 14, 18 |
| TikTok / Snapchat (media + feed) | Capture pipeline, HLS playback, image pipeline, UICollectionView, hitch hunting, push | 14, 15, 16, 18, 19 |
| Jupiter / wallet engineering | Key management, signing, RPC transports, integer money, simulation, deep links | 6, 7, 8, 20 |
| Billion-user infrastructure | Modularization, flags/experiments, offline, release trains, observability, a11y/l10n | 17, 19, 21, 22 |

A sane learning order from where you stand now:

1. **Concurrency until it is reflexive** (Part 4). Every hard bug and every senior interview lands here.
2. **Build one UIKit thing**: an infinite `UICollectionView` feed with diffable data source and image downsampling. This single project covers Parts 14, 15, and 18.
3. **Build one media thing**: camera preview with a Core Image filter, record, export, play back with a reused AVPlayer. That is the TikTok take-home.
4. **Port the signer**: write an ed25519 `SolanaSigner` actor conforming to a protocol like `BuyerSigner`, do a devnet transfer, then a Jupiter devnet quote. You will be shocked how much of `Core/Chain` you can copy.
5. **Instrument something real**: profile this very app's cold start and scroll with Instruments; find one hitch; fix it.
6. Then flags, packages, and fastlane the day a project needs a second contributor.

The remaining 20 percent (Metal shaders, on-device ML with Core ML, ARKit, watchOS, custom allocator-level tuning) is specialist territory; you hire for it or grow into it. Everything above is the load-bearing 80.

---

Built alongside the Recourse protocol for the Build on Arc hackathon. The backend has a Rust guide of the same spirit; read the two together and you have the whole system.
