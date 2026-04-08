//
//  ComponentView.swift
//  RWLabsArchitecture
//
//  Type alias and future extensions for component-based views
//  Combines BaseView and Navigatable protocols for full-featured components
//

import SwiftUI

// MARK: - ComponentView Type Alias

/// Type alias for views that combine BaseView and Navigatable protocols
///
/// `ComponentView` represents a fully-featured component that:
/// - Manages state through a ViewModel (`BaseView`)
/// - Handles navigation (`Navigatable`)
///
/// # Architecture
///
/// ```
/// ComponentView = BaseView & Navigatable
///     │
///     ├─ BaseView
///     │   ├─ associatedtype VM: ViewModel
///     │   ├─ var model: VM
///     │   ├─ var content: Content
///     │   └─ Automatic .onAppear() handling
///     │
///     └─ Navigatable
///         ├─ associatedtype VM: ViewModel & NavigationCoordinatable
///         ├─ var navigator: SwiftUINavigator<VM.D>
///         ├─ func destinationView(for:) -> DestinationView
///         └─ NavigationStack with push/modal/alert support
/// ```
///
/// # Usage
///
/// ## Basic Component with Navigation
/// ```swift
/// struct ProductListView: ComponentView {
///     typealias VM = ProductListViewModel
///
///     @StateObject var model: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         List(model.products, id: \.id) { product in
///             ProductRow(product: product)
///                 .onTapGesture {
///                     model.send(.productTapped(product))
///                 }
///         }
///         .navigationTitle("Products")
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .productDetail(let product):
///             ProductDetailView(
///                 model: model.connections.createProductDetail(product),
///                 navigator: navigator
///             )
///         }
///     }
/// }
/// ```
///
/// ## With State and Actions
/// ```swift
/// struct CheckoutView: ComponentView {
///     typealias VM = CheckoutViewModel
///
///     @StateObject var model: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         VStack(spacing: 16) {
///             // Cart items
///             ForEach(model.cartItems) { item in
///                 CartItemRow(item: item)
///             }
///
///             // Total
///             HStack {
///                 Text("Total:")
///                 Spacer()
///                 Text("$\(model.total, specifier: "%.2f")")
///             }
///             .font(.headline)
///
///             // Checkout button
///             Button("Proceed to Payment") {
///                 model.send(.checkoutTapped)
///             }
///             .disabled(model.cartItems.isEmpty)
///
///             if model.isLoading {
///                 ProgressView()
///             }
///         }
///         .padding()
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .payment:
///             PaymentView(
///                 model: model.connections.paymentViewModel,
///                 navigator: navigator
///             )
///
///         case .orderConfirmation(let orderId):
///             OrderConfirmationView(
///                 model: model.connections.createOrderConfirmation(orderId),
///                 navigator: navigator
///             )
///         }
///     }
/// }
/// ```
///
/// # What ComponentView Provides
///
/// ## From BaseView:
/// - **ViewModel Integration**: Automatic `model` property
/// - **Content Separation**: Clean separation of content from navigation
/// - **Lifecycle Handling**: Automatic `onAppear()` call
/// - **Type Safety**: Generic over ViewModel type
///
/// ## From Navigatable:
/// - **NavigationStack**: Built-in NavigationStack wrapper
/// - **Push Navigation**: `.navigationDestination` handling
/// - **Modal Presentation**: `.sheet` support
/// - **Alerts**: `.alert` integration
/// - **Coordinator Integration**: Automatic coordinator setup
///
/// # Complete Example
///
/// ```swift
/// // MARK: - State/Action/Destination
///
/// struct ProductListState: ViewModelState {
///     var products: [Product] = []
///     var isLoading: Bool = false
///     var error: Error? = nil
/// }
///
/// enum ProductListAction: ViewModelAction {
///     case viewDidAppear
///     case productTapped(Product)
///     case refreshTapped
/// }
///
/// enum ProductListDestination: RouteDestination {
///     case productDetail(Product)
///     case cart
///
///     var id: String {
///         switch self {
///         case .productDetail(let product): return "detail_\(product.id)"
///         case .cart: return "cart"
///         }
///     }
///
///     var presentationStyle: PresentationStyle {
///         switch self {
///         case .productDetail: return .push
///         case .cart: return .modal
///         }
///     }
/// }
///
/// // MARK: - ViewModel
///
/// class ProductListViewModel: BaseViewModel<State, Action, Output, Destination> {
///     typealias State = ProductListState
///     typealias Action = ProductListAction
///     typealias Output = ProductListOutput
///     typealias D = ProductListDestination
///
///     @Injected var productRepository: ProductRepository
///
///     lazy var connections: Connections = {
///         Connections(parent: self)
///     }()
///
///     init(initialState: State = State()) {
///         super.init(initialState: initialState)
///     }
///
///     override func send(_ action: Action) {
///         switch action {
///         case .viewDidAppear:
///             Task { await loadProducts() }
///
///         case .productTapped(let product):
///             navigate(to: .productDetail(product))
///
///         case .refreshTapped:
///             Task { await loadProducts() }
///         }
///     }
///
///     private func loadProducts() async {
///         state.isLoading = true
///         do {
///             let products = try await productRepository.fetchAll()
///             state.products = products
///             state.isLoading = false
///         } catch {
///             state.error = error
///             state.isLoading = false
///         }
///     }
///
///     class Connections: BaseConnections<ProductListViewModel> {
///         func createProductDetail(_ product: Product) -> ProductDetailViewModel {
///             let vm = ProductDetailViewModel(initialState: .init(product: product))
///             vm.onOutput { [weak parent] output in
///                 parent?.handleDetailOutput(output)
///             }
///             return vm
///         }
///     }
/// }
///
/// // MARK: - View
///
/// struct ProductListView: ComponentView {
///     typealias VM = ProductListViewModel
///
///     @StateObject var model: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         List {
///             ForEach(model.products, id: \.id) { product in
///                 ProductRow(product: product)
///                     .onTapGesture {
///                         model.send(.productTapped(product))
///                     }
///             }
///         }
///         .navigationTitle("Products")
///         .toolbar {
///             ToolbarItem(placement: .navigationBarTrailing) {
///                 Button("Cart") {
///                     model.navigate(to: .cart)
///                 }
///             }
///         }
///         .refreshable {
///             model.send(.refreshTapped)
///         }
///         .overlay {
///             if model.isLoading {
///                 ProgressView()
///             }
///         }
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .productDetail(let product):
///             ProductDetailView(
///                 model: model.connections.createProductDetail(product),
///                 navigator: navigator
///             )
///
///         case .cart:
///             CartView(
///                 model: model.connections.cartViewModel,
///                 navigator: navigator
///             )
///         }
///     }
/// }
/// ```
///
/// # Benefits
///
/// 1. **Unified Pattern**: Single protocol for all stateful, navigable views
/// 2. **Reduced Boilerplate**: Automatic navigation and lifecycle handling
/// 3. **Type Safety**: Compile-time checking of destinations and ViewModels
/// 4. **Testability**: Easy to test with mock navigators and ViewModels
/// 5. **Consistency**: Enforces architectural patterns across the app
///
/// # When to Use
///
/// - **Screens with Navigation**: Any view that needs to navigate to other screens
/// - **ViewModel-Driven Views**: Views managed by ViewModels with State/Action pattern
/// - **Feature Modules**: Top-level views in feature flows
/// - **Coordinator Pattern**: Views that participate in coordinated navigation
///
/// # When NOT to Use
///
/// - **Stateless Components**: Use `StatelessComponentView` instead
/// - **Leaf Views**: Views that never navigate elsewhere (use plain `View`)
/// - **Simple Dialogs**: Views shown only as alerts/sheets without navigation
/// - **Reusable Components**: Generic UI components (buttons, labels, etc.)
public protocol RoutableView: BaseView {}
public protocol ComponentView: BaseView {}

public protocol Destinatationable: BaseView {
    /// The destination view type returned by `destinationView(for:)`
    associatedtype DestinationView: View

    /// The ViewModel type (must support navigation coordination)
//    associatedtype VM: ViewModel & NavxigationCoordinatable

    /// Creates the view for a given destination
    ///
    /// Called by NavigationStack when navigating to a destination.
    /// Should create and configure the destination view with its ViewModel.
    ///
    /// - Parameter destination: The destination to navigate to
    /// - Returns: The view to display for this destination
    ///
    /// # Example
    /// ```swift
    /// func destinationView(for destination: VM.D) -> some View {
    ///     switch destination {
    ///     case .detail(let id):
    ///         DetailView(
    ///             model: model.connections.createDetail(id),
    ///             navigator: navigator
    ///         )
    ///     }
    /// }
    /// ```
    func destinationView(for destination: VM.State.Destination) -> DestinationView
}

// MARK: - Navigatable Body Implementation

public extension ComponentView where Self: Destinatationable   {
    var body: some View {
        content
            .onAppear {
                model.onAppear()
            }
//            .showDestination(dest: model.destination, destView: { dest in
//                destinationView(for: dest)
//            })
//            .navigationDestination(for: VM.State.Destination.self) { destination in
//                destinationView(for: destination)
//                    .environmentObject(navigator)
//            }
            
        
    }
    

}

extension View {
    public func showDestination<D:RouteDestinationPresentable>(dest: Binding<D?>,  destView: @escaping (D) -> some View) -> AnyView {
        switch dest.wrappedValue?.presentationStyle {
            case .push:
                AnyView(self
                    .navigationDestination(item: dest) { dest in
                        destView(dest)
//                        destinationView(for: dest)
                    })
//                    .anyView()
            case .customAlert:
                AnyView(self
                    .customAlert(isPresented: dest.isPresent()) {
                        if let dest = dest.wrappedValue {
                            destView(dest)
                        }
                    }
                )
            default:
            AnyView(
                self
                    .sheet(item: dest) { dest in
                        destView(dest)
                    }
                )
        }
    }
    
    func anyView() {
        AnyView(self)
    }
}
extension Binding {
  /// Creates a binding by projecting the current optional value to a boolean describing if it's
  /// non-`nil`.
  ///
  /// Writing `false` to the binding will `nil` out the base value. Writing `true` does nothing.
  ///
  /// - Returns: A binding to a boolean. Returns `true` if non-`nil`, otherwise `false`.
  public func isPresent<Wrapped>() -> Binding<Bool>
  where Value == Wrapped? {
    self._isPresent
  }
}

extension Optional {
  fileprivate var _isPresent: Bool {
    get { self != nil }
    set {
      guard !newValue else { return }
      self = nil
    }
  }
}

public extension RoutableView {
    /// Body implementation providing NavigationStack with routing
    ///
    /// This implementation:
    /// 1. Wraps content in NavigationStack
    /// 2. Binds to navigator's path for navigation state
    /// 3. Calls `model.onAppear()` and `model.setCoordinator()`
    /// 4. Configures `.navigationDestination` for push navigation
    /// 5. Configures `.sheet` for modal presentation
    /// 6. Configures `.alert` for alert presentation
    ///
    /// # Navigation Bindings
    ///
    /// - **Path**: Bound to navigator's path for push navigation
    /// - **Modal**: Bound to model's modalDestination for sheets
    /// - **Alert**: Bound to model's alertDestination for alerts
    ///
    /// # Lifecycle
    ///
    /// On view appear:
    /// 1. `model.onAppear()` - Initialize data, analytics, etc.
    /// 2. `model.setCoordinator()` - Connect ViewModel to navigation
    ///
    /// # Example Flow
    ///
    /// ```
    /// View appears
    ///     ↓
    /// NavigationStack created with path binding
    ///     ↓
    /// content rendered
    ///     ↓
    /// .onAppear fires
    ///     ↓
    /// model.onAppear() called
    /// model.setCoordinator() called
    ///     ↓
    /// User taps → navigate(to:)
    ///     ↓
    /// Path updates
    ///     ↓
    /// .navigationDestination fires
    ///     ↓
    /// destinationView(for:) called
    ///     ↓
    /// New view pushed
    /// ```
    @MainActor
    var body: some View {
        NavigationStack {
            content
                .onAppear {
                    model.onAppear()
                }
        }
    }
}

// MARK: - Architecture Notes

/*
 # Design Rationale

 ## Protocol Composition

 Navigatable is designed to compose with BaseView:

 ```swift
 BaseView alone:
 - ViewModel integration
 - Content separation
 - Lifecycle (onAppear)

 Navigatable alone:
 - Navigator integration
 - Destination routing
 (Can't work without BaseView - needs content)

 BaseView + Navigatable (ComponentView):
 - Full-featured component
 - ViewModel + Navigation
 - Complete lifecycle + routing
 ```

 ## Type-Safe Routing

 By requiring `destinationView(for:)` to switch on enum destinations,
 we ensure:
 - Compile-time checking of all routes
 - No typos or invalid string paths
 - Exhaustive handling of destinations
 - Clear documentation of navigation graph

 ## Navigator Passing

 The navigator is passed explicitly (not injected) to:
 - Make navigation dependencies visible
 - Enable testing with mock navigators
 - Allow multiple navigators in complex hierarchies
 - Clarify which view controls which routes

 ## Coordinator Integration

 The automatic `setCoordinator()` call connects the ViewModel to
 navigation capabilities, enabling:
 - model.navigate(to:)
 - model.dismiss()
 - model.popToRoot()
 - Programmatic navigation from ViewModels

 ## Body Override

 When a view conforms to both BaseView and Navigatable, this body
 implementation takes precedence over BaseView's default body.

 This is intentional - navigation wrapping should be the outermost layer:
 ```
 NavigationStack
     └─ content
         └─ .onAppear { model.onAppear() }
 ```

 Not:
 ```
 content
     └─ .onAppear { model.onAppear() }
         └─ NavigationStack (wrong!)
 ```

 ## Presentation Styles

 The three presentation types (push, modal, alert) cover all
 common navigation patterns:

 - **Push** (.navigationDestination): Hierarchical navigation
 - **Modal** (.sheet): Temporary tasks, forms, detail views
 - **Alert** (.alert): Confirmations, errors, simple choices

 Each has its own SwiftUI modifier and binding.
 */


// MARK: - Future Extensions

/*
 # Potential Future Additions

 As the architecture evolves, this file may include:

 ## 1. Common View Modifiers
 ```swift
 extension ComponentView {
     func withLoadingOverlay() -> some View {
         overlay {
             if model.isLoading {
                 ProgressView()
             }
         }
     }

     func withErrorHandling() -> some View {
         alert("Error", isPresented: .constant(model.error != nil)) {
             Button("OK") { }
         } message: {
             Text(model.error?.localizedDescription ?? "")
         }
     }
 }
 ```

 ## 2. Analytics Integration
 ```swift
 extension ComponentView {
     func trackScreenView() -> some View {
         onAppear {
             Analytics.shared.trackScreen(String(describing: Self.self))
         }
     }
 }
 ```

 ## 3. Testing Helpers
 ```swift
 #if DEBUG
 extension ComponentView {
     static func preview(
         state: VM.State,
         navigator: SwiftUINavigator<VM.D>? = nil
     ) -> some View {
         // Generate preview with mock data
     }
 }
 #endif
 ```

 ## 4. Accessibility Enhancements
 ```swift
 extension ComponentView {
     func withAccessibilityHints() -> some View {
         // Add automatic accessibility hints
     }
 }
 ```

 ## 5. Performance Monitoring
 ```swift
 extension ComponentView {
     func monitorPerformance() -> some View {
         // Track view render times, memory usage, etc.
     }
 }
 ```
 */
