# RWLabsArchitecture

A small, state-driven architecture for SwiftUI apps.

Every screen is a **model** (what the screen knows and does) plus a **view** (how it looks). Screens link to their child screens through **connections**, and navigation is just state: set a value and the screen appears, clear it and it goes away. There are no coordinators or routers to call.

```
┌──────────────┐   send(.action)   ┌───────────────┐   sendOutput(.event)   ┌──────────────┐
│     View     │ ────────────────▶ │     Model     │ ─────────────────────▶ │ Parent model │
│ (SwiftUI)    │ ◀──────────────── │ state, send() │                        │              │
└──────────────┘   reads state     └───────────────┘                        └──────────────┘
```

**Contents**

1. [Requirements and installation](#requirements-and-installation)
2. [The idea in one minute](#the-idea-in-one-minute)
3. [Your first screen](#your-first-screen)
4. [Setting up the app](#setting-up-the-app)
5. [What `@Component` writes for you](#what-component-writes-for-you)
6. [Child screens: connections](#child-screens-connections)
7. [Navigation](#navigation)
8. [App flows and tab bars](#app-flows-and-tab-bars)
9. [Deep links](#deep-links)
10. [Edit screens](#edit-screens)
11. [Dependencies](#dependencies)
12. [Async work, loading and errors](#async-work-loading-and-errors)
13. [Storage and property wrappers](#storage-and-property-wrappers)
14. [Built-in services](#built-in-services)
15. [Testing](#testing)
16. [Things to know](#things-to-know)
17. [Further reading](#further-reading)

---

## Requirements and installation

| | |
|---|---|
| Platform | iOS 17+ |
| Swift tools | 6.2 |
| Dependencies | [swift-case-paths](https://github.com/pointfreeco/swift-case-paths) and [swift-syntax](https://github.com/swiftlang/swift-syntax) (for the macros), and [RWLabsFoundation](https://github.com/raunjon/RWLabsFoundation), which is re-exported, so `import RWLabsArchitecture` also brings in its Optional, Binding and Async helpers |

Add the package in Xcode (**File ▸ Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/raunjon/RWLabsArchitectureSwift.git", branch: "master")
// or, for a local checkout next to your app:
.package(path: "../RWLabsArchitecture")
```

Then `import RWLabsArchitecture`. It re-exports CasePaths, so you don't need to import that too.

The examples assume your app target uses Swift 5 mode, or Swift 6 with **Default Actor Isolation = MainActor** (the default for new Xcode projects). In plain Swift 6 mode, see [Swift 6 notes](#things-to-know).

The package ships Swift macros. The first time you build, Xcode asks you to **Trust & Enable** them. On the command line, pass `-skipMacroValidation` to `xcodebuild`.

---

## The idea in one minute

Each screen has three small types and one class:

| Piece | What it is | Example |
|---|---|---|
| `State` | Everything the screen shows, as plain data | `count`, `profile`, `isLoading` |
| `Action` | What the user (or the view) can ask for | `.increment`, `.save` |
| `Output` | What the screen tells its **parent** | `.saved(profile)`, `.loggedOut` |
| The model | A `ComponentModel` that changes `state` in `send(_:)` | `CounterModel` |

The rules:

- **The view only reads state and sends actions.** It never changes state itself.
- **The model is the only thing that changes its state.**
- **A child talks to its parent through outputs**, never by holding a reference to it.
- **Navigation is state.** A screen shows a child by setting `destination`, and hides it by clearing it.

---

## Your first screen

```swift
import SwiftUI
import RWLabsArchitecture

@Component
final class CounterModel: ComponentModel<CounterModel> {
    struct State {
        var count = 0
    }

    enum Action { case increment, reset }
    enum Output { case reachedTen }

    override func send(_ action: Action) {
        switch action {
        case .increment:
            state.count += 1
            if state.count == 10 { sendOutput(.reachedTen) }
        case .reset:
            state.count = 0
        }
    }
}

struct CounterView: ComponentView {
    @ObservedObject var model: CounterModel

    var content: some View {
        VStack {
            Text("\(model.count)")                    // same as model.state.count
            button(.increment) { Text("Add one") }    // sends the action on tap
            button(.reset) { Text("Reset") }
        }
    }
}
```

Things to notice:

- **`@Component`** fills in the boilerplate (see [below](#what-component-writes-for-you)).
- **`ComponentModel<CounterModel>`** — the model passes *itself* as the type parameter.
- **`model.count`** reads `model.state.count`. Every state property can be read (and written) this way.
- **`button(_:label:)`** is a `Button` that sends an action.
- **`content`** instead of `body`. `ComponentView` provides `body`, and calls the model's `onAppear()` when the view appears.
- **`@ObservedObject`** when someone else owns the model (a parent or a connection). Use `@StateObject` when the view creates and owns it.

---

## Setting up the app

The library registers nothing on its own. **Every app must register an `ErrorService`** (models forward errors to it) before it creates its first model.

```swift
struct AppErrorService: ErrorService {
    func handleError(_ error: Error) {
        Log.e("Unhandled error", error: error)
    }
}

@main
struct MyApp: App {
    @StateObject private var appModel: AppModel

    init() {
        AppCoordinator.shared.onConfigure = {
            let container = DependencyContainer.shared
            container.registerSingleton(ErrorService.self, instance: AppErrorService())
            container.registerSingleton(LoggerService.self, instance: ConsoleLogger())
            // …everything else the app uses
        }
        AppCoordinator.shared.configureIfNeeded()   // registers, checks ErrorService, starts services
        _appModel = StateObject(wrappedValue: AppModel(initialState: .init()))
    }

    var body: some Scene {
        WindowGroup { AppView(model: appModel) }
    }
}
```

`configureIfNeeded()` stops with a clear message if no `ErrorService` is registered. It also calls `start()` on every registered singleton that conforms to `Service`. `AppCoordinator.shared.teardown()` stops them again.

---

## What `@Component` writes for you

Without the macro, a model has a lot of repeated code. `@Component` writes it, and **anything you write yourself wins**.

| You write | `@Component` adds |
|---|---|
| `struct State { … }` | `isLoading`, `error`, `destination` and the `ViewModelState` conformance |
| `enum Destination { … }` | `@CasePathable` and `ViewModelDestination` |
| `enum Action` / `enum Output` | Their conformances |
| *(nothing)* for `Destination`, `Action` or `Output` | Empty defaults (`EmptyDestination`, `EmptyAction`, `EmptyOutput`) |
| `class Connections: ConnectionsBase { … }` | `ConnectionsBase` itself, the `connections` property, `setupConnections()` and `HasConnections` |
| — | The `ComponentTypes` conformance that `ComponentModel<Self>` needs |

<details>
<summary>The same model without the macro</summary>

```swift
final class CounterModel: ComponentModel<CounterModel> {
    struct State: ViewModelState {
        var count = 0
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }
    enum Action: ViewModelAction { case increment, reset }
    enum Output: ViewModelOutput { case reachedTen }

    override func send(_ action: Action) { … }
}
extension CounterModel: ComponentTypes {}
```

</details>

---

## Child screens: connections

A parent keeps its child's **state** inside its own state. A **connection** turns that state into a live child model, keeps the two in sync in both directions, and delivers the child's outputs to the parent.

There are three kinds:

| Kind | The parent's state holds | The child exists | Use it for |
|---|---|---|---|
| **Direct** | The child's state, always | As long as the parent | Tabs, embedded panels |
| **Case** | The child's state inside one case of an enum (usually `destination`) | While that case is set | Pushes, sheets, alerts, app flows |
| **Optional** | The child's state as an optional | While it's not `nil` | Inline components shown on demand |

```swift
@Component
final class ProfileModel: ComponentModel<ProfileModel> {
    struct State {
        var name = ""
        var stats = StatsModel.State()            // direct child
        var banner: BannerModel.State?            // optional child
    }

    enum Destination {
        case editor(EditorModel.State)            // case child (a sheet)
        case settings(SettingsModel.State)        // case child (a push)
    }

    enum Action { case editTapped, settingsTapped, showBanner }

    final class Connections: ConnectionsBase {
        // Direct: returns the child model itself
        lazy var stats: StatsModel = Connection<StatsModel>()
            .connect(from: parent!, to: \.stats)

        // Case: exists while destination == .editor
        lazy var editor = Connection<EditorModel> { [weak parent] output in
            switch output {
            case .saved(let name): parent?.state.name = name
            }
        }
        .connect(state: \.destination, case: \.editor, parent: parent)

        lazy var settings = Connection<SettingsModel>()
            .connect(state: \.destination, case: \.settings, parent: parent)

        // Optional: exists while banner != nil
        lazy var banner = Connection<BannerModel>()
            .connect(state: \.banner, parent: parent)
    }

    override func send(_ action: Action) {
        switch action {
        case .editTapped:     destination = .editor(.init(name: state.name))   // the payload is the child's starting state
        case .settingsTapped: destination = .settings(.init())
        case .showBanner:     state.banner = .init()
        }
    }
}
```

Good to know:

- **The child is always built from state**: `EditorModel(initialState: payload)`. To give a child a starting value, put it in the payload.
- **Edits flow both ways.** When the editor changes its state, the parent's `.editor(…)` payload updates too, and vice versa.
- **Use `[weak parent]`** in output handlers. Connections themselves never keep a parent or child alive.
- **Read a child** with `model.connections.editor.model` (an optional `EditorModel`).

---

## Navigation

### Showing children

Navigation is `state.destination`. The view binds each connection to a presentation:

```swift
struct ProfileView: ComponentView {
    @ObservedObject var model: ProfileModel

    var content: some View {
        VStack {
            Text(model.name)
            StatsView(model: model.connections.stats)                      // direct child, embedded

            if let banner = model.connections.banner.model {               // optional child, inline
                BannerView(model: banner)
            }

            button(.editTapped) { Text("Edit") }
            button(.settingsTapped) { Text("Settings") }
        }
        .present(model.connections.editor) { EditorView(model: $0) }      // a sheet
        .push(model.connections.settings) { SettingsView(model: $0) }     // a push
    }
}
```

| Helper | Shows the child as |
|---|---|
| `.push(connection) { … }` | A push onto the enclosing `NavigationStack` |
| `.present(connection) { … }` | A sheet |
| `.customAlert(item: connection.bindingModel) { … }` | A custom alert in its own window above the app |
| `.showDestination(model.binding(\.destination)) { … }` | Whatever each case's `presentationStyle` says (`.push`, `.modal`, `.fullScreen`, `.customAlert`) |

When the user swipes a sheet away or taps Back, the parent's `destination` is cleared automatically.

`ComponentView` doesn't add a `NavigationStack`. The view that *hosts* a stack adds it, e.g. `NavigationStack { HomeView(model: home) }` in the tab bar.

### Going back: `close()` and `popToRoot()`

A child can leave without its parent having to handle an output:

```swift
override func send(_ action: Action) {
    switch action {
    case .cancelTapped: close()        // pop, dismiss or remove just this screen
    case .doneTapped:   popToRoot()    // back to the first screen of this NavigationStack
    }
}
```

- **`close()`** works for pushes, sheets, alerts and optional inline children.
- **`popToRoot()`** pops every pushed screen in one animation. Inside a sheet, it goes back to the sheet's first screen and leaves the sheet open.

The parent can always close a child itself too: `destination = nil` (or `dismiss()`).

---

## App flows and tab bars

There's no separate flow system: an app flow is just a model whose state decides which child is showing.

```swift
@Component
final class AppModel: ComponentModel<AppModel> {
    struct State {
        var flow: Flow? = .login(.init())
    }

    @CasePathable
    enum Flow: ViewModelDestination {
        case login(LoginModel.State)
        case main(MainTabModel.State)
    }

    enum Action { case loggedIn, loggedOut }

    final class Connections: ConnectionsBase {
        lazy var login = Connection<LoginModel> { [weak parent] output in
            switch output { case .loggedIn: parent?.send(.loggedIn) }
        }
        .connect(state: \.flow, case: \.login, parent: parent)

        lazy var main = Connection<MainTabModel> { [weak parent] output in
            switch output { case .loggedOut: parent?.send(.loggedOut) }
        }
        .connect(state: \.flow, case: \.main, parent: parent)
    }

    override func send(_ action: Action) {
        switch action {
        case .loggedIn:  state.flow = .main(.init())
        case .loggedOut: state.flow = .login(.init())
        }
    }
}

struct AppView: ComponentView {
    @ObservedObject var model: AppModel

    var content: some View {
        switch model.flow {
        case .login: model.connections.login.model.map(LoginView.init)
        case .main:  model.connections.main.model.map(MainTabView.init)
        case nil:    ProgressView()
        }
    }
}
```

A **tab bar** holds every tab's state at once and connects each tab with a direct connection, so each tab keeps its state and navigation stack while the user switches:

```swift
@Component
final class MainTabModel: ComponentModel<MainTabModel> {
    enum Tab: Hashable { case home, profile }

    struct State {
        var selectedTab: Tab = .home
        var home = HomeModel.State()
        var profile = ProfileModel.State()
    }

    final class Connections: ConnectionsBase {
        lazy var home: HomeModel = Connection<HomeModel>().connect(from: parent!, to: \.home)
        lazy var profile: ProfileModel = Connection<ProfileModel>().connect(from: parent!, to: \.profile)
    }
}

struct MainTabView: ComponentView {
    @ObservedObject var model: MainTabModel

    var content: some View {
        TabView(selection: model.binding(\.selectedTab)) {
            NavigationStack { HomeView(model: model.connections.home) }
                .tag(MainTabModel.Tab.home)
            NavigationStack { ProfileView(model: model.connections.profile) }
                .tag(MainTabModel.Tab.profile)
        }
    }
}
```

**Events from deep inside** (like "log out" from a settings screen) travel up through outputs: settings → tab → tab bar → app. If that chain gets long, inject a small service (say, a `SessionService`) that the app model listens to.

---

## Deep links

Any screen can be opened from a link with one call:

```swift
appModel.openDeepLink(Route(url: url))      // e.g. myapp://profile/settings
```

Each path segment opens one level. To make a screen's destinations linkable, add `@DeepLinkable` to its `Destination`:

```swift
@DeepLinkable
enum Destination {
    case settings(SettingsModel.State)                   // …/settings

    @DeepLink("item", params: ["id": "itemId"])         // …/item?id=42 → itemId = "42"
    case detail(ItemDetailModel.State)

    @DeepLink(skip: true)                                // can't be linked to
    case confirmDelete(ConfirmModel.State)
}
```

- **Case names become URL names**, unless `@DeepLink("…")` renames them.
- **`params`** copies query items into state properties, converting `String`, `Int`, `Double`, `Bool`, `UUID` and their optionals.
- **A model that isn't driven by `destination`** (like a tab bar) adopts `DeepLinkStepHandler` and picks the child itself.
- **When a link can't open**, `openDeepLink` returns `false`, keeps everything it opened so far, and logs a warning saying exactly what's missing.

`Route` also parses and builds URLs on its own: `route.matches(pattern: "/item/:id")` returns `["id": "42"]`, and `route.url(scheme: "myapp")` builds a link.

---

## Edit screens

`Editable<Item>` keeps the item as loaded next to the user's draft, so a screen knows whether anything changed and can undo it:

```swift
@Component
final class ProfileEditModel: ComponentModel<ProfileEditModel> {
    struct State: ItemEditingState {
        var item: Editable<Profile>
    }

    enum Action { case save, revert }
    enum Output { case saved(Profile) }

    @Injected var api: ProfileAPI

    override func send(_ action: Action) {
        switch action {
        case .revert:
            revert()                                         // draft = original
        case .save:
            perform { [api, draft = state.item.draft] in try await api.save(draft) }
            then: { [weak self] saved in
                self?.commit(saved)                          // original = draft = saved
                self?.sendOutput(.saved(saved))
            }
        }
    }
}

// In the view
TextField("Name", text: model.binding(draft: \.name))
button(.save) { Text("Save") }.disabled(!model.isModified)
```

`Item` must be `Equatable`, so changing a value back to what it was doesn't count as a change. For a screen that edits several items, use `Editable` properties directly (`state.address.isModified`).

---

## Dependencies

Register services once at startup, then inject them anywhere:

```swift
// Registering
let container = DependencyContainer.shared
container.registerSingleton(ProfileAPI.self, instance: LiveProfileAPI())   // one shared instance
container.registerLazySingleton(Database.self) { Database() }              // created on first use
container.register(Formatter.self) { Formatter() }                         // a new one every time

// Using
final class ProfileModel: ComponentModel<ProfileModel> {
    @Injected var api: ProfileAPI               // resolved when the model is created; crashes if missing
    @LazyInjected var database: Database        // resolved on first use
    @OptionalInjected var analytics: AnalyticsService?   // nil if not registered
}
```

- Register protocols as the protocol type (`ProfileAPI.self`) and resolve them the same way.
- A singleton that conforms to `Service` gets `start()` and `stop()` calls from `AppCoordinator`.
- In tests, swap a dependency by assigning it: `model.api = MockProfileAPI()`.

---

## Async work, loading and errors

```swift
case .load:
    perform { [api] in try await api.fetchProfile() }
    then: { [weak self] profile in self?.state.profile = profile }
```

`perform`:

1. sets `isLoading` to `true` while it runs;
2. passes the result to `then`;
3. sends any thrown error to `handleError(_:)`, which stores it in `state.error` and forwards it to your `ErrorService`;
4. returns the `Task`, so you can cancel it.

You can also call `startLoading()`, `stopLoading()` and `handleError(_:)` yourself, and `state.clearError()` to dismiss an error.

---

## Storage and property wrappers

### Persisted values

```swift
UserDefaults.appSuiteName = "group.com.example.myapp"   // optional; share data with extensions

@Preference("hasSeenIntro", default: false) var hasSeenIntro: Bool
@Preference("lastUser") var lastUser: String?           // optional; setting nil removes it
@StoredObject("profile") var cachedProfile: Profile?    // any Codable, stored as JSON
```

`UserDefaults.standard` isn't shared between an app and its widgets or extensions. To share, set `appSuiteName` to an App Group id (starting with `group.`) enabled in every target.

### In-memory helpers

| Wrapper | Does |
|---|---|
| `@Clamped(0...100)` | Keeps a value inside a range |
| `@Trimmed` | Stores what was typed; `$name` gives it without surrounding spaces |
| `@Debounced(delay: 0.3)` | `$query` publishes only once typing settles (for search) |
| `@Logged(name: "count")` | Logs each change in debug builds |
| `@Copyable` | Stores a copy of an `NSCopying` object |

---

## Built-in services

None of these are registered for you; register the ones you want.

| Service | What it gives you |
|---|---|
| `LoggerService` / `ConsoleLogger` | Levelled logging. Use `Log.d`, `Log.i`, `Log.w`, `Log.e`… from anywhere; messages are dropped if no logger is registered. |
| `ValidationService` / `DefaultValidationService` | `validate(text, rules: [.required, .email, .minLength(8), .minAge(18, dateFormat: "yyyy-MM-dd")])` |
| `AnalyticsService` / `ConsoleAnalyticsService` | A simple analytics protocol, plus an implementation that prints every call |
| `Async` | `Async.main { }`, `Async.background { }`, `Async.after(0.5) { }` |

---

## Testing

Models are plain classes, so you test them without any UI:

```swift
@MainActor
final class ProfileModelTests: XCTestCase {
    override func setUp() {
        super.setUp()
        DependencyContainer.shared.registerSingleton(ErrorService.self, instance: TestErrorService())
    }

    func testEditOpensTheEditor() {
        let model = ProfileModel(initialState: .init(name: "Ada"))

        model.send(.editTapped)

        XCTAssertEqual(model.connections.editor.model?.state.name, "Ada")
    }
}
```

- **Register an `ErrorService`** in `setUp`. Every model needs one.
- **Assert on state**: navigation is `state.destination`, so "did it open the editor?" is a state check.
- **Syncing between parent and child happens on the next main-queue turn.** Before asserting a child edit reached the parent, let the queue run once (`await Task.yield()` or a short `DispatchQueue.main.async` wait).

The package's own tests run on the iOS Simulator:

```bash
xcodebuild test -scheme RWLabsArchitecture -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -skipMacroValidation
```

---

## Things to know

- **Inside a model, write `state.x = …` (or `self.x = …`)**, not a bare `x = …`. Reading `model.x` from outside works through dynamic member lookup, but Swift only uses that when there's an explicit receiver.
- **State holds data, never models.** Put the child's *state* in your state and let a connection create the model.
- **Destinations compare by case.** `.detail(a) == .detail(b)` is `true`, so states don't have to be `Equatable`. Override `id` if two values of the same case must differ.
- **Two separate `.sheet` modifiers can't hand over directly.** To switch from one sheet straight to another, use `showDestination` (one sheet for every sheet-style destination) or dismiss first.
- **Without `@Component`:** reference each case connection in `setupConnections()` (`_ = editor`), and adopt `HasConnections` on models that use deep links.
- **`@LazyInjected` works in classes**, not in SwiftUI view structs.
- **Swift 6 mode without MainActor default isolation:** write views as `struct ProfileView: @MainActor ComponentView`, and make services you use inside `perform { }` `Sendable` (`protocol ProfileAPI: Sendable`).

---

## Further reading

The `Documentation/` folder goes deeper:

- [Connections.md](Documentation/Connections.md) — the three connection kinds, how syncing works, memory, troubleshooting
- [Navigation.md](Documentation/Navigation.md) — destinations, push / present / `showDestination`, custom alerts, `close()` / `popToRoot()`
- [Flows.md](Documentation/Flows.md) — root flows, tab bars, deep links, app startup

Every public type also has a short doc comment with an example. Option-click it in Xcode.

### Project layout

```
Sources/RWLabsArchitecture/Architecture/
├── Base/                  ComponentModel, ComponentView, @Component, Editable, custom alerts
├── Core/                  Protocols, AppCoordinator, Service / ErrorService
├── Navigation/            Destinations, push/present, close/popToRoot, deep links, Route
│   └── Connections/       Connection, CaseConnection, ViewModelConnections
├── DependencyInjection/   DependencyContainer
├── PropertyWrappers/      @Injected…, @Preference, @StoredObject, state wrappers
└── Services/              Logger, Validation, Analytics
Sources/RWLabsArchitectureMacros/   @Component, @DeepLinkable, @DeepLink
Tests/RWLabsArchitectureTests/      XCTest suite (iOS Simulator)
```
