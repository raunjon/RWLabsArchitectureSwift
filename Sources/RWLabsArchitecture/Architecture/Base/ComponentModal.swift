//
//  ComponentModal.swift
//  RWLabsArchitecture
//
//  Base class for modal/sheet ViewModels
//

import SwiftUI
import Combine

// MARK: - Component Modal

/// Base class for modal or sheet ViewModels using State/Action/Output pattern
///
/// `ComponentModal` provides a lightweight ViewModel implementation for modal views,
/// sheets, alerts, and other temporary UI components that don't require navigation.
///
/// # Architecture Pattern
///
/// ComponentModal follows the same State/Action/Output pattern as BaseViewModel
/// but without navigation capabilities:
///
/// ```
/// State
///     └─ Single source of truth for UI state
///
/// Action
///     └─ User interactions and events
///         ↓
///     send(_ action:) → Process action
///         ↓
///     Update state or sendOutput
///
/// Output
///     └─ Side effects (navigation, parent communication, etc.)
/// ```
///
/// # When to Use
///
/// Use `ComponentModal` for:
/// - Modal views and sheets that don't need their own navigation
/// - Input dialogs, pickers, and forms
/// - Child components that communicate with parents via outputs
/// - Temporary UI overlays
///
/// Use `BaseViewModel` instead if you need:
/// - Navigation stack management
/// - Complex routing between multiple screens
/// - Deep linking support
///
/// # Example Usage
///
/// ```swift
/// // Define State, Action, Output
/// typealias AddCommentState = AddCommentViewModel.State
/// typealias AddCommentAction = AddCommentViewModel.Action
/// typealias AddCommentOutput = AddCommentViewModel.Output
///
/// class AddCommentViewModel: ComponentModal<AddCommentState, AddCommentAction, AddCommentOutput> {
///     struct State: ViewModelState {
///         var isLoading: Bool = false
///         var error: Error?
///         var comment: String = ""
///     }
///
///     enum Action: ViewModelAction {
///         case submit
///         case cancel
///     }
///
///     enum Output: ViewModelOutput {
///         case didSubmit(String)
///         case didCancel
///     }
///
///     override func send(_ action: Action) {
///         switch action {
///         case .submit:
///             sendOutput(.didSubmit(state.comment))
///         case .cancel:
///             sendOutput(.didCancel)
///         }
///     }
///
///     override func onAppear() {
///         // Initialize if needed
///     }
/// }
///
/// // In view
/// struct AddCommentView: View {
///     @ObservedObject var viewModel: AddCommentViewModel
///
///     var body: some View {
///         VStack {
///             TextField("Comment", text: $viewModel.state.comment)
///             Button("Submit") {
///                 viewModel.send(.submit)
///             }
///         }
///     }
/// }
/// ```
///
/// # Features
/// n
/// - **@Published State**: Automatic view updates via `@ObservedObject`
/// - **Output Publishing**: Communicate with parent via Combine publishers
/// - **Equatable & Hashable**: Can be used in collections and ForEach
/// - **Identifiable**: Unique ID for SwiftUI identity
/// - **Cancellable Storage**: Built-in storage for Combine subscriptions
///
@MainActor
open class ComponentModal1<State: ViewModelState, Action: ViewModelAction, Output: ViewModelOutput>: @MainActor ViewModel, @MainActor ActionableComponent, @MainActor OutputableComponent, Equatable, @MainActor Hashable {
    
    // MARK: - Properties

    /// Unique identifier for this component
    public let id: UUID = UUID()

    /// Subject for publishing outputs to parent
    public let outputSubject: PassthroughSubject<Output, Never> = .init()

    /// Optional handler for outputs (alternative to Combine subscription)
    public var outputHandler: ((Output) -> Void)?

    /// Storage for Combine cancellables
    public var cancellables = Set<AnyCancellable>()

    /// Current state of the component
    /// - Note: Marked with @Published to trigger view updates
    @Published public var state: State

    /// Loading state indicator
    public var isLoading: Bool = false

    // MARK: - Initialization

    /// Initialize with an initial state
    /// - Parameter initialState: The initial state for this component
    public required init(initialState: State) {
        self.state = initialState
    }

    // MARK: - Action Handling

    /// Sends an action to be processed by the component
    ///
    /// Override this method in subclasses to handle actions:
    /// ```swift
    /// override func send(_ action: Action) {
    ///     switch action {
    ///     case .submit:
    ///         // Handle submit
    ///     case .cancel:
    ///         sendOutput(.didCancel)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter action: The action to process
    open func send(_ action: Action) {
        fatalError("Must override send(_:) in subclass")
    }

    // MARK: - Lifecycle

    /// Called when the view appears
    ///
    /// Override this method to perform initialization:
    /// ```swift
    /// override func onAppear() {
    ///     // Load initial data
    ///     // Setup subscriptions
    /// }
    /// ```
    open func onAppear() {
        fatalError("Must override onAppear() in subclass")
    }

    /// Dismisses the component
    ///
    /// Override this method if you need custom dismiss logic:
    /// ```swift
    /// override func dismiss() {
    ///     sendOutput(.didDismiss)
    ///     super.dismiss()
    /// }
    /// ```
    open func dismiss() {
        // Default implementation does nothing
        // Subclasses can override for custom dismiss logic
    }

    // MARK: - State Management

    /// Update state on main thread
    ///
    /// Use this to safely mutate state:
    /// ```swift
    /// updateState { state in
    ///     state.isLoading = true
    ///     state.items.append(newItem)
    /// }
    /// ```
    ///
    /// - Parameter update: Closure that mutates the state
    public func updateState(_ update: (inout State) -> Void) {
        update(&state)
    }

    // MARK: - Cancellable Management

    /// Store a cancellable for later cleanup
    ///
    /// Use this to manage Combine subscriptions:
    /// ```swift
    /// publisher
    ///     .sink { value in /* ... */ }
    ///     .store(in: &cancellables) // or viewModel.store(cancellable)
    /// ```
    ///
    /// - Parameter cancellable: The cancellable to store
    public func store(_ cancellable: AnyCancellable) {
        cancellables.insert(cancellable)
    }

    /// Subscribe to outputs with a handler
    ///
    /// Use this for a fluent API:
    /// ```swift
    /// let viewModel = MyViewModel(initialState: .init())
    ///     .onOutput { output in
    ///         // Handle output
    ///     }
    /// ```
    ///
    /// - Parameter handler: Closure to handle outputs
    /// - Returns: Self for chaining
    @discardableResult
    public func onOutput(_ handler: @escaping ((Output) -> Void)) -> Self {
        store(
            outputs.sink(receiveValue: handler)
        )
        return self
    }

    // MARK: - Equatable

    nonisolated public static func == (lhs: ComponentModal1<State, Action, Output>, rhs: ComponentModal1<State, Action, Output>) -> Bool {
        lhs.id == rhs.id
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id.description)
    }
}
