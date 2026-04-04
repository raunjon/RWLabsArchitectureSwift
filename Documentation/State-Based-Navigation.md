# State-Based Navigation

## Overview

The architecture now uses **state-based navigation** where all navigation destinations are managed through the `state.destination` property. This provides a single source of truth for navigation state, making it easier to reason about, test, and debug navigation flows.

## Key Changes

### 1. ViewModelState Protocol

All ViewModelStates must now include a `destination` property:

```swift
public protocol ViewModelState {
    /// The destination type for navigation
    associatedtype Destination: RouteDestination

    var isLoading: Bool { get set }
    var error: Error? { get set }

    /// The current navigation destination
    var destination: Destination? { get set }
}
```

### 2. Navigation Through State

Instead of calling navigator methods or managing separate destination properties, you simply set `state.destination`:

```swift
// Old approach (removed):
navigationCoordinator.navigate(to: .detail(id: "123"))

// New approach:
state.destination = .detail(id: "123")
```

### 3. Presentation Style Bindings

The `NavigationCoordinatable` protocol now provides filtered bindings based on presentation style:

- `pushDestination` - For `.push` style (NavigationStack)
- `modalDestination` - For `.modal` and `.fullScreen` styles
- `alertDestination` - For `.alert` style
- `customAlertDestination` - For `.customAlert` style

These bindings automatically filter `state.destination` based on the destination's `presentationStyle`.

## Usage Examples

### Basic ViewModel Setup

```swift
class ProductViewModel: BaseViewModel<State, Action, Output, Destination> {

    struct State: ViewModelState {
        // Required properties
        var isLoading: Bool = false
        var error: Error? = nil
        var destination: Destination? = nil  // ← Navigation state

        // Feature-specific properties
        var products: [Product] = []
        var selectedProduct: Product?
    }

    @CasePathable
    enum Destination: RouteDestination {
        case detail(Product.State)
        case cart
        case settings

        static var featureId: String { "products" }
        static var initialDestination: Destination { .detail(.init()) }

        var presentationStyle: PresentationStyle {
            switch self {
            case .detail:
                return .push  // Push onto navigation stack
            case .cart:
                return .modal  // Present as modal sheet
            case .settings:
                return .fullScreen  // Present full screen
            }
        }
    }

    enum Action: ViewModelAction {
        case selectProduct(Product)
        case showCart
        case showSettings
    }

    enum Output: ViewModelOutput {
        case productPurchased
    }

    override func send(_ action: Action) {
        switch action {
        case .selectProduct(let product):
            // Set destination to navigate
            state.destination = .detail(Product.State(product: product))

        case .showCart:
            state.destination = .cart

        case .showSettings:
            state.destination = .settings
        }
    }
}
```

### SwiftUI View Integration

#### Push Navigation

```swift
struct ProductListView: View {
    @StateObject var viewModel: ProductViewModel

    var body: some View {
        List(viewModel.state.products) { product in
            Button(product.name) {
                viewModel.send(.selectProduct(product))
            }
        }
        .navigationDestination(item: $viewModel.pushDestination) { destination in
            // This binding only activates for .push presentations
            switch destination {
            case .detail(let productState):
                if let detailVM = viewModel.connections.detail.model {
                    ProductDetailView(viewModel: detailVM)
                }
            default:
                EmptyView()
            }
        }
        .sheet(item: $viewModel.modalDestination) { destination in
            // This binding only activates for .modal/.fullScreen presentations
            switch destination {
            case .cart:
                CartView()
            case .settings:
                SettingsView()
            default:
                EmptyView()
            }
        }
    }
}
```

#### Modal Presentation

```swift
struct ProfileView: View {
    @StateObject var viewModel: ProfileViewModel

    var body: some View {
        VStack {
            Text("Profile")

            Button("Edit Bio") {
                // Setting state.destination shows the modal
                viewModel.state.destination = .bioEditor(.init())
            }
        }
        .sheet(item: $viewModel.modalDestination) { destination in
            switch destination {
            case .bioEditor:
                if let editorVM = viewModel.connections.bioEditor.model {
                    BioEditorView(viewModel: editorVM)
                }
            default:
                EmptyView()
            }
        }
    }
}
```

#### Alert Presentation

```swift
struct CheckoutView: View {
    @StateObject var viewModel: CheckoutViewModel

    var body: some View {
        VStack {
            // ... checkout UI ...

            Button("Complete Purchase") {
                viewModel.send(.purchase)
            }
        }
        .alert(item: $viewModel.alertDestination) { destination in
            switch destination {
            case .confirmPurchase(let amount):
                Alert(
                    title: Text("Confirm Purchase"),
                    message: Text("Total: $\(amount)"),
                    primaryButton: .default(Text("Confirm")) {
                        viewModel.send(.confirmPurchase)
                    },
                    secondaryButton: .cancel {
                        viewModel.state.destination = nil
                    }
                )
            default:
                Alert(title: Text("Unknown"))
            }
        }
    }
}
```

### Dismissing Destinations

To dismiss any destination, simply set it to `nil`:

```swift
func dismiss() {
    state.destination = nil
}

// Or from a child through output
enum Output: ViewModelOutput {
    case dismiss
}

// In parent's output handler:
switch output {
case .dismiss:
    state.destination = nil
}
```

### Using with Connections

Connections work seamlessly with state-based navigation:

```swift
class Connections: BaseConnections<ProductViewModel> {

    lazy var detail = Connection<ProductDetailViewModel> { [weak parent] output in
        guard let parent = parent else { return }

        switch output {
        case .addedToCart(let product):
            parent.state.cart.append(product)

        case .close:
            // Dismiss by clearing destination
            parent.state.destination = nil
        }
    }
    .connect(state: \.destination, case: \.detail)
    .factory {
        ProductDetailViewModel(initialState: .init())
    }
}
```

## Benefits

### 1. Single Source of Truth

All navigation state is in one place - `state.destination`. No need to coordinate between multiple properties or coordinators.

```swift
// Everything flows through state
state.destination = .detail(...)  // Navigate
state.destination = nil            // Dismiss
```

### 2. Testability

Navigation is now just state changes, making tests simple:

```swift
func testShowDetail() {
    let viewModel = ProductViewModel(initialState: .init())

    viewModel.send(.selectProduct(testProduct))

    XCTAssertNotNil(viewModel.state.destination)
    if case .detail(let productState) = viewModel.state.destination {
        XCTAssertEqual(productState.product.id, testProduct.id)
    } else {
        XCTFail("Expected detail destination")
    }
}
```

### 3. Time-Travel Debugging

Since navigation is part of state, you can snapshot and restore entire navigation flows:

```swift
let snapshot = viewModel.state
// ... perform actions ...
viewModel.state = snapshot  // Restore including navigation state
```

### 4. State Persistence

Save and restore navigation state easily:

```swift
// Save
let stateData = try JSONEncoder().encode(viewModel.state)
UserDefaults.standard.set(stateData, forKey: "appState")

// Restore (including navigation position!)
let stateData = UserDefaults.standard.data(forKey: "appState")
viewModel.state = try JSONDecoder().decode(State.self, from: stateData)
```

### 5. Declarative SwiftUI Integration

SwiftUI bindings work naturally with state properties:

```swift
.sheet(item: $viewModel.modalDestination) { destination in
    // Automatically shown when state.destination has modal presentation style
}
```

## Presentation Style Reference

| Style | Binding | Usage | Example |
|-------|---------|-------|---------|
| `.push` | `pushDestination` | Navigation stack | List → Detail |
| `.modal` | `modalDestination` | Modal sheet | Show settings |
| `.fullScreen` | `modalDestination` | Full screen cover | Onboarding |
| `.alert` | `alertDestination` | System alert | Confirm action |
| `.customAlert` | `customAlertDestination` | Custom alert view | Custom dialog |
| `.replace` | Handled by coordinator | Replace current | - |
| `.popToRoot` | Handled by coordinator | Pop to root | - |

## Migration Guide

### From Old Pattern

```swift
// Old: Separate destination property
var modalDestination: Destination?
var pushDestination: Destination?

// Old: Multiple navigation calls
navigationCoordinator.navigate(to: .detail)
navigationCoordinator.presentModal(.settings)
```

### To New Pattern

```swift
// New: Single destination in state
struct State: ViewModelState {
    var destination: Destination? = nil
    // ...
}

// New: Just set state
state.destination = .detail  // Presentation style determines how it's shown
state.destination = .settings
```

## Advanced Patterns

### Nested Navigation

For complex navigation hierarchies, destinations can contain child states:

```swift
@CasePathable
enum Destination: RouteDestination {
    case productList(ProductListState)
    case checkout(CheckoutState)

    var presentationStyle: PresentationStyle {
        // ...
    }
}

// Child state can have its own destination
struct CheckoutState: ViewModelState {
    var destination: CheckoutDestination?

    enum CheckoutDestination: RouteDestination {
        case payment(PaymentState)
        case confirmation
    }
}
```

### Conditional Navigation

Navigation logic can depend on state:

```swift
func showDetail(for product: Product) {
    guard state.isAuthenticated else {
        state.destination = .login
        return
    }

    state.destination = .detail(product)
}
```

### Navigation Guards

Prevent navigation based on conditions:

```swift
func navigateToCheckout() {
    guard !state.cart.isEmpty else {
        state.destination = .alert(.emptyCart)
        return
    }

    guard state.hasShippingAddress else {
        state.destination = .addAddress
        return
    }

    state.destination = .checkout
}
```

## Best Practices

### 1. Always Define Presentation Style

```swift
enum Destination: RouteDestination {
    case detail

    var presentationStyle: PresentationStyle {
        switch self {
        case .detail: return .push  // ✅ Always specify
        }
    }
}
```

### 2. Use Connections for Child ViewModels

```swift
// ✅ Good: Use connection pattern
lazy var detail = Connection<DetailVM> { ... }
    .connect(state: \.destination, case: \.detail)

// ❌ Avoid: Manual ViewModel management
```

### 3. Clear Destination to Dismiss

```swift
// ✅ Good: Explicit dismissal
state.destination = nil

// ❌ Avoid: Calling separate dismiss methods
```

### 4. Make Destinations Equatable

```swift
@CasePathable
enum Destination: RouteDestination, Equatable {  // ✅ Add Equatable
    case detail(String)
}
```

This enables SwiftUI to properly detect changes and animate transitions.

## Troubleshooting

### Destination Not Showing

**Problem:** Setting `state.destination` but nothing happens

**Solution:**
- Check that presentation style is correct
- Ensure you're using the right binding (`.sheet(item: $viewModel.modalDestination)` for modals)
- Verify destination enum conforms to `RouteDestination`

### Wrong Presentation Style

**Problem:** Destination shows as sheet instead of push

**Solution:** Check the `presentationStyle` property:

```swift
var presentationStyle: PresentationStyle {
    switch self {
    case .detail: return .push  // For NavigationStack
    case .settings: return .modal  // For .sheet()
    }
}
```

### Binding Not Updating

**Problem:** SwiftUI binding doesn't reflect destination changes

**Solution:**
- Ensure State conforms to Equatable
- Make sure you're using `@StateObject` for the ViewModel
- Check that destination enum cases are Equatable

## See Also

- [Connections-Case-Based.md](./Connections-Case-Based.md) - Using Connections with state-based navigation
- [NavigationCoordinatable.swift](../Sources/RWLabsArchitecture/Architecture/Navigation/NavigationCoordinatable.swift) - Protocol implementation
- [ViewModelProtocol.swift](../Sources/RWLabsArchitecture/Architecture/Core/ViewModelProtocol.swift) - ViewModelState protocol
