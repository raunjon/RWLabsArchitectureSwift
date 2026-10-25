# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`RWLabsArchitecture` is a Swift Package providing a reactive, state-driven MVVM architecture for SwiftUI apps:

- State/Action/Output ViewModels (`BaseViewModel`)
- View protocols that bind a view to its model (`ComponentView`, built on `BaseView`)
- A `Connection` / `CaseConnection` system for wiring parent ↔ child ViewModels (direct, enum-case, and optional child states)
- App-level flows (login / onboarding / main, tab bars) expressed as ordinary ViewModels. There is no separate flow system.
- A dependency injection container plus property wrappers

It is consumed as a local package (`.package(path: "../RWLabsArchitecture")`) by app targets; it is not an app itself. Platforms in `Package.swift`: iOS 17, macOS 10.15 (swift-tools 6.2).

Dependencies: `swift-case-paths` (tracking `main`), used for `@CasePathable` destination enums, and `swift-syntax` (`509.0.0..<700.0.0`), used by the macro target.

## Default building blocks

**New feature code uses `ComponentModel` and `ComponentView`.** Write every screen as a `@Component final class X: ComponentModel<X>` subclass plus a `ComponentView`, and write all examples and docs that way too. Treat `BaseViewModel` and `BaseView` as the underlying base types, not things to use directly.

- `ComponentModel<Model: ComponentTypes>` (`Base/ComponentModel.swift`) subclasses `BaseViewModel<Model.State, Model.Action, Model.Output>`: it takes **the model itself** and reads its nested types through `ComponentTypes`. Otherwise it's empty, so everything listed for `BaseViewModel` below applies to it. Without `@Component`, a model writes `extension X: ComponentTypes {}` itself, plus `typealias Output = EmptyOutput` (and so on) for any type it doesn't declare.
- Mark every `ComponentModel` subclass **`@Component`** (`Base/Component.swift`) and leave out the boilerplate it writes:
  - `struct State` gets `@ComponentState`, which adds `isLoading`, `error` and `destination: Destination?` (whichever are missing) plus `ViewModelState`.
  - `enum Destination` gets `@CasePathable` and `ViewModelDestination`; `enum Action` and `enum Output` get their conformances.
  - A missing `Destination` / `Action` / `Output` becomes a `typealias` to `EmptyDestination` / `EmptyAction` / `EmptyOutput`. The class header may still name it (`X.Output`).
  - A nested `class Connections: ConnectionsBase` (a generated `typealias ConnectionsBase = ViewModelConnections<Model>`; a macro can't write the superclass itself) gets `setupConnections()` touching every `lazy var` (`@ComponentConnections`), and the model gets `lazy var connections = Connections(parent: self)` and `HasConnections`.
  - The class gets `ComponentTypes`, which `ComponentModel<X>` needs.
  - Anything declared by hand wins. A macro can't write a superclass, which is why the header names the model and `Connections` inherits from the generated `ConnectionsBase`.
  - The module `@_exported import`s `CasePaths`, so `@CasePathable` resolves without the app importing it.
- A `ComponentView` declares its model as `@ObservedObject var model` when a parent or connection owns it (the usual case for child screens), or `@StateObject var model` when the view owns it. `BaseView` only requires `var model: Model { get }`, so either works, and so does a plain `let`.
- `ComponentView` doesn't add a `NavigationStack`. The view that **hosts** a navigation root wraps it: the tab bar does `NavigationStack { HomeView(model: …) }`, and the root flow switch does the same for a flow that pushes. Don't make one view conform to both `ComponentView` and `RoutableView`. It compiles, but both provide a default `body`, so which one you get isn't obvious.

## Building

The code uses UIKit (`UIWindow` in the custom-alert overlay) and iOS 16/17 SwiftUI APIs, so it only compiles for iOS. A plain `swift build` builds for the macOS host and fails. Build for the iOS Simulator instead:

```bash
xcodebuild -scheme RWLabsArchitecture -destination 'generic/platform=iOS Simulator' -skipMacroValidation build
```

The package has a macro target, `Sources/RWLabsArchitectureMacros`, which provides `@Component` (plus the `@ComponentState`/`@ComponentDestination`/`@ComponentAction`/`@ComponentOutput`/`@ComponentConnections` it applies), `@DeepLinkable` and `@DeepLink`, and depends on `swift-syntax`. `-skipMacroValidation` stands in for Xcode's one-time "Trust & Enable" prompt. Macro behaviour is covered by functional tests (`ComponentMacroTests`, `DeepLinkMacroTests`) in the iOS test target. There are no `SwiftSyntaxMacrosTestSupport` expansion tests, because those have to run on macOS and the main target doesn't build for macOS.

`RWLabsExamples.xcodeproj` (in the sibling `RWLabsExamples` folder) does not use this checkout. It references its own separate copy at `RWLabsExamples/Libraries/RWLabsArchitecture`, so edits made here don't show up there until that copy is synced.

There is a small test target, `Tests/RWLabsArchitectureTests` (XCTest). Run it on an iOS Simulator:

```bash
xcodebuild test -scheme RWLabsArchitecture -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -skipMacroValidation
```

It currently covers `CaseConnection`'s two-way state sync, `DependencyContainer`, the `@Injected` wrappers, the service lifecycle (`AppCoordinator` + `startServices`/`stopServices`), the logger, validation, the `Extensions/` helpers, `Route`, deep links, the presentation helpers, and the storage and state wrappers. Tests that create a `BaseViewModel` must register an `ErrorService` in `setUp`.

## Source layout

Everything lives under `Sources/RWLabsArchitecture/Architecture/`.

### Base/

- **`BaseViewModel<State, Action, Output>`** (`BaseViewModel.swift`) — the `@MainActor open class` underneath `ComponentModel`. It conforms to `ViewModel` (which includes `StateComponent`).
  - `@Published var state`, `id: UUID` (equality and hashing use only `id`), `required init(initialState:)`.
  - `send(_:)` must be overridden (the default calls `fatalError`). `onAppear()` is an open no-op.
  - Outputs: `sendOutput(_:)`, `outputs` (backed by `outputSubject`), `onOutput { }` (sinks into `cancellables`, returns `Self`), `store(_:)`. Connections subscribe to `outputs` with their own handler.
  - Loading and errors: `startLoading()`, `stopLoading()`, `updateLoading(to:)`, and `handleError(_:)`. `handleError` is `open`. It sets `state.error` **and forwards to the injected `ErrorService`**.
  - `perform(_ operation:, then:)` runs async work in a main-actor `Task` with `isLoading` on, passes the result to the optional `then`, and sends thrown errors to `handleError` (but ignores `CancellationError`). It returns the `Task` (`@discardableResult`) so callers can cancel it.
  - `binding(\.keyPath)` builds a SwiftUI `Binding` into `state`. It skips writes when the new value is `Equatable` and unchanged.
  - `destination` (get/set) is a plain pass-through to `state.destination`, so the two are interchangeable. `dismiss()` sets it to `nil`.
  - `updateState { }` comes from the `StateComponent` default in `ViewModelProtocol.swift`.
  - Also defines `EmptyState` (a struct) and `EmptyDestination` / `EmptyAction` / `EmptyOutput` (enums with no cases, so a model using them can't navigate, receive an action or emit), `ViewModelState.hasError` / `clearError()`. `ComponentModel` lives in `ComponentModel.swift` (see above); it's the place for anything every feature ViewModel should share.
- **`ErrorService`** (protocol, in `Core/Service.swift`) — `func handleError(_ error: Error)`. `BaseViewModel` declares `@Injected var errorService: ErrorService`, which resolves eagerly. **By design, every host app must provide its own `ErrorService`** and register it in `DependencyContainer.shared` before creating any ViewModel; `AppCoordinator` intentionally doesn't register a default. `AppCoordinator.configure()` stops with a clear message if it's missing; otherwise a ViewModel's init would crash. Tests need to register one too.
- **`BaseView`** (`BaseView.swift`) — a `View` with `associatedtype Model: ViewModel`, `var model: Model { get }`, and `@ViewBuilder var content`. The default `body` is `content.onAppear { model.onAppear() }`. If the view also conforms to `Tappable`, `body` adds a full-rect `contentShape` and `.onTapGesture { onTap() }`.
- **`CustomAlert.swift`** — `customAlert(isPresented:dismissOnBackgroundTap:content:)` and `customAlert(item:dismissOnBackgroundTap:destination:)`. The alert is hosted in its own `UIWindow` above the app (made key, VoiceOver-modal), over a dimmed background, and animates in and out the same way whether it's dismissed by a background tap or by clearing the binding in code. Things to know:
  - It doesn't inherit the presenting view's environment, so pass data through the model.
  - `@Environment(\.dismiss)` does nothing inside it; clear the binding to close it.
  - An alert whose binding is already set when the view appears is shown.
  - If the presenting view disappears, the alert closes and the binding is reset.

### Core/

- **`ViewModelProtocol.swift`** — `ViewModelState` (`associatedtype Destination: ViewModelDestination` and required `isLoading`, `error`, and `destination: Destination?`; **not** `Equatable`/`Hashable`, so states can hold anything), `ViewModelAction`, `ViewModelOutput`, and `ViewModel` (`StateComponent & Identifiable & Equatable & Hashable where State: ViewModelState`, with `state`, `send`, `outputs`, `onAppear`, `onOutput`, `init(initialState:)`). `StateComponent` is `@dynamicMemberLookup`: `model.foo` reads or writes `model.state.foo`, and it provides the `updateState { }` default.
- **`ComponentView.swift`** (in `Base/`) — view protocols layered on `BaseView`, and destination presentation:
  - `ComponentView` — **the view protocol to use.** Its `body` is `BaseView`'s (`content.onAppear { model.onAppear() }`), and it adds `button(_ action:label:)`, which renders `label` and sends the action on tap.
  - `View.onOutput(of: model) { output in … }` — lets a view react to its own model's outputs (a wrapper around `onReceive(model.outputs)`). Parents normally get a child's outputs through its connection instead.
  - `RoutableView` — `body` wraps `content` in a `NavigationStack`. Not used in the default pattern; the host wraps navigation roots in `NavigationStack` instead.
  - `View.showDestination(_ dest: Binding<D?>, destination:)` where `D: RouteDestinationPresentable`. It always attaches `.navigationDestination(item:)` (`.push`), `.fullScreenCover(item:)` (`.fullScreen`), `.customAlert(item:)` (`.customAlert`), and `.sheet(item:)` (everything else). Each gets a binding filtered to its style, so view identity stays stable. It works with a `CaseConnection.bindingModel` (the child ViewModel must conform to `RouteDestinationPresentable`) or with the destination enum via `model.binding(\.destination)`.
- **`AppCoordinator`** — a `@MainActor` singleton (`AppCoordinator.shared`, an `ObservableObject`):
  - **It registers nothing.** The app registers every dependency, including the required `ErrorService`, in `onConfigure`.
  - `configure()` runs `onConfigure?()`, stops with a clear `precondition` message if no `ErrorService` is registered, calls `DependencyContainer.shared.startServices()`, and sets `isConfigured = true`.
  - `configureIfNeeded()` skips if already configured. `teardown()` calls `stopServices()` and resets `isConfigured`, which is `public private(set)`.
  - It has nothing to do with navigation. The old `flowCoordinator`, `configureFlow()`, `onSetupInitialFlow`, and `initialFlow` were removed together with the flow layer.
- **`Service.swift`** — `Service` (`start()` / `stop()`, both defaulting to no-ops; singletons are started and stopped by `AppCoordinator` through the container) and `ErrorService`.

### Services/

Ready-made service protocols and implementations. Apps register the ones they use; nothing is registered by default.

- **`Validation.swift`** — `ValidationService` / `DefaultValidationService` / `ValidationRule` / `ValidationResult`.
  - `validate(_:rules:)` takes `String?`, and `nil` counts as empty.
  - Rules: `.required`, `.minLength`, `.maxLength`, `.email`, `.phone`, `.minAge(Int, dateFormat:)`, and `.custom(_, errorMessage:)`.
  - Only `.required` checks emptiness. `.email`, `.phone` and `.minAge` pass an empty value, so optional fields can be left blank.
  - `.minAge` parses with a fixed `en_US_POSIX` locale and Gregorian calendar.
  - Error messages are English strings, not localized.
- **`Analytics.swift`** — `AnalyticsService` and `ConsoleAnalyticsService` (prints every call; formerly `MockAnalyticsService`).
- **`Logger.swift`** — `LoggerService`, `LogLevel` (with an emoji `display`), `ConsoleLogger`, and `Log`.
  - `LoggerService` has **one** requirement, `log(_:level:error:file:function:line:)`. `debug`, `info`, `warning`, `error(_:error:)`, `success`, `network`, `data` and `ui` are extension methods with `#fileID`/`#function`/`#line` defaults, so `logger.info("…")` works through the protocol.
  - `ConsoleLogger` prints one line per message: a detailed one in debug builds, level plus message in release.
  - `Log.d/i/w/e/s/data/network/ui` look up the registered `LoggerService` on every call, work from any thread, and silently drop messages if no logger is registered.

### Navigation/

- **`Destination.swift`** (formerly `NavigationCore.swift`) — `ViewModelDestination` (`Hashable & Identifiable`; `id: String` defaults to the enum case name via `Mirror`, e.g. `"detail"` for `.detail(state)`, and `==`/`hash` use it), `RouteDestinationPresentable` (adds `presentationStyle`), and `PresentationStyle` (`push`, `modal`, `fullScreen`, `customAlert`, `alert`). `AnyDestination`, `NavigationCommand`, `NavigationState`, `metadata`, and the `.replace`/`.popToRoot` styles were removed.
- **`Presentation.swift`** — `View.present(connection) { … }` (a sheet via `bindingModel`), `View.push(connection, enableBackButton:) { … }` (`navigationDestination` via `bindingModel`), `presentAsBinding(item:)` (a sheet for a `VM?` binding), and `customBackButton(enable:)`, a placeholder that returns the view unchanged. `present` and `push` also accept `Binding<CaseConnection>` (`$model.connections.x`). They're `View` extensions, so they chain after other modifiers. Dismissing or popping clears the parent's destination. These replaced ThirtyPlusPanel's `ModalPresentation.swift` helpers; `PresentAsSheetContainer` and `toBool()` were dropped. `Binding.isEqual(to:)` selection helpers moved to `Binding+Extensions.swift`.
- **`Route.swift`** — deep-link parsing: `Route(url:)` (for custom schemes the host is the first path segment, so `myapp://product/123` and `https://example.com/product/123` both give `/product/123`), `matches(pattern:) -> [String: String]?` with `:param` placeholders, `isMatch(_:)`, and `url(scheme:host:)` (standard `myapp://…` form, sorted query items). `FeatureRouter` was removed.
- **`DeepLink.swift`** — opens any screen from a link: `model.openDeepLink(route) -> Bool` reads the path as one screen name per level.
  - A `Destination` enum gets `DeepLinkable` from the **`@DeepLinkable` macro**. Every case's name is its URL segment, and its payload is built with `State()`. `@DeepLink("name", params: ["query": "property"], skip:)` on a case renames it, copies query items into state properties (via `DeepLinkStep.assign(_:to:in:)`, which converts `String`/`Int`/`Double`/`Bool`/`UUID`/`LosslessStringConvertible` and their optionals), or leaves it out.
  - Or write `init?(_ step: DeepLinkStep)` by hand, mapping URL names (`step.name`) and parameters (`step["id"]`, shared query items) to cases. Its model adopts `HasConnections` (in `ViewModelConnections.swift`, now `@MainActor` with `ConnectionsType: AnyObject`) so the walker can reach the child.
  - Models that don't navigate through `destination` (tab bars) adopt `DeepLinkStepHandler.openDeepLinkStep(_:) -> (any ViewModel)?`.
  - The walker sets `state.destination`, then finds the active `CaseConnection` by reflecting over `connections` and calls its internal `deepLinkChild()`, which syncs immediately rather than on the next main-queue turn. Lazy connections must be touched in `setupConnections()` to be found.
  - It stops at the first unrecognised segment and logs a warning with `Log.w`. The root ViewModel decides whether a link can open now, or stores it (e.g. `pendingLink`) until after login. See `Documentation/Flows.md`.

### Navigation/Connections/

- **`ViewModelConnections<Parent: ViewModel>`** (`ViewModelConnections.swift`, together with the `Connectable` and `HasConnections` protocols) — the base class for a ViewModel's `Connections` object. It used to be called `BaseConnections`, and lived in a file of that name.
  - It keeps a `weak var parent`.
  - `required init(parent:)` calls `setupConnections()` (an open no-op) and then hands the parent to every evaluated `AnyConnection` property, found with `Mirror`.
- **`Connection<To: ViewModel>`** (`Connection.swift`), with `init(outputHandler:)` or `init()`:
  - `.connect(from: parent, to: \State.childState) -> To` — for a **non-optional** `To.State` stored on the parent's state. It returns the bare child ViewModel. A private `DirectLink`, owned by the child (via `objc_setAssociatedObject`), holds parent and child **weakly**, delivers outputs, and syncs state **both ways**, using the same echo flags and pending-edit guard as `CaseConnection`.
  - `.connect(state: \.destination, case: \.someCase, parent: parent) -> CaseConnection<From, To, Case>` — for a child whose state is the payload of one case of a `@CasePathable` destination enum.
  - Also `model`, `bindingModel`, `clear()`, and dynamic member lookup into the child.
- **`CaseConnection<From, To, Case>`** — observes the parent's `objectWillChange`, handling each change on the next main-queue turn. The two-way sync uses flags rather than state equality to stop parent ↔ child echo loops, and doesn't push parent state into the child while a child edit is still waiting to sync (covered by the tests):
  - When the case matches, it creates the child as `To(initialState: payload)` (or reuses the cached one), sets its state, and syncs child state changes back into the enum case.
  - When `destination` becomes `nil` or moves to a different case, it deactivates and drops its cached child. Deactivation only clears the parent's `destination` if that destination is still this connection's case.
  - `model` also syncs eagerly when you read it.
  - `bindingModel` (a computed `Binding<To?>`, no longer implicitly unwrapped) clears the parent's `destination` when it's set to `nil`, for example when the user swipes a sheet down or pops back.
- **Optional child states:** `.connect(state: \.filter, parent: parent)` takes a `WritableKeyPath<From.State, To.State?>` and returns `CaseConnection<From, To, To.State?>`. The child exists while the value is non-`nil`, and it has the same sync, `bindingModel` and `present`/`push` support as a case connection. `CaseConnection` reads and writes its payload through closures, so one class serves both enum cases and plain optionals; its `Case` parameter has no constraint. `OptionalConnection`, which stored a child ViewModel in state, was removed.
- **`Async`** (`Extensions/Async.swift`) — `Async.main { }`, `Async.background { }`, `Async.after(_:) { }`.

### DependencyInjection/ and PropertyWrappers/

- `DependencyContainer.shared` — the only dependency system. It's thread-safe (`@unchecked Sendable`, guarded by an `NSRecursiveLock` so a factory can resolve other dependencies).
  - Registration: `register(T.self) { … }` (new instance per resolve), `registerSingleton(T.self, instance:)` (one existing instance), and `registerLazySingleton(T.self) { … }` (built on first resolve, then reused).
  - Resolution: `resolve` (crashes if missing), `resolveOptional`, and `isRegistered` (checks without resolving). `clear()` removes everything.
  - Service lifecycle: `startServices()` calls `start()` on every singleton that conforms to `Service`, in registration order, and is idempotent. `stopServices()` stops them in reverse order. A lazy singleton created after services have started is started on creation. Factory registrations are never started. An instance registered under several types starts once.
  - Types are keyed by `ObjectIdentifier`, so types that share a name don't collide. Register a protocol as the protocol type (`ErrorService.self`) and resolve it the same way.
  - The SwiftUI-style `DependencyValues` / `DependencyKey` / `@Dependency` were removed (nothing used them).
- Wrappers in `Injected.swift`, all reading `DependencyContainer.shared` (there's no custom-container parameter):
  - `@Injected` resolves when the owner is created and crashes if the type is unregistered.
  - `@LazyInjected` resolves on first access and caches. Its getter mutates the wrapper, so it works on class properties (ViewModels) but **not** in a SwiftUI `View` struct. It delays the *lookup*; `registerLazySingleton` delays *creation*.
  - `@OptionalInjected` is `nil` when the type is unregistered.
  - All three have setters, so tests can swap in fakes (`model.api = MockAPIClient()`).
- `Storage.swift` — persisted values in `UserDefaults.app`:
  - `UserDefaults.appSuiteName: String?`: set it once at startup; `nil` means `.standard`. **`.standard` is per app/extension**, so to share between targets (widgets, extensions, a second app) use an App Group id that starts with `group.`, with that group enabled in every target's App Groups capability. `UserDefaults.app` is cached.
  - `UserDefaults.migrate(fromSuite:)` copies an old suite's values in (existing values win) and clears the old suite. The old library always used a suite named `""` (the overridable `suite` couldn't actually be overridden), so apps moving to `appSuiteName` should run `UserDefaults.app.migrate(fromSuite: "")` once.
  - `@Preference(key, default:)` holds property-list values only (`String`, `Int`, `Double`, `Bool`, `Date`, `Data`, and arrays and dictionaries of those). It's optional with no `default:`, keys may be `String` or `RawRepresentable<String>`, and setting `nil` removes the key. It absorbed the removed `@UserDefault`.
  - `@StoredObject(key)` holds a `Codable` value as JSON; setting `nil` removes the key.
- `StateWrappers.swift` — in-memory wrappers:
  - `@Clamped(range)`.
  - `@Trimmed`: stores what was typed, so it's safe to bind to a `TextField`; `$x` gives the trimmed value.
  - `@Debounced(delay:)`: `$x` publishes settled changes on main, not the initial value; copies share the stream.
  - `@Logged(name:)`: logs changes with `Log.d` in debug builds.
  - `@Copyable`: `copy()`, falling back to `mutableCopy()`.
  - `@Atomic` and `@Validated` were removed: `@Atomic` wasn't safe for read-modify-write, and `@Validated` silently dropped writes.

### Extensions/

(Renamed from the misspelled `Extentions`.)

- `AnyOptional` / `Optional` — `isNil`, `exists`, and `String?.orEmpty` (`self ?? ""`). For collections: `nilOrEmpty`, `hasContent`, and `content` (which returns `nil` when the collection is empty). The old `String?.empty` / `Int?.empty` were removed; they ignored the value and always returned `""` / `-1`.
- `Binding+Extensions`:
  - `orDefault(_:)` turns any `Binding<T?>` into a `Binding<T>`. `orEmpty()` is the shorthand for `String?` (`""`), `Bool?` (`false`) and `Date?` (the current date while `nil`).
  - `unwrap(...)` makes bindings to properties of optional reference objects. These are kept for future use; nothing calls them yet.
  - `isPresent()` turns `Binding<T?>` into `Binding<Bool>`; `customAlert(item:)` uses it.

## How the pieces fit together

```swift
@Component
final class ProfileViewModel: ComponentModel<ProfileViewModel> {
    struct State {}                          // isLoading, error, destination are generated

    enum Destination: RouteDestinationPresentable {
        case bioEditor(BioEditorViewModel.State)
        var presentationStyle: PresentationStyle { .modal }
    }

    enum Action { case editBio }             // no Output: it becomes EmptyOutput

    final class Connections: ConnectionsBase {
        lazy var bioEditor = Connection<BioEditorViewModel> { [weak parent] output in
            parent?.handle(output)
        }
        .connect(state: \.destination, case: \.bioEditor, parent: parent)
    }                                        // setupConnections() and `connections` are generated

    override func send(_ action: Action) {
        switch action {
        case .editBio: state.destination = .bioEditor(.init())
        }
    }

    func handle(_ output: BioEditorViewModel.Output) { /* react to child events */ }
}

// View
struct ProfileView: ComponentView {
    @ObservedObject var model: ProfileViewModel
    var content: some View {
        button(.editBio) { Text("Edit bio") }
            .sheet(item: model.connections.bioEditor.bindingModel) { BioEditorView(model: $0) }
    }
}
```

### Flows are ViewModels

App-level flows use the same pieces. **There is no `Flow` / `FlowCoordinator` layer; it was removed.** Don't reintroduce one. The full pattern, compiled and verified, is in [Documentation/Flows.md](Documentation/Flows.md).

- **Root:** an `AppViewModel` whose state has `var flow: Flow?`, a `@CasePathable` enum with one case per flow (`.login(LoginViewModel.State)`, `.onboarding(…)`, `.main(MainTabViewModel.State)`). Each case gets a `CaseConnection` via `.connect(state: \.flow, case: \.login, parent: parent)`. The rules for which flow comes next live in `send`, and the view is an exhaustive `switch model.flow`.
- **Tab bar:** a `MainTabViewModel` whose state holds `selectedTab` plus every tab's state. Each tab is `Connection.connect(from: parent!, to: \.home)`, which returns a ViewModel that's always present, so tabs keep their state across switches.
- **Inside a tab:** a `ComponentView` root, which the tab bar wraps in `NavigationStack { … }`, using `state.destination` + `CaseConnection` as above.
- **Cross-flow events** (for example logout from deep in a tab) bubble up through output handlers: tab → tab bar → `AppViewModel`. If that gets too deep, use an injected service the root ViewModel subscribes to, never a global coordinator.
- **Several flows on screen at once** (iPad split view) means one ViewModel holding several children. It isn't built yet, and it needs no new types.

Typical app startup:

```swift
AppCoordinator.shared.onConfigure = {
    DependencyContainer.shared.registerSingleton(ErrorService.self, instance: MyErrorService())  // + everything else the app needs
}
AppCoordinator.shared.configureIfNeeded()                      // registers, checks ErrorService, starts services
let appModel = AppViewModel(initialState: .init())             // create after the ErrorService is registered
WindowGroup { AppView(model: appModel) }
```

## Gotchas (read before changing connections or navigation)

- **There are no factories.** `Connection` / `CaseConnection` always build the child with `To.init(initialState:)` from the parent's state or the enum payload, so seed the child's starting state there (`.bioEditor(.init(...))`). Optional child states work the same way. Don't reintroduce `.factory`, or child ViewModels stored in state.
- **`setupConnections()`** — Mirror can't see a `lazy var` until it has been evaluated.
  - If you pass `parent: parent` to `.connect(state:case:parent:)`, the connection wires itself the first time it's accessed, so the override is recommended rather than required. It makes the connection observe the parent from init instead of from the view's first read.
  - If you pass `parent: nil`, the override is **required**. Without it, `model` / `bindingModel` stay `nil` even after `destination` is set.
- **Switching presentations directly.** `destination` changes are synchronous. To switch from one presentation straight to another, prefer `showDestination`: it uses one `.sheet` for every sheet-style destination, and SwiftUI handles that switch itself. Two separate `.sheet` modifiers on the same view can't reliably hand over directly, so dismiss first in that case.
- **Destination equality is case-based.** `ViewModelDestination`'s default `id` is the enum case name, and its default `==` and `hash` use `id`, so `.detail(a) == .detail(b)`. That's what lets payload states skip `Hashable`. Override `id` if payloads need to be distinguished. States themselves have no equality; nothing in the library compares whole states.
- **Binding `bindingModel` to `showDestination(_:destination:)` requires the child ViewModel type itself to conform to `RouteDestinationPresentable`**, because `D` is the child VM type, not the destination enum. Otherwise use `.sheet(item:)` / `.navigationDestination(item:)` / `.customAlert(item:)` directly with `bindingModel`.
- **Every app must provide an `ErrorService`.** This is by design: register it in the container before creating any `BaseViewModel` (see above).
- **Connections don't leak.** `bindingModel` and every observer capture `self` and the parent weakly, and a direct child's `DirectLink` holds both models weakly. `ConnectionLifecycleTests` checks that parents, children and case connections are freed; keep those tests passing when changing captures. Connections log nothing, except `Log.w` on a parent type mismatch.

## Documentation

Three guides in `Documentation/`. Keep them in sync with the code and the gotchas above when changing behaviour:

- [Connections.md](Documentation/Connections.md) — direct, case and optional connections, `setupConnections()`, how syncing works, memory, troubleshooting
- [Navigation.md](Documentation/Navigation.md) — destinations, `push` / `present` / `showDestination` / custom alerts, view protocols, testing
- [Flows.md](Documentation/Flows.md) — root flows, tab bars, deep links (`openDeepLink`, `@DeepLinkable`, `Route`), app startup
- [Backlog.md](Documentation/Backlog.md) — designed but not yet built (`popToRoot()` / `close()`), plus deferred items and app migrations

Doc comments in the source are short and current. When one disagrees with the code, trust the code and fix the comment.
