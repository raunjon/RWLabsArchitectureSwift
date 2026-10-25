# Flows and Deep Links

An app has several flows: login, onboarding, the main tab bar, and inside that, one flow per tab. This library has **no separate flow system** for them. A flow is a ViewModel whose state decides which child is showing. It uses the same `Connection` / `CaseConnection` wiring as every screen.

The old `Flow` / `FlowCoordinator` / `FlowContext` / `FlowContainer` layer was removed, along with `AppCoordinator.flowCoordinator`, `configureFlow()` and `onSetupInitialFlow`.

There are three levels:

| Level | What decides what's showing | Wiring |
|-------|-----------------------------|--------|
| Root (login / onboarding / main) | `AppViewModel.state.flow`, an optional enum | `CaseConnection` on `\.flow` |
| Tab bar | `MainTabViewModel.state.selectedTab`; every tab's state is always present | `Connection.connect(from:to:)` per tab |
| Inside a tab | Each screen's `state.destination` | `CaseConnection` on `\.destination` (see [Navigation.md](Navigation.md)) |

## 1. Root Flow

The root ViewModel holds an optional enum with one case per flow. Each case carries that flow's **state**, the same rule as destination enums.

```swift
@Component
final class AppViewModel: ComponentModel<AppViewModel> {
    @CasePathable
    enum Flow: ViewModelDestination {
        case login(LoginViewModel.State)
        case onboarding(OnboardingViewModel.State)
        case main(MainTabViewModel.State)
    }

    struct State: ViewModelState {
        var flow: Flow? = .login(.init())
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }

    enum Action: ViewModelAction { case didLogIn(isNewUser: Bool), didFinishOnboarding, didLogOut }

    lazy var connections = Connections(parent: self)

    final class Connections: ViewModelConnections<AppViewModel> {
        lazy var login = Connection<LoginViewModel> { [weak parent] output in
            switch output {
            case .loggedIn(let isNewUser): parent?.send(.didLogIn(isNewUser: isNewUser))
            }
        }
        .connect(state: \.flow, case: \.login, parent: parent)

        lazy var onboarding = Connection<OnboardingViewModel> { [weak parent] output in
            switch output {
            case .finished: parent?.send(.didFinishOnboarding)
            }
        }
        .connect(state: \.flow, case: \.onboarding, parent: parent)

        lazy var main = Connection<MainTabViewModel> { [weak parent] output in
            switch output {
            case .loggedOut: parent?.send(.didLogOut)
            }
        }
        .connect(state: \.flow, case: \.main, parent: parent)

        override func setupConnections() {
            _ = login
            _ = onboarding
            _ = main
        }
    }

    // The rules that decide which flow comes next live here
    override func send(_ action: Action) {
        switch action {
        case .didLogIn(let isNewUser): state.flow = isNewUser ? .onboarding(.init()) : .main(.init())
        case .didFinishOnboarding:     state.flow = .main(.init())
        case .didLogOut:               state.flow = .login(.init())
        }
    }
}
```

`.connect(state:case:parent:)` works with any optional `@CasePathable` enum on the parent's state, not just `destination`.

When `flow` moves from one case to another, the old flow's connection deactivates and drops its ViewModel, and the new one is created from the case payload. To start a flow in a particular state, put that state in the payload: `.main(.init(selectedTab: .profile))`.

The view is an exhaustive switch:

```swift
struct AppView: ComponentView {
    @ObservedObject var model: AppViewModel

    var content: some View {
        switch model.flow {
        case .login:      model.connections.login.model.map(LoginView.init)
        case .onboarding: model.connections.onboarding.model.map(OnboardingView.init)
        case .main:       model.connections.main.model.map(MainTabView.init)
        case nil:         ProgressView()
        }
    }
}
```

## 2. Tab Bar

Every tab's state is always present, so each tab is an ordinary `Connection.connect(from:to:)` that returns a non-optional ViewModel. Tabs stay alive while the user switches between them, so each one keeps its state and its navigation stack.

```swift
@Component
final class MainTabViewModel: ComponentModel<MainTabViewModel> {
    enum Tab: Hashable { case home, profile }

    struct State: ViewModelState {
        var selectedTab: Tab = .home
        var home = HomeViewModel.State()
        var profile = ProfileViewModel.State()
        var isLoading = false
        var error: Error?
        var destination: EmptyDestination?
    }

    enum Action: ViewModelAction { case select(Tab) }
    enum Output: ViewModelOutput { case loggedOut }

    lazy var connections = Connections(parent: self)

    final class Connections: ViewModelConnections<MainTabViewModel> {
        lazy var home: HomeViewModel = Connection<HomeViewModel>()
            .connect(from: parent!, to: \.home)

        lazy var profile: ProfileViewModel = Connection<ProfileViewModel> { [weak parent] output in
            switch output {
            case .loggedOut: parent?.sendOutput(.loggedOut)   // bubble up to AppViewModel
            }
        }
        .connect(from: parent!, to: \.profile)
    }

    override func send(_ action: Action) {
        switch action {
        case .select(let tab): state.selectedTab = tab
        }
    }
}

struct MainTabView: ComponentView {
    @ObservedObject var model: MainTabViewModel

    var content: some View {
        TabView(selection: model.binding(\.selectedTab)) {
            NavigationStack { HomeView(model: model.connections.home) }
                .tabItem { Label("Home", systemImage: "house") }
                .tag(MainTabViewModel.Tab.home)
            NavigationStack { ProfileView(model: model.connections.profile) }
                .tabItem { Label("Profile", systemImage: "person") }
                .tag(MainTabViewModel.Tab.profile)
        }
    }
}
```

## 3. Inside a Tab

Each tab's root is an ordinary `ComponentView`. The tab bar wraps it in `NavigationStack { … }` (above), so each tab gets its own stack. Navigate with `state.destination` plus `CaseConnection`, exactly as on any other screen. See [Navigation.md](Navigation.md).

## Events That Change the Flow from Deep Inside

Child outputs bubble up one level at a time through the output handlers above. Tapping "Log out" on the profile screen takes this path:

```
ProfileViewModel  --.loggedOut-->  MainTabViewModel  --.loggedOut-->  AppViewModel.send(.didLogOut)
```

If an event starts several levels deep and threading it through each level gets tedious, don't add a global coordinator. Inject a small service instead (for example a `SessionService` with a publisher) and have `AppViewModel` subscribe to it.

## App Startup

```swift
@main
struct MyApp: App {
    @StateObject private var appModel: AppViewModel

    init() {
        AppCoordinator.shared.onConfigure = {
            // The library registers nothing; register everything the app uses, including the required ErrorService
            DependencyContainer.shared.registerSingleton(ErrorService.self, instance: AppErrorService())
        }
        AppCoordinator.shared.configureIfNeeded()   // runs onConfigure, checks ErrorService, starts services
        _appModel = StateObject(wrappedValue: AppViewModel(initialState: .init()))
    }

    var body: some Scene {
        WindowGroup { AppView(model: appModel) }
    }
}
```

The `ErrorService` has to be registered before the first ViewModel is created. That's why `AppViewModel` is created in `init` after `configure()`, rather than as a property default.

To decide the first flow at launch (for example, skip login when a session exists), set it in the initial state: `AppViewModel(initialState: .init(flow: session.isValid ? .main(.init()) : .login(.init())))`.

## Deep Links

Every screen can be deep-linked. A link's path is read as one screen name per level, and its query items carry the parameters:

```
myapp://home/item?id=42           → tab "home" → open item 42
myapp://profile/orders/order?id=7 → tab "profile" → orders → order 7
https://example.com/home/item?id=42  (universal links give the same path)
```

`model.openDeepLink(route)` walks the path down the ViewModel tree. At each level:
1. a model that adopts `DeepLinkStepHandler` handles the step itself (tab bars);
2. otherwise its `Destination`, if `DeepLinkable`, builds a case from the step, `state.destination` is set, and the link continues into the child that destination's connection creates.

It returns `false`, and logs a warning, at the first segment no screen recognises. Everything before that segment stays open.

### Per screen: `@DeepLinkable` on its destination enum

```swift
@DeepLinkable
@CasePathable
enum Destination: ViewModelDestination {
    @DeepLink("item", params: ["id": "itemId"])   // …/item?id=42
    case detail(ItemDetailModel.State)

    @DeepLink(params: ["orderId": "orderId"])    // …/order?orderId=7 (converted to the Int property)
    case order(OrderModel.State)

    case settings(SettingsModel.State)           // …/settings: the case name, built with State()

    @DeepLink(skip: true)                        // not linkable
    case confirmDelete(ConfirmModel.State)
}

@Component   // adds HasConnections and setupConnections()
final class HomeModel: ComponentModel<HomeModel> { … }
```

The macro generates the `DeepLinkable` conformance:
- **URL names:** every case is linkable under its case name, unless `@DeepLink("name")` renames it or `@DeepLink(skip: true)` leaves it out.
- **Payloads:** a case's payload is built with `State()`, so each payload state needs defaults for every property.
- **Parameters:** `params` maps query item names to state properties, which must be `var`. Supported types are `String`, `Int`, `Double`, `Bool`, `UUID`, any other `LosslessStringConvertible`, and optionals of those. A missing or unconvertible parameter makes the link stop there, except for an optional property, which is left `nil`.
- **Cases without a payload** work, so do labelled payloads (`case detail(state: …)`). Cases with more than one associated value don't compile; skip them or give them a single state payload.
- **Mistakes** (a duplicate URL name, an unknown property) are compile errors.

The first time an app builds with it, Xcode asks you to **Trust & Enable** the package's macros, as it does for CasePaths. From the command line, pass `-skipMacroValidation` to `xcodebuild`.

#### Without the macro

Write the initializer yourself when a case needs custom logic:

```swift
extension HomeModel.Destination: DeepLinkable {
    init?(_ step: DeepLinkStep) {
        switch step.name {
        case "item":
            guard let id = step["id"] else { return nil }
            self = .detail(.init(itemId: id))
        case "settings":
            self = .settings(.init())
        default:
            return nil
        }
    }
}

@Component   // adds HasConnections and setupConnections()
final class HomeModel: ComponentModel<HomeModel> { … }
```

- **`HasConnections` and `setupConnections()`:** `@Component` adds both. Without it, adopt `HasConnections` and override `setupConnections()` (`_ = detail`): the link needs `HasConnections` to find the child, and the walker can only see a `lazy` connection once it has been touched.
- **The URL names** are whatever you write in `init?`, not the Swift case names, so renaming a case doesn't break links.
- **Query items are shared by every step.** Use distinct names (`orderId`, `itemId`) if two screens on one path need different values.

### Tab bar: pick the tab, return its model

```swift
extension MainTabModel: DeepLinkStepHandler {
    func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)? {
        switch step.name {
        case "home":    state.selectedTab = .home;    return connections.home
        case "profile": state.selectedTab = .profile; return connections.profile
        default:        return nil
        }
    }
}
```

### Root: switch to the right flow, or keep the link for later

The root decides whether a link can open now. While the user is on login or onboarding, it keeps the link in its state and opens it once the main flow is showing:

```swift
// App
.onOpenURL { appModel.send(.open(Route(url: $0))) }

// AppViewModel
struct State: ViewModelState {
    var flow: Flow? = .login(.init())
    var pendingLink: Route?
    …
}

override func send(_ action: Action) {
    switch action {
    case .open(let route):
        guard case .main? = state.flow, let main = connections.main.model else {
            state.pendingLink = route          // opened after login
            return
        }
        main.openDeepLink(route)

    case .didLogIn:
        state.flow = .main(.init())
        if let route = state.pendingLink, let main = connections.main.model {
            state.pendingLink = nil
            main.openDeepLink(route)
        }
    …
    }
}
```

Only assign `state.flow` when it actually changes. Assigning a new `.main(...)` payload while main is already showing pushes that fresh state into the existing tab bar ViewModel, which resets its tabs.

### Share links

Build the URL from the same path names with `Route`:

```swift
Route(path: "/home/item", queryItems: ["id": item.id]).url(scheme: "myapp")                 // myapp://home/item?id=…
Route(path: "/home/item", queryItems: ["id": item.id]).url(scheme: "https", host: "example.com")
```

### `Route`

`Route(url:)` reduces a link to a path and query items, the same for both link styles: `myapp://home/item?id=42` and `https://example.com/home/item?id=42` both give the path `/home/item`. For a custom scheme, the URL's host is treated as the first path segment.

- `matches(pattern:) -> [String: String]?` matches `:param` placeholders (`"/item/:id"` → `["id": "42"]`), or returns `nil`. `isMatch(_:)` returns a `Bool`. Trailing slashes are ignored. Use these for one-off handling outside `openDeepLink`.
- `url(scheme:host:)` builds `myapp://home/item` (custom scheme) or `https://example.com/home/item` (with a host). Query items are sorted, so the output is stable.

## Testing

A flow is just state, so assert on it directly:

```swift
@MainActor
func testLogoutReturnsToLogin() {
    let app = AppViewModel(initialState: .init(flow: .main(.init())))
    app.send(.didLogOut)
    guard case .login? = app.state.flow else { return XCTFail("expected .login") }
}
```

## Later: Several Flows on Screen at Once (iPad)

A split view is a ViewModel whose state holds more than one child at a time. For example, a sidebar child and a detail child, each with its own `Connection.connect(from:to:)`, or an optional enum for the detail. No new library types are needed.

## Swift 6 Language Mode

In a target compiled in Swift 6 mode without MainActor default isolation, write view conformances as isolated conformances, `struct AppView: @MainActor ComponentView`. Apps that use Swift 5 mode or `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (as ChatApp and RWLabsExamples do) can write `: ComponentView` as shown above.
