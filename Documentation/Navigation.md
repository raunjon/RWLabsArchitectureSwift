# Navigation

Navigation is state. A screen navigates by setting `state.destination` on its ViewModel, and the view presents whatever that destination's connection creates. There's no navigator or coordinator object to call.

| Concern | Where |
|---|---|
| Destination enums and presentation styles | `Navigation/Destination.swift` |
| Presenting from a view: `push`, `present`, `presentAsBinding` | `Navigation/Presentation.swift` |
| Presenting by style: `showDestination` | `Base/ComponentView.swift` |
| Custom alerts | `Base/CustomAlert.swift` |
| Turning a destination into a live child | Connections ([Connections.md](Connections.md)) |
| Root flows, tab bars and deep links | [Flows.md](Flows.md) |

## 1. Destinations

Each screen's state has an optional `destination`: a `@CasePathable` enum with one case per child, carrying the child's **state** (not the child ViewModel):

```swift
@CasePathable
enum Destination: ViewModelDestination {
    case detail(ProductDetailModel.State)
    case cart(CartModel.State)
}

struct State: ViewModelState {
    var products: [Product] = []
    var isLoading = false
    var error: Error?
    var destination: Destination?        // EmptyDestination? for a screen that never navigates
}
```

- **Identity:** `ViewModelDestination` gives every value an `id`, which is the case name (`"detail"`). `==` and `hash` use it, so payload states don't need to be `Equatable` or `Hashable`. Override `id` if two values of the same case must be told apart.
- **`EmptyDestination`** has no cases, so a screen using it can never navigate.

## 2. Navigating from the ViewModel

```swift
override func send(_ action: Action) {
    switch action {
    case .productTapped(let product): state.destination = .detail(.init(product: product))
    case .cartTapped:                 state.destination = .cart(.init())
    case .close:                      dismiss()          // destination = nil
    }
}
```

`model.destination` is a plain pass-through to `state.destination`, so the two are interchangeable, and changes are synchronous.

## 3. Presenting from the View

Bind each destination's connection to a presentation. The helpers work on any view, so chain them after other modifiers:

```swift
// The parent hosts this screen in a NavigationStack (tab bar or root flow)
struct ProductListView: ComponentView {
    @ObservedObject var model: ProductListModel

    var content: some View {
        List(model.products) { product in
            Button(product.name) { model.send(.productTapped(product)) }
        }
        .navigationTitle("Products")
        .push(model.connections.detail) { ProductDetailView(model: $0) }
        .present(model.connections.cart) { CartView(model: $0) }
    }
}
```

| Helper | Shows the child as | Notes |
|---|---|---|
| `.push(connection) { … }` | A push onto the enclosing `NavigationStack` | Optional `enableBackButton:` goes to `customBackButton(enable:)`, which is a placeholder for now |
| `.present(connection) { … }` | A sheet | |
| `.customAlert(item: connection.bindingModel) { … }` | A custom alert overlay | See §5 |
| `.presentAsBinding(item: $optionalModel) { … }` | A sheet, for a `VM?` binding | |

`push` and `present` also accept a binding to the connection (`$model.connections.detail`).

Dismissing a sheet, popping back, or closing the alert clears the parent's `destination`. A destination that's already set when the view appears is shown.

### Presenting by style with `showDestination`

Alternatively, a destination can say how it's presented, and one modifier presents every case:

```swift
@CasePathable
enum Destination: RouteDestinationPresentable {
    case detail(ProductDetailModel.State)
    case cart(CartModel.State)

    var presentationStyle: PresentationStyle {
        switch self {
        case .detail: .push
        case .cart:   .modal
        }
    }
}

content.showDestination(model.binding(\.destination)) { destination in
    switch destination {
    case .detail: model.connections.detail.model.map(ProductDetailView.init)
    case .cart:   model.connections.cart.model.map(CartView.init)
    }
}
```

| `PresentationStyle` | Modifier |
|---|---|
| `.push` | `.navigationDestination(item:)` |
| `.modal` | `.sheet(item:)` |
| `.fullScreen` | `.fullScreenCover(item:)` |
| `.customAlert` | `.customAlert(item:)` |
| `.alert` | `.sheet(item:)` for now; use SwiftUI's `.alert` for system alert chrome |

All four modifiers are always attached, each seeing the value only when its style matches, so the view keeps its identity as destinations come and go. `showDestination` also accepts a connection's `bindingModel`, but then the **child ViewModel** must conform to `RouteDestinationPresentable`.

### Switching straight from one presentation to another

SwiftUI handles a change within one `.sheet` modifier. Two separate `.sheet` modifiers on the same view can't reliably hand over directly. When going straight from one sheet to another, either use `showDestination`, which has a single sheet modifier, or dismiss first.

## 4. View Protocols

| Protocol | `body` |
|---|---|
| `ComponentView` (**use this**) | `content`, calling `model.onAppear()` each time it appears. Adds `button(_ action:) { label }` and `onOutput(of:)`. |
| `RoutableView` | `NavigationStack { content }`. Not used in the default pattern, where the parent hosts navigation roots. Don't combine it with `ComponentView`. |
| `BaseView` (+ `Tappable`) | The base of both |

A view holds its model as `@ObservedObject` when a parent or connection owns it, or as `@StateObject` when the view owns it.

## 5. Custom Alerts

`customAlert(isPresented:)` and `customAlert(item:)` show their content in a separate window above the app, over a dimmed background:
- **Window:** it becomes the key window, and VoiceOver can't reach the screen behind it.
- **Background tap:** dismisses, unless `dismissOnBackgroundTap: false`.
- **Animation:** it animates in and out the same way whether it's dismissed by a tap or by clearing the binding in code.

Because it's a separate window:
- It **doesn't inherit the presenting view's environment.** Pass data through the model.
- **`@Environment(\.dismiss)` does nothing inside it.** Close it by clearing the binding, usually by having the child ask the parent to clear `destination`.
- **If the presenting view disappears** (for example on a tab switch), it closes and resets the binding.

## 6. Testing

Navigation is state, so assert on `state.destination` and on the connection:

```swift
@MainActor
func testTappingAProductPushesDetail() {
    DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    let model = ProductListModel(initialState: .init())
    model.send(.productTapped(.mock))

    guard case .detail(let detail)? = model.state.destination else { return XCTFail("expected .detail") }
    XCTAssertEqual(detail.product.id, Product.mock.id)
    XCTAssertNotNil(model.connections.detail.model)     // reading model activates the child
}
```

Popping to the root of a stack from a deep screen isn't built yet; the design is in [Backlog.md](Backlog.md).
