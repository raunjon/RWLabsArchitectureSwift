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
///     │   ├─ var viewModel: VM
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
///     @StateObject var viewModel: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         List(viewModel.products, id: \.id) { product in
///             ProductRow(product: product)
///                 .onTapGesture {
///                     viewModel.send(.productTapped(product))
///                 }
///         }
///         .navigationTitle("Products")
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .productDetail(let product):
///             ProductDetailView(
///                 viewModel: viewModel.connections.createProductDetail(product),
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
///     @StateObject var viewModel: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         VStack(spacing: 16) {
///             // Cart items
///             ForEach(viewModel.cartItems) { item in
///                 CartItemRow(item: item)
///             }
///
///             // Total
///             HStack {
///                 Text("Total:")
///                 Spacer()
///                 Text("$\(viewModel.total, specifier: "%.2f")")
///             }
///             .font(.headline)
///
///             // Checkout button
///             Button("Proceed to Payment") {
///                 viewModel.send(.checkoutTapped)
///             }
///             .disabled(viewModel.cartItems.isEmpty)
///
///             if viewModel.isLoading {
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
///                 viewModel: viewModel.connections.paymentViewModel,
///                 navigator: navigator
///             )
///
///         case .orderConfirmation(let orderId):
///             OrderConfirmationView(
///                 viewModel: viewModel.connections.createOrderConfirmation(orderId),
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
/// - **ViewModel Integration**: Automatic `viewModel` property
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
///     @StateObject var viewModel: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         List {
///             ForEach(viewModel.products, id: \.id) { product in
///                 ProductRow(product: product)
///                     .onTapGesture {
///                         viewModel.send(.productTapped(product))
///                     }
///             }
///         }
///         .navigationTitle("Products")
///         .toolbar {
///             ToolbarItem(placement: .navigationBarTrailing) {
///                 Button("Cart") {
///                     viewModel.navigate(to: .cart)
///                 }
///             }
///         }
///         .refreshable {
///             viewModel.send(.refreshTapped)
///         }
///         .overlay {
///             if viewModel.isLoading {
///                 ProgressView()
///             }
///         }
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .productDetail(let product):
///             ProductDetailView(
///                 viewModel: viewModel.connections.createProductDetail(product),
///                 navigator: navigator
///             )
///
///         case .cart:
///             CartView(
///                 viewModel: viewModel.connections.cartViewModel,
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
public protocol RoutableView: BaseView, Navigatable, Destinatationable {}
public protocol ComponentView: BaseView {
    var title: String {get}
}

// MARK: - Future Extensions

/*
 # Potential Future Additions

 As the architecture evolves, this file may include:

 ## 1. Common View Modifiers
 ```swift
 extension ComponentView {
     func withLoadingOverlay() -> some View {
         overlay {
             if viewModel.isLoading {
                 ProgressView()
             }
         }
     }

     func withErrorHandling() -> some View {
         alert("Error", isPresented: .constant(viewModel.error != nil)) {
             Button("OK") { }
         } message: {
             Text(viewModel.error?.localizedDescription ?? "")
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
