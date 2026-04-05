//
//  ViewModelProtocol.swift
//  RWLabsArchitecture
//
//  Core ViewModel protocols defining the State/Action/Output pattern
//  Provides protocol-oriented foundation for reactive ViewModels
//

import Foundation
import Combine
import SwiftUI

// MARK: - ViewModelState Protocol

/// Base protocol for all ViewModel state types
///
/// Conforming types encapsulate all view-displayable state in a single struct,
/// enabling snapshot testing, time-travel debugging, and predictable UI updates.
///
/// # Usage
///
/// ## Basic State
/// ```swift
/// struct ProductListState: ViewModelState {
///     var products: [Product] = []
///     var isLoading: Bool = false
///     var error: Error? = nil
/// }
/// ```
///
/// ## Complex State
/// ```swift
/// struct CheckoutState: ViewModelState {
///     var items: [CartItem] = []
///     var subtotal: Decimal = 0
///     var tax: Decimal = 0
///     var total: Decimal = 0
///     var shippingAddress: Address?
///     var paymentMethod: PaymentMethod?
///     var isLoading: Bool = false
///     var error: Error? = nil
///     var validationErrors: [String: String] = [:]
/// }
/// ```
///
/// # Key Features
/// - **Value Semantics**: Struct-based for immutability and copy-on-write
/// - **Loading State**: Standard `isLoading` for UI feedback
/// - **Error Handling**: Standard `error` property for error display
/// - **Testable**: Easy to create state snapshots for testing
///
/// # Requirements
/// - Must be a value type (struct preferred)
/// - Must include `isLoading: Bool`
/// - Must include `error: Error?`
/// - Must include `destination: Destination?` where Destination conforms to RouteDestination
public protocol ViewModelState: Hashable {
    /// The destination type for navigation
    associatedtype Destination: Identifiable

    /// Indicates whether an async operation is in progress
    var isLoading: Bool { get set }

    /// The current error, if any
    var error: Error? { get set }

    /// The current navigation destination
    var destination: Destination? { get set }
}

extension ViewModelState {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.destination?.id == rhs.destination?.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.destination?.id)
    }
}

// MARK: - ViewModelAction Protocol

/// Base protocol for ViewModel actions
///
/// Actions represent user intent or system events that trigger state changes.
/// Typically implemented as an enum for exhaustive switching and type safety.
///
/// # Usage
///
/// ## User Actions
/// ```swift
/// enum LoginAction: ViewModelAction {
///     case emailChanged(String)
///     case passwordChanged(String)
///     case loginTapped
///     case forgotPasswordTapped
///     case signUpTapped
/// }
/// ```
///
/// ## Combined Actions
/// ```swift
/// enum ProductDetailAction: ViewModelAction {
///     // User actions
///     case viewDidAppear
///     case addToCartTapped
///     case favoriteToggled
///     case quantityChanged(Int)
///
///     // System actions
///     case productLoaded(Product)
///     case loadFailed(Error)
/// }
/// ```
///
/// # Best Practices
/// - Use descriptive past-tense names for events (e.g., `userTapped`, not `tapUser`)
/// - Group related actions with associated values
/// - Keep actions atomic and focused
/// - Don't include complex logic in action names
public protocol ViewModelAction {}

// MARK: - ViewModelOutput Protocol

/// Base protocol for ViewModel outputs (side effects)
///
/// Outputs represent side effects that shouldn't be part of state,
/// such as navigation, alerts, haptic feedback, or analytics events.
///
/// # Usage
///
/// ## Navigation Outputs
/// ```swift
/// enum LoginOutput: ViewModelOutput {
///     case navigateToHome
///     case navigateToSignUp
///     case navigateToForgotPassword
/// }
/// ```
///
/// ## UI Feedback Outputs
/// ```swift
/// enum FormOutput: ViewModelOutput {
///     case showSuccess(message: String)
///     case showError(message: String)
///     case triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle)
///     case dismissKeyboard
/// }
/// ```
///
/// ## Mixed Outputs
/// ```swift
/// enum CheckoutOutput: ViewModelOutput {
///     // Navigation
///     case navigateToPayment
///     case navigateToOrderConfirmation(orderId: String)
///
///     // UI
///     case showAlert(title: String, message: String)
///     case copyToClipboard(text: String)
///
///     // Analytics
///     case trackCheckoutStarted
///     case trackPurchaseCompleted(amount: Decimal)
/// }
/// ```
///
/// # Outputs vs State
/// **Use State for**:
/// - Data displayed in the UI
/// - Loading/error states
/// - User selections
/// - Form values
///
/// **Use Output for**:
/// - Navigation
/// - One-time alerts/toasts
/// - Analytics tracking
/// - Haptic feedback
/// - Clipboard operations
/// - Deep linking
public protocol ViewModelOutput {}

// MARK: - ViewModel Protocol

/// Core protocol for all ViewModels using State/Action/Output pattern
///
/// `ViewModel` provides a unified interface for reactive ViewModels,
/// enforcing separation of concerns through distinct State, Action, and Output types.
///
/// # Architecture Pattern
///
/// ```
/// View ──send(Action)──> ViewModel
///  ↑                         │
///  │                         ↓
///  └────── state ─────── [Reduce]
///                           │
///                           ↓
///                        outputs ──> Side Effects
/// ```
///
/// # Usage
///
/// ## Basic ViewModel Implementation
/// ```swift
/// class CounterViewModel: ViewModel {
///     typealias State = CounterState
///     typealias Action = CounterAction
///     typealias Output = CounterOutput
///
///     @Published var state: State
///     let id = UUID()
///
///     private let outputSubject = PassthroughSubject<Output, Never>()
///     var outputs: AnyPublisher<Output, Never> {
///         outputSubject.eraseToAnyPublisher()
///     }
///
///     required init(initialState: State) {
///         self.state = initialState
///     }
///
///     func send(_ action: Action) {
///         switch action {
///         case .increment:
///             state.count += 1
///             outputSubject.send(.countChanged(state.count))
///
///         case .decrement:
///             state.count -= 1
///             outputSubject.send(.countChanged(state.count))
///
///         case .reset:
///             state.count = 0
///             outputSubject.send(.countReset)
///         }
///     }
///
///     func onAppear() {
///         // Load initial data if needed
///     }
///
///     @discardableResult
///     func onOutput(_ handler: @escaping (Output) -> Void) -> Self {
///         outputSubject.sink(receiveValue: handler)
///             .store(in: &cancellables)
///         return self
///     }
/// }
/// ```
///
/// ## In SwiftUI View
/// ```swift
/// struct CounterView: View {
///     @StateObject var viewModel: CounterViewModel
///
///     var body: some View {
///         VStack {
///             Text("Count: \(viewModel.state.count)")
///
///             HStack {
///                 Button("-") { viewModel.send(.decrement) }
///                 Button("+") { viewModel.send(.increment) }
///                 Button("Reset") { viewModel.send(.reset) }
///             }
///         }
///         .onAppear {
///             viewModel.onAppear()
///         }
///         .onReceive(viewModel.outputs) { output in
///             handleOutput(output)
///         }
///     }
///
///     func handleOutput(_ output: CounterOutput) {
///         switch output {
///         case .countChanged(let count):
///             print("Count changed to \(count)")
///         case .countReset:
///             print("Count reset")
///         }
///     }
/// }
/// ```
///
/// # Key Features
/// - **Type-Safe**: Associated types ensure compile-time safety
/// - **Reactive**: Combine-based output stream
/// - **Testable**: Pure functions for state updates
/// - **Composable**: Parent ViewModels can observe child outputs
/// - **Identifiable**: Each ViewModel has unique ID
///
/// # Protocol Requirements
/// - `State`: ViewModelState conforming type
/// - `Action`: ViewModelAction conforming type
/// - `Output`: ViewModelOutput conforming type
/// - `state`: Published property for UI binding
/// - `send(_:)`: Action handler
/// - `outputs`: Publisher for side effects
/// - `init(initialState:)`: Required initializer
///
public protocol ViewModel: StateComponent, Identifiable, Equatable {
    /// The State type for this ViewModel
    associatedtype State: ViewModelState

    /// The Action type for this ViewModel
    associatedtype Action: ViewModelAction

    /// The Output type for this ViewModel
    associatedtype Output: ViewModelOutput
    
//    var destination: Binding<State.Destination?> { get }

    /// The current state of the ViewModel
    ///
    /// Published property that SwiftUI views observe for updates.
    var state: State { get set }

    /// Sends an action to the ViewModel
    ///
    /// Called by the view to trigger state changes or side effects.
    /// - Parameter action: The action to process
    func send(_ action: Action)

    /// Publisher for observing outputs (side effects)
    ///
    /// Subscribe to this for navigation, alerts, analytics, etc.
    var outputs: AnyPublisher<Output, Never> { get }

    /// Called when the view appears
    ///
    /// Use this for initial data loading, analytics tracking, etc.
    func onAppear()

    /// Registers an output handler
    ///
    /// Convenience method for observing outputs with closure syntax.
    /// - Parameter handler: Closure called for each output
    /// - Returns: Self for method chaining
    @discardableResult
    func onOutput(_ handler: @escaping ((Output) -> Void)) -> Self

    /// Required initializer with initial state
    ///
    /// - Parameter initialState: The starting state for the ViewModel
    init(initialState: State)
}

// MARK: - StateComponent Protocol

/// Protocol for components with observable state
///
/// Provides foundation for components that manage state and support
/// dynamic member lookup for convenient state property access.
///
/// # Usage
///
/// With DynamicStateLookup extension, you can access state properties directly:
/// ```swift
/// class MyViewModel: StateComponent {
///     struct State {
///         var count: Int = 0
///         var name: String = ""
///     }
///
///     @Published var state = State()
/// }
///
/// let vm = MyViewModel()
/// print(vm.count)  // Accesses vm.state.count
/// vm.name = "Alice" // Sets vm.state.name = "Alice"
/// ```
public protocol StateComponent: ObservableObject, DynamicStateLookup {
    /// The State type
    associatedtype State

    /// The current state
    var state: State { get set }
    func updateState(_ update: (inout State) -> Void)
}

/// Protocol for components with actions
///
/// Defines interface for components that handle user actions
/// and provide UI lifecycle methods.
///
/// # Usage
/// ```swift
/// class FormViewModel: ActionableComponent {
///     typealias Action = FormAction
///
///     @Published var isLoading: Bool = false
///
///     func send(_ action: Action) {
///         switch action {
///         case .submitTapped:
///             submitForm()
///         }
///     }
///
///     func dismiss() {
///         // Handle dismissal
///     }
/// }
/// ```
public protocol ActionableComponent: ObservableObject {
    /// The Action type
    associatedtype Action: ViewModelAction

    /// Sends an action to the component
    func send(_ action: Action)

    /// Dismisses the component
    func dismiss()

    /// Loading state indicator
    var isLoading: Bool { get set }
}

// MARK: - DynamicStateLookup Protocol

/// Enables dynamic member lookup for convenient property access
///
/// When combined with `@dynamicMemberLookup`, allows accessing
/// nested properties directly on the parent object.
///
/// # Example
/// ```swift
/// @dynamicMemberLookup
/// class ViewModel: DynamicStateLookup {
///     struct State {
///         var username: String = ""
///         var isValid: Bool = false
///     }
///
///     var state = State()
/// }
///
/// let vm = ViewModel()
/// vm.username = "john"  // Instead of vm.state.username = "john"
/// print(vm.isValid)     // Instead of print(vm.state.isValid)
/// ```
@dynamicMemberLookup
public protocol DynamicStateLookup {}

// MARK: - DynamicStateLookup Extensions

/// Default implementation for general dynamic member lookup
public extension DynamicStateLookup {
    /// Provides dynamic member lookup on self
    public subscript<Value>(dynamicMember keyPath: KeyPath<Self, Value>) -> Value {
        self[keyPath: keyPath]
    }
}

/// Extension for StateComponent to enable state property access
///
/// Allows accessing state properties directly:
/// ```swift
/// viewModel.userName  // Instead of viewModel.state.userName
/// viewModel.isLoading // Instead of viewModel.state.isLoading
/// ```
public extension DynamicStateLookup where Self: StateComponent {

    /// Read-only dynamic member lookup for state properties
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    /// Read-write dynamic member lookup for state properties
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> Value {
        get { state[keyPath: keyPath] }
        set { state[keyPath: keyPath] = newValue }
    }
}

/// Extension for ViewModel to enable state property access
///
/// Same as StateComponent extension but for ViewModel protocol.
public extension DynamicStateLookup where Self: ViewModel {

    /// Read-only dynamic member lookup for state properties
    public subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    /// Read-write dynamic member lookup for state properties
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> Value {
        get { state[keyPath: keyPath] }
        set { state[keyPath: keyPath] = newValue }
    }
}

// MARK: - Architecture Pattern Examples

/*
 # State/Action/Output Pattern

 This pattern provides clear separation of concerns:

 ## State
 - **What**: All data displayed in the UI
 - **When**: Changes trigger view updates
 - **Where**: Stored in ViewModel, observed by View
 - **Example**: Product list, loading flags, selected items

 ## Action
 - **What**: User intents or system events
 - **When**: Triggered by view interactions or lifecycle events
 - **Where**: Sent from View to ViewModel
 - **Example**: Button taps, text changes, view lifecycle

 ## Output
 - **What**: One-time side effects
 - **When**: Emitted as result of action processing
 - **Where**: Published by ViewModel, observed by View
 - **Example**: Navigation, alerts, analytics

 # Full Example

 ```swift
 // MARK: - State
 struct LoginState: ViewModelState {
     var email: String = ""
     var password: String = ""
     var isLoading: Bool = false
     var error: Error? = nil
     var isLoginButtonEnabled: Bool {
         !email.isEmpty && !password.isEmpty
     }
 }

 // MARK: - Action
 enum LoginAction: ViewModelAction {
     case emailChanged(String)
     case passwordChanged(String)
     case loginTapped
     case forgotPasswordTapped
 }

 // MARK: - Output
 enum LoginOutput: ViewModelOutput {
     case navigateToHome
     case navigateToForgotPassword
     case showError(message: String)
 }

 // MARK: - ViewModel
 class LoginViewModel: ViewModel {
     typealias State = LoginState
     typealias Action = LoginAction
     typealias Output = LoginOutput

     @Published var state: State
     let id = UUID()

     @Injected var authService: AuthenticationService
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
         case .emailChanged(let email):
             state.email = email

         case .passwordChanged(let password):
             state.password = password

         case .loginTapped:
             Task { await performLogin() }

         case .forgotPasswordTapped:
             outputSubject.send(.navigateToForgotPassword)
         }
     }

     func onAppear() {
         // Analytics, pre-fill email, etc.
     }

     @discardableResult
     func onOutput(_ handler: @escaping (Output) -> Void) -> Self {
         outputSubject.sink(receiveValue: handler)
             .store(in: &cancellables)
         return self
     }

     private func performLogin() async {
         state.isLoading = true
         state.error = nil

         do {
             try await authService.login(
                 email: state.email,
                 password: state.password
             )
             state.isLoading = false
             outputSubject.send(.navigateToHome)
         } catch {
             state.isLoading = false
             state.error = error
             outputSubject.send(.showError(message: error.localizedDescription))
         }
     }
 }

 // MARK: - View
 struct LoginView: View {
     @StateObject var viewModel: LoginViewModel

     var body: some View {
         VStack {
             TextField("Email", text: $viewModel.email)
             SecureField("Password", text: $viewModel.password)

             Button("Login") {
                 viewModel.send(.loginTapped)
             }
             .disabled(!viewModel.state.isLoginButtonEnabled)

             Button("Forgot Password?") {
                 viewModel.send(.forgotPasswordTapped)
             }

             if viewModel.isLoading {
                 ProgressView()
             }
         }
         .onAppear {
             viewModel.onAppear()
         }
         .onReceive(viewModel.outputs) { output in
             handleOutput(output)
         }
     }

     func handleOutput(_ output: LoginOutput) {
         switch output {
         case .navigateToHome:
             // Navigate to home screen

         case .navigateToForgotPassword:
             // Navigate to forgot password

         case .showError(let message):
             // Show error alert
         }
     }
 }
 ```
 */
