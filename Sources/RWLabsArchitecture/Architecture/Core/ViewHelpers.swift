//
//  ViewHelpers.swift
//  RWLabsArchitecture
//
//  Helper extensions and utilities for SwiftUI views
//  Provides view extensions for ViewModel integration and output handling
//

import SwiftUI
import Combine

// MARK: - ComponentView Protocol (Commented Out)

/// A view protocol that enforces ViewModel-driven architecture with State/Action/Output pattern
///
/// **Note**: This protocol is commented out in favor of direct View + ViewModel composition,
/// which provides more flexibility and better SwiftUI integration.
///
/// # Alternative Pattern (Recommended)
///
/// Instead of conforming to ComponentView, directly use ViewModels in SwiftUI views:
///
/// ```swift
/// struct ProductListView: View {
///     @StateObject var model: ProductListViewModel
///
///     var body: some View {
///         // View implementation
///     }
/// }
/// ```
///
/// # Why Not ComponentView Protocol?
///
/// - **SwiftUI Compatibility**: Protocol requirements conflict with SwiftUI's body property
/// - **Flexibility**: Direct composition allows easier customization
/// - **Preview Support**: Simpler previews without protocol conformance
/// - **Type Erasure**: Avoids complex associated type constraints
///
/// The helper extensions below provide the same benefits without protocol constraints.
//
//public protocol ComponentView: View {
//    /// The ViewModel type that manages this component's state
//    associatedtype ViewModelType: ViewModel
//
//    /// The ViewModel instance
//    var model: ViewModelType { get }
//
//    /// The main body of the component (required by View protocol)
//    var body: Self.Body { get }
//}

// MARK: - View Extensions for ComponentView

/// Helper extensions for working with ViewModels and outputs in SwiftUI views
///
/// These extensions provide convenient methods for subscribing to ViewModel outputs
/// without requiring protocol conformance.

public extension View {
    /// Subscribe to a publisher with a handler (convenience for model.outputs)
    ///
    /// Provides syntactic sugar for observing ViewModel output streams
    /// in SwiftUI views.
    ///
    /// # Usage
    ///
    /// ## Basic Output Handling
    /// ```swift
    /// struct ProductListView: View {
    ///     @StateObject var model: ProductListViewModel
    ///
    ///     var body: some View {
    ///         List(model.products, id: \.id) { product in
    ///             ProductRow(product: product)
    ///         }
    ///         .onOutput(model.outputs) { output in
    ///             handleOutput(output)
    ///         }
    ///     }
    ///
    ///     func handleOutput(_ output: ProductListViewModel.Output) {
    ///         switch output {
    ///         case .navigateToDetail(let product):
    ///             // Navigate to product detail
    ///         case .showError(let message):
    ///             // Show error alert
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// ## Inline Handling
    /// ```swift
    /// var body: some View {
    ///     ContentView()
    ///         .onOutput(model.outputs) { output in
    ///             switch output {
    ///             case .success:
    ///                 showSuccessMessage()
    ///             case .failure(let error):
    ///                 showError(error)
    ///             }
    ///         }
    /// }
    /// ```
    ///
    /// ## Multiple Outputs
    /// ```swift
    /// var body: some View {
    ///     VStack {
    ///         HeaderView()
    ///             .onOutput(headerViewModel.outputs) { output in
    ///                 handleHeaderOutput(output)
    ///             }
    ///
    ///         ContentView()
    ///             .onOutput(contentViewModel.outputs) { output in
    ///                 handleContentOutput(output)
    ///             }
    ///     }
    /// }
    /// ```
    ///
    /// # Comparison with onReceive
    ///
    /// This method is equivalent to SwiftUI's `onReceive` but with a more
    /// descriptive name for ViewModel output handling:
    ///
    /// ```swift
    /// // Using onOutput (clearer intent)
    /// .onOutput(model.outputs) { output in
    ///     handleOutput(output)
    /// }
    ///
    /// // Using onReceive (same behavior)
    /// .onReceive(model.outputs) { output in
    ///     handleOutput(output)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - publisher: The publisher to subscribe to (typically `model.outputs`)
    ///   - handler: Closure called for each published value
    /// - Returns: Modified view with output subscription
    func onOutput<Output>(_ publisher: AnyPublisher<Output, Never>, perform handler: @escaping (Output) -> Void) -> some View {
        self.onReceive(publisher, perform: handler)
    }
}

// MARK: - Stateless Component

/// Protocol for components that don't need state management
///
/// Use this for pure presentational components that receive all data
/// via parameters and don't manage any internal state.
///
/// # Usage
///
/// ## Simple Stateless Component
/// ```swift
/// struct UserAvatarView: StatelessComponentView {
///     let imageURL: URL?
///     let size: CGFloat
///
///     var body: some View {
///         AsyncImage(url: imageURL) { image in
///             image
///                 .resizable()
///                 .scaledToFill()
///         } placeholder: {
///             ProgressView()
///         }
///         .frame(width: size, height: size)
///         .clipShape(Circle())
///     }
/// }
/// ```
///
/// ## Computed Stateless Component
/// ```swift
/// struct PriceLabel: StatelessComponentView {
///     let price: Decimal
///     let currency: String
///
///     var formattedPrice: String {
///         let formatter = NumberFormatter()
///         formatter.numberStyle = .currency
///         formatter.currencyCode = currency
///         return formatter.string(from: price as NSNumber) ?? ""
///     }
///
///     var body: some View {
///         Text(formattedPrice)
///             .font(.headline)
///             .foregroundColor(.primary)
///     }
/// }
/// ```
///
/// ## Styled Stateless Component
/// ```swift
/// struct BadgeView: StatelessComponentView {
///     let text: String
///     let color: Color
///
///     var body: some View {
///         Text(text)
///             .font(.caption)
///             .padding(.horizontal, 8)
///             .padding(.vertical, 4)
///             .background(color.opacity(0.2))
///             .foregroundColor(color)
///             .cornerRadius(4)
///     }
/// }
/// ```
///
/// # When to Use
/// - **Pure UI Components**: Display-only components with no business logic
/// - **Reusable Elements**: Buttons, badges, labels, avatars
/// - **Styled Wrappers**: Custom styled versions of standard views
/// - **Presentational Components**: Components that only receive props
///
/// # When NOT to Use
/// - Components that manage state → Use regular `View` with ViewModel
/// - Components with user interactions → Use ViewModel for action handling
/// - Components that fetch data → Use ViewModel for data management
/// - Components with complex logic → Use ViewModel pattern
///
/// # Note
/// This protocol is largely ceremonial. In practice, any SwiftUI `View`
/// can be used as a stateless component. This protocol simply communicates
/// intent and can help with code organization.
public protocol StatelessComponentView: View {
    /// The view body (required by View protocol)
    var body: Self.Body { get }
}

// MARK: - Architecture Pattern Documentation

/*
 # Component View Architecture

 This file provides helper utilities for integrating ViewModels with SwiftUI views
 using the State/Action/Output pattern.

 ## Pattern Overview

 Instead of using protocol conformance, this architecture encourages direct
 composition of ViewModels with SwiftUI views:

 ```
 SwiftUI View
     ├── @StateObject var model
     ├── body (observes model.state)
     ├── send actions → model.send(action)
     └── receive outputs → .onOutput(model.outputs)
 ```

 ## Complete Example

 ```swift
 // MARK: - State/Action/Output

 struct ProductListState: ViewModelState {
     var products: [Product] = []
     var isLoading: Bool = false
     var error: Error? = nil
     var selectedProduct: Product?
 }

 enum ProductListAction: ViewModelAction {
     case viewDidAppear
     case refreshTapped
     case productTapped(Product)
     case searchQueryChanged(String)
 }

 enum ProductListOutput: ViewModelOutput {
     case navigateToDetail(Product)
     case showError(String)
     case showSuccessMessage(String)
 }

 // MARK: - ViewModel

 class ProductListViewModel: ViewModel {
     typealias State = ProductListState
     typealias Action = ProductListAction
     typealias Output = ProductListOutput

     @Published var state: State
     let id = UUID()

     @Injected var productRepository: ProductRepository
     private let outputSubject = PassthroughSubject<Output, Never>()
     private var cancellables = Set<AnyCancellable>()

     var outputs: AnyPublisher<Output, Never> {
         outputSubject.eraseToAnyPublisher()
     }

     required init(initialState: State = State()) {
         self.state = initialState
     }

     func send(_ action: Action) {
         switch action {
         case .viewDidAppear:
             Task { await loadProducts() }

         case .refreshTapped:
             Task { await loadProducts() }

         case .productTapped(let product):
             state.selectedProduct = product
             outputSubject.send(.navigateToDetail(product))

         case .searchQueryChanged(let query):
             Task { await searchProducts(query: query) }
         }
     }

     func onAppear() {
         send(.viewDidAppear)
     }

     @discardableResult
     func onOutput(_ handler: @escaping (Output) -> Void) -> Self {
         outputSubject.sink(receiveValue: handler)
             .store(in: &cancellables)
         return self
     }

     private func loadProducts() async {
         state.isLoading = true
         state.error = nil

         do {
             let products = try await productRepository.fetchAll()
             state.products = products
             state.isLoading = false
         } catch {
             state.isLoading = false
             state.error = error
             outputSubject.send(.showError(error.localizedDescription))
         }
     }

     private func searchProducts(query: String) async {
         guard !query.isEmpty else {
             await loadProducts()
             return
         }

         state.isLoading = true
         // Perform search...
         state.isLoading = false
     }
 }

 // MARK: - View

 struct ProductListView: View {
     @StateObject var model: ProductListViewModel
     @State private var showingAlert = false
     @State private var alertMessage = ""

     var body: some View {
         NavigationView {
             ZStack {
                 if model.isLoading {
                     ProgressView()
                 } else {
                     productList
                 }
             }
             .navigationTitle("Products")
             .toolbar {
                 ToolbarItem(placement: .navigationBarTrailing) {
                     Button("Refresh") {
                         model.send(.refreshTapped)
                     }
                 }
             }
         }
         .onAppear {
             model.onAppear()
         }
         .onOutput(model.outputs) { output in
             handleOutput(output)
         }
         .alert("Error", isPresented: $showingAlert) {
             Button("OK") { }
         } message: {
             Text(alertMessage)
         }
     }

     private var productList: some View {
         List(model.products, id: \.id) { product in
             ProductRow(product: product)
                 .onTapGesture {
                     model.send(.productTapped(product))
                 }
         }
     }

     private func handleOutput(_ output: ProductListViewModel.Output) {
         switch output {
         case .navigateToDetail(let product):
             // Navigate to detail view
             print("Navigate to \(product.name)")

         case .showError(let message):
             alertMessage = message
             showingAlert = true

         case .showSuccessMessage(let message):
             print("Success: \(message)")
         }
     }
 }

 // MARK: - Stateless Component Example

 struct ProductRow: StatelessComponentView {
     let product: Product

     var body: some View {
         HStack {
             AsyncImage(url: product.imageURL) { image in
                 image
                     .resizable()
                     .scaledToFill()
             } placeholder: {
                 Color.gray
             }
             .frame(width: 60, height: 60)
             .cornerRadius(8)

             VStack(alignment: .leading, spacing: 4) {
                 Text(product.name)
                     .font(.headline)

                 Text(product.description)
                     .font(.subheadline)
                     .foregroundColor(.secondary)
                     .lineLimit(2)

                 Text("$\(product.price, specifier: "%.2f")")
                     .font(.subheadline)
                     .foregroundColor(.primary)
             }

             Spacer()
         }
         .padding(.vertical, 8)
     }
 }

 // MARK: - Preview

 #Preview {
     ProductListView(
         model: ProductListViewModel(
             initialState: ProductListState(
                 products: [
                     Product(id: 1, name: "iPhone", description: "Latest model", price: 999.99, imageURL: nil),
                     Product(id: 2, name: "MacBook", description: "Pro version", price: 1999.99, imageURL: nil)
                 ],
                 isLoading: false,
                 error: nil
             )
         )
     )
 }
 ```

 ## Benefits of This Approach

 1. **No Protocol Overhead**: Direct ViewModel composition without protocol constraints
 2. **SwiftUI Integration**: Works naturally with SwiftUI's property wrappers
 3. **Preview Support**: Easy to create previews with mock state
 4. **Type Safety**: Full type checking at compile time
 5. **Flexibility**: Can mix stateful and stateless components freely
 6. **Clarity**: Clear separation between state, actions, and outputs

 ## Best Practices

 ### 1. State Management
 - Keep state in ViewModel, not in View
 - Use `@State` only for purely UI-related state (sheet presentation, etc.)
 - Derive computed values in State struct when possible

 ### 2. Action Handling
 - Always use `send(_:)` to communicate user intent
 - Don't directly mutate ViewModel state from the View
 - Keep action names descriptive and past-tense

 ### 3. Output Handling
 - Use outputs for one-time side effects (navigation, alerts)
 - Don't use outputs for state that should be in State
 - Handle outputs in a centralized location in the View

 ### 4. Component Composition
 - Break down complex views into smaller stateless components
 - Use ViewModel only for components that need state management
 - Pass data down, send actions up

 ### 5. Testing
 - Test ViewModel logic independently of Views
 - Create snapshots of State for testing
 - Mock outputs for testing side effects
 */
