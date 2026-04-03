//
//  Connection.swift
//  RWLabsArchitecture
//
//  Fluent API for managing state-mapped child ViewModels
//  Clean syntax: Connection<VM> { output }.connect(to: \.property)
//

import SwiftUI
import Combine
import CasePaths

protocol AnyConnection: AnyObject {
    func _setupParent(_ parent: any StateComponent)
}


// MARK: - Connection

/// Manages a child ViewModel stored in parent state with output handling
///
/// # Usage
/// ```swift
/// class Connections: BaseConnections<EntriesViewModel> {
///     lazy var filter = Connection<FilterViewModel> { [weak parent] output in
///         parent?.applyFilter(output)
///     }
///     .connect(to: \.filterViewModel)
///     .factory { FilterViewModel(initialState: .init()) }
/// }
///
/// // Transparent access
/// viewModel.connections.filter.send(.apply)
/// viewModel.connections.filter.state.searchText
/// viewModel.connections.filter.clear()
/// ```
@MainActor
@dynamicMemberLookup
public final class Connection<VM:ViewModel>: @MainActor AnyConnection {

    // MARK: - Properties

    private var outputHandler: ((VM.Output) -> Void)?
    private var factoryClosure: (() -> VM)?
    private var storedKeyPath: AnyKeyPath?

    // Storage closures (set lazily on first access)
    private var getFromState: (() -> VM?)?
    private var saveToState: ((VM) -> Void)?
    private var clearFromState: (() -> Void)?

    private var cachedViewModel: VM?
    private weak var parentRef: (any StateComponent)?

    // MARK: - Initialization

    /// Creates a Connection with output handler (trailing closure syntax)
    ///
    /// # Example
    /// ```swift
    /// Connection<FilterViewModel> { output in
    ///     parent?.handleOutput(output)
    /// }
    /// ```
    public init(outputHandler: @escaping (VM.Output) -> Void) {
        self.outputHandler = outputHandler
    }

    /// Creates a Connection without output handler
    public init() {
        self.outputHandler = nil
    }

    // MARK: - Fluent API

    /// Connects to a state property
    ///
    /// ```swift
    /// .connect(to: \.filterViewModel)
    /// ```
    public func connect<Parent>(
        to keyPath: WritableKeyPath<Parent, VM>
    ) -> Self {
        self.storedKeyPath = keyPath
        return self
    }
    
    public func connect<Parent:StateComponent>(from parent: Parent?,
                                               to keyPath: WritableKeyPath<Parent.State, VM>
    ) -> Self {
        return connect(to: keyPath).attach(parent)
    }
    
    public func attach<Parent:StateComponent>(_ parent: Parent?) -> Self    {
        guard let parent else { return self }
        self.setupParent(parent)
        return self
    }
    
    public func connect<Case: CasePathable, Parent:ViewModel>(state: WritableKeyPath<ParentState, Case?>, case casePath: CaseKeyPath<Case, VM.State>) -> PresentedCaseComponentConnection<From, To, Case> {
        PresentedCaseComponentConnection(connection: self, state: state, casePath: casePath)
    }

    /// Sets a custom factory for ViewModel creation
    ///
    /// ```swift
    /// .factory {
    ///     SettingsViewModel(initialState: .init(userId: "current-user"))
    /// }
    /// ```
    public func factory(_ factory: @escaping () -> VM) -> Self {
        self.factoryClosure = factory
        return self
    }

    // MARK: - ViewModel Access

    /// The child ViewModel instance
    ///
    /// Lazily created on first access, then cached.
    /// Automatically handles output binding and state storage.
    public var model: VM {
        // Setup accessors if not done yet
        ensureSetup()

        // Return cached if available
        if let cached = cachedViewModel {
            return cached
        }

        // Try to get existing from state
        if let existing = getFromState?() {
            cachedViewModel = existing
            bindOutputIfPossible(to: cachedViewModel!)
            return existing
        }

        // Create new ViewModel
        let newVM = createViewModel()

        // Bind output handler if VM is a BaseViewModel
        bindOutputIfPossible(to: newVM)

        // Save to state
        saveToState?(newVM)

        // Cache it
        cachedViewModel = newVM

        return newVM
    }

    // MARK: - Lifecycle

    /// Clears the ViewModel from state
    ///
    /// Next access will create a new instance.
    ///
    /// ```swift
    /// connections.filter.clear()
    /// ```
    public func clear() {
        clearFromState?()
        cachedViewModel = nil
    }

    // MARK: - Dynamic Member Lookup

    /// Transparent access to ViewModel members
    ///
    /// ```swift
    /// connections.filter.send(.apply)  // Instead of .viewModel.send(.apply)
    /// connections.filter.state.searchText
    /// ```
    public subscript<T>(dynamicMember keyPath: KeyPath<VM, T>) -> T {
        model[keyPath: keyPath]
    }

    // MARK: - Internal Setup (called by BaseConnections)

    internal func setupParent<Parent: StateComponent>(_ parent: Parent) {
        self.parentRef = parent
        guard let kp = storedKeyPath as? WritableKeyPath<Parent.State, VM> else {
            fatalError("KeyPath type mismatch")
        }
    }

    private func ensureSetup() {
        // Only set up once
        ensureParentInjected()
        guard getFromState == nil, let parent = parentRef else { return }

        // Cast the stored keyPath to the correct type
        guard let kp = storedKeyPath else {
            fatalError("Connection must call .connect(to:) before accessing viewModel")
        }

        // Try to cast to the correct keyPath type
        setupAccessors(parent: parent, keyPath: kp)
    }
    
    private func ensureParentInjected() {
        if parentRef == nil,
           let parent = (Mirror(reflecting: self).superclassMirror?.children.first { $0.label == "parent" }?.value as? any StateComponent) {
            self.setupParent(parent)
        }
    }

    private func setupAccessors<Parent: StateComponent>(parent: Parent, keyPath: AnyKeyPath) {
        // Cast keyPath to WritableKeyPath<Parent.State, VM?>
        guard let typedKeyPath = keyPath as? WritableKeyPath<Parent.State, VM> else {
            fatalError("KeyPath type mismatch")
        }

        self.getFromState = { [weak parent] in
            parent?.state[keyPath: typedKeyPath]
        }

        self.saveToState = { [weak parent] vm in
            parent?.updateState { state in
                state[keyPath: typedKeyPath] = vm
            }
        }

//        self.clearFromState = { [weak parent] in
//            parent?.updateState { state in
//                state[keyPath: typedKeyPath] = nil
//            }
//        }
    }

    // MARK: - Private Helpers

    private func createViewModel() -> VM {
        if let factory = factoryClosure {
            return factory()
        }

        // If VM is non-optional and no factory provided, crash with helpful message
        fatalError("Connection<\(VM.self)> requires .factory { } to create non-optional ViewModel. Either add .factory { } or use Connection<\(VM.self)?> for optional ViewModels.")
    }

    private func bindOutputIfPossible(to viewModel: VM) {
        guard let outputHandler = outputHandler else { return }

        // Try to bind output if VM conforms to expected protocol
        // Use runtime type checking
        bindOutputHandler(on: viewModel, handler: outputHandler)
    }

    private func bindOutputHandler(on viewModel: VM, handler: @escaping ((VM.Output) -> Void)) {
        // Type-erased output binding
        // We'll use a protocol extension to handle this properly
        viewModel.onOutput(handler)
//        callOnOutput(on: baseVM, with: handler)
    }

    private func callOnOutput(on viewModel: any ViewModel, with handler: Any) {
        // This requires BaseViewModel to expose onOutput in a type-erased way
        // For now, we'll use a workaround
        // The actual binding will work at runtime because BaseViewModel has onOutput
    }
    
    func _setupParent(_ parent: any StateComponent) {
        if let parent = parent as? any StateComponent {
            self.setupParent(parent)
        }
    }
}


@propertyWrapper
@MainActor
public struct ConnectionWrapper<VM: ViewModel> {

    private let connection: Connection<VM>

    public init<ParentState>(_ keyPath: WritableKeyPath<ParentState, VM>,
                output: ((any StateComponent, VM.Output) -> Void)? = nil) {
        self.connection = Connection<VM> {_ in 
            // handled later
        }.connect(to: keyPath)
    }

    public var wrappedValue: VM {
        connection.model
    }
}
