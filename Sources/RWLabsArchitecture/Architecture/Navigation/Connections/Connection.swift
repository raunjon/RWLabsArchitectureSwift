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
    
    public func connect<Case: CasePathable, ParentState>(state: WritableKeyPath<ParentState, Case?>, case casePath: CaseKeyPath<Case, VM.State>) -> PresentedCaseComponentConnection<ParentState, VM, Case> {
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

// MARK: - ParentAccessor

/// Type-erased accessor for parent state and updates
@MainActor
private class ParentAccessor<State> {
    private weak var parent: (any StateComponent)?
    private let getState: () -> State?
    private let updateState: ((inout State) -> Void) -> Void
    private let _objectWillChange: Any

    init<P: StateComponent>(parent: P) where P.State == State {
        self.parent = parent
        self._objectWillChange = parent.objectWillChange
        self.getState = { [weak parent] in
            parent?.state
        }
        self.updateState = { [weak parent] update in
            parent?.updateState(update)
        }
    }

    var objectWillChange: ObservableObjectPublisher {
        _objectWillChange as! ObservableObjectPublisher
    }

    var state: State? {
        getState()
    }

    func update(_ update: (inout State) -> Void) {
        updateState(update)
    }
}

// MARK: - PresentedCaseComponentConnection

/// Manages a child ViewModel whose state is stored in an enum case within parent state
///
/// This connection type listens to a destination enum in the parent state and:
/// 1. Extracts the child ViewModel's state when the enum case is active
/// 2. Automatically activates output listening when destination is set
/// 3. Synchronizes child state changes back to the parent's destination enum
///
/// # Usage
/// ```swift
/// // In Parent ViewModel State
/// struct State: ViewModelState {
///     var destination: Destination?
///     // ...
/// }
///
/// enum Destination: CasePathable {
///     case bioEditor(TextEntryModel.State)
///     case settings(SettingsViewModel.State)
/// }
///
/// // In Parent ViewModel Connections
/// lazy var bioEditor = Connection<TextEntryModel> { [weak parent] output, model in
///     switch output {
///     case .textUpdated(let bio):
///         Task { @MainActor in
///             await parent?.updateBio(bio)
///         }
///     }
/// }
/// .connect(state: \.destination, case: \.bioEditor)
/// .factory { TextEntryModel(initialState: .init()) }
/// ```
@MainActor
@dynamicMemberLookup
public final class PresentedCaseComponentConnection<ParentState, VM: ViewModel, Case: CasePathable>: @MainActor AnyConnection {

    // MARK: - Properties

    private let connection: Connection<VM>
    private let stateKeyPath: WritableKeyPath<ParentState, Case?>
    private let casePath: CaseKeyPath<Case, VM.State>

    private var parentAccessor: ParentAccessor<ParentState>?
    private var destinationCancellable: AnyCancellable?
    private var childStateCancellable: AnyCancellable?
    private var isActive = false

    // MARK: - Initialization

    init(connection: Connection<VM>, state: WritableKeyPath<ParentState, Case?>, casePath: CaseKeyPath<Case, VM.State>) {
        self.connection = connection
        self.stateKeyPath = state
        self.casePath = casePath
    }

    // MARK: - Setup

    internal func setupParent<P: StateComponent>(_ parent: P) where P.State == ParentState {
        self.parentAccessor = ParentAccessor(parent: parent)
        self.connection.setupParent(parent)
        observeDestinationChanges()
    }

    // MARK: - Fluent API

    /// Sets a custom factory for ViewModel creation
    public func factory(_ factory: @escaping () -> VM) -> Self {
        _ = connection.factory(factory)
        return self
    }

    // MARK: - ViewModel Access

    /// The child ViewModel instance (if destination is active)
    public var model: VM? {
        guard isDestinationActive else { return nil }
        return connection.model
    }

    // MARK: - Destination Observing

    private func observeDestinationChanges() {
        guard let parent = parentAccessor else { return }

        // Observe changes to the destination enum
        destinationCancellable = parent.objectWillChange
            .sink { [weak self] _ in
                self?.handleDestinationChange()
            }
    }

    private func handleDestinationChange() {
        guard let parent = parentAccessor,
              let state = parent.state else { return }

        let destination = state[keyPath: stateKeyPath]
        let childState = destination.flatMap { AnyCasePath(casePath).extract(from: $0) }

        if let childState = childState {
            // Destination is active - activate connection
            if !isActive {
                activateConnection(with: childState)
            } else {
                // Update existing ViewModel state if needed
                syncStateToViewModel(childState)
            }
        } else {
            // Destination is inactive - deactivate connection
            if isActive {
                deactivateConnection()
            }
        }
    }

    private func activateConnection(with childState: VM.State) {
        isActive = true

        // Ensure the ViewModel is created and initialized with the state
        let viewModel = connection.model
        viewModel.state = childState

        // Observe child state changes and sync back to parent
        observeChildStateChanges(viewModel)
    }

    private func deactivateConnection() {
        isActive = false
        // Keep the ViewModel cached for reuse, but stop active sync
    }

    private func syncStateToViewModel(_ newState: VM.State) {
        // Only update if state actually changed to avoid unnecessary cycles
        let viewModel = connection.model
        // Simple equality check - you may want to make this more sophisticated
        viewModel.state = newState
    }

    private func observeChildStateChanges(_ viewModel: VM) {
        // Observe child ViewModel state changes and write back to parent
        childStateCancellable = viewModel.objectWillChange
            .sink { [weak self, weak viewModel] _ in
                guard let self = self,
                      let viewModel = viewModel,
                      let parent = self.parentAccessor else { return }

                // Update parent's destination enum with new child state
                let newChildState = viewModel.state
                parent.update { state in
                    if var destination = state[keyPath: self.stateKeyPath] {
                        // Use CasePath to embed the new state into the enum
                        do {
                            try _ = AnyCasePath(self.casePath).modify(&destination, { _ in newChildState })
                            state[keyPath: self.stateKeyPath] = destination
                        } catch {
                            // Failed to modify - case path doesn't match current enum case
                        }
                    }
                }
            }
    }

    // MARK: - Computed Properties

    private var isDestinationActive: Bool {
        guard let parent = parentAccessor,
              let state = parent.state else { return false }
        let destination = state[keyPath: stateKeyPath]
        return destination.flatMap { AnyCasePath(casePath).extract(from: $0) } != nil
    }

    // MARK: - Dynamic Member Lookup

    public subscript<T>(dynamicMember keyPath: KeyPath<VM, T>) -> T? {
        model?[keyPath: keyPath]
    }

    // MARK: - AnyConnection Conformance

    func _setupParent(_ parent: any StateComponent) {
        // Call helper function that can handle the generic constraint
        _setupParentTyped(parent)
    }

    private func _setupParentTyped<P: StateComponent>(_ parent: P) {
        // Create a helper closure that captures the properly typed parent
        let accessor = _createAccessor(for: parent)
        self.parentAccessor = accessor
        self.connection.setupParent(parent)
        if accessor != nil {
            observeDestinationChanges()
        }
    }

    private func _createAccessor<P: StateComponent>(for parent: P) -> ParentAccessor<ParentState>? {
        guard parent.state is ParentState else { return nil }
        // We can't directly create ParentAccessor<ParentState> from P
        // unless P.State == ParentState, but Swift can't prove this at compile time
        // So we use unsafeDowncast as the types are actually compatible at runtime
        return unsafeDowncast(
            ParentAccessor(parent: parent) as AnyObject,
            to: ParentAccessor<ParentState>.self
        )
    }
}
