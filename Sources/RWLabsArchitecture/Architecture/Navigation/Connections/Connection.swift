//
//  Connection.swift
//  RWLabsArchitecture
//
//  Fluent API for managing state-mapped child ViewModels
//  Clean syntax: Connection<VM> { output }.connect(state: \.destination, case: \.myCase)
//

import SwiftUI
import Combine
import CasePaths

// MARK: - AnyConnection Protocol

protocol AnyConnection: AnyObject {
    func _setupParent(_ parent: any ViewModel)
}

// MARK: - Connection

/// Manages a child ViewModel stored in parent state with output handling
///
/// # Usage
/// ```swift
/// class Connections: BaseConnections<ParentViewModel> {
///     lazy var entry = Connection<EntryViewModel> { [weak parent] output in
///         guard let parent = parent else { return }
///         switch output {
///         case .entryUpdated(let entry):
///             parent.handleEntryUpdate(entry)
///         }
///     }
///     .connect(state: \.destination, case: \.entry)
///     .factory { EntryViewModel(initialState: .init()) }
/// }
///
/// // Transparent access
/// viewModel.connections.entry.send(.update)
/// viewModel.connections.entry.state.title
/// ```
@MainActor
@dynamicMemberLookup
public final class Connection<VM: ViewModel>: @MainActor AnyConnection {

    // MARK: - Properties

    private let outputHandler: ((VM.Output) -> Void)?
    private var factoryClosure: (() -> VM)?

    private weak var parentViewModel: (any ViewModel)?
    private var cachedViewModel: VM?

    // Observation
    private var stateCancellable: AnyCancellable?
    private var childStateCancellable: AnyCancellable?
    private var isActive = false

    // MARK: - Initialization

    /// Creates a Connection with output handler
    public init(outputHandler: @escaping (VM.Output) -> Void) {
        self.outputHandler = outputHandler
    }

    /// Creates a Connection without output handler
    public init() {
        self.outputHandler = nil
    }

    // MARK: - Fluent API

    /// Sets a custom factory for ViewModel creation
    ///
    /// ```swift
    /// .factory { EntryViewModel(initialState: .init()) }
    /// ```
    public func factory(_ factory: @escaping () -> VM) -> Self {
        self.factoryClosure = factory
        return self
    }

    /// Connects to a case within parent's state destination enum
    ///
    /// ```swift
    /// .connect(state: \.destination, case: \.entry)
    /// ```
    public func connect<From: ViewModel, Case: CasePathable>(
        state stateKeyPath: WritableKeyPath<From.State, Case?>,
        case casePath: CaseKeyPath<Case, VM.State>, parent: From?
    ) -> CaseConnection<From, VM, Case> {
        return CaseConnection(
            connection: self,
            stateKeyPath: stateKeyPath,
            casePath: casePath,
            parent: parent
        )
    }

    // MARK: - ViewModel Access

    /// The child ViewModel instance (if active)
    public var model: VM? {
        return cachedViewModel
    }

    // MARK: - Lifecycle

    /// Clears the cached ViewModel
    public func clear() {
        cachedViewModel = nil
        isActive = false
        childStateCancellable?.cancel()
    }

    // MARK: - Dynamic Member Lookup

    /// Transparent access to ViewModel members
    public subscript<T>(dynamicMember keyPath: KeyPath<VM, T>) -> T? {
        model?[keyPath: keyPath]
    }

    // MARK: - Internal

    func _setupParent(_ parent: any ViewModel) {
        self.parentViewModel = parent
    }

    fileprivate func createOrGetViewModel(with childState: VM.State) -> VM {
        if let cached = cachedViewModel {
            return cached
        }

        let vm = createViewModel(with: childState)
        cachedViewModel = vm

        // Bind output handler if provided
        if let outputHandler = outputHandler {
            vm.onOutput(outputHandler)
        }

        return vm
    }

    private func createViewModel(with childState: VM.State) -> VM {
        return .init(initialState: childState)
    }
}

// MARK: - CaseConnection

/// Manages a child ViewModel whose state is stored in an enum case within parent state
///
/// This connection type:
/// 1. Observes changes to parent's state destination enum
/// 2. Extracts child state when the case matches
/// 3. Creates/updates child ViewModel with extracted state
/// 4. Syncs child state changes back to parent
/// 5. Handles output callbacks
///
/// # Usage
/// ```swift
/// // In Parent State
/// struct State: ViewModelState {
///     var destination: Destination?
/// }
///
/// enum Destination: CasePathable {
///     case entry(EntryViewModel.State)
///     case settings(SettingsViewModel.State)
/// }
///
/// // In Connections
/// lazy var entry = Connection<EntryViewModel> { [weak parent] output in
///     switch output {
///     case .updated(let data):
///         parent?.handleUpdate(data)
///     }
/// }
/// .connect(state: \.destination, case: \.entry)
/// .factory { EntryViewModel(initialState: .init()) }
/// ```
@MainActor
@dynamicMemberLookup
public final class CaseConnection<From: ViewModel, To: ViewModel, Case: CasePathable>: @MainActor AnyConnection {

    // MARK: - Properties

    private let connection: Connection<To>
    private let stateKeyPath: WritableKeyPath<From.State, Case?>
    private let casePath: CaseKeyPath<Case, To.State>

    private weak var parentViewModel: (any ViewModel)?
    private var stateCancellable: AnyCancellable?
    private var childStateCancellable: AnyCancellable?
    private var isActive = false

    // MARK: - Initialization

    init(
        connection: Connection<To>,
        stateKeyPath: WritableKeyPath<From.State, Case?>,
        casePath: CaseKeyPath<Case, To.State>,
        parent: From?
    ) {
        self.connection = connection
        self.stateKeyPath = stateKeyPath
        self.casePath = casePath
        if let parent {
            self._setupParent(parent)
        }
    }

    // MARK: - Fluent API

    /// Sets a custom factory for ViewModel creation
    public func factory(_ factory: @escaping () -> To) -> Self {
        _ = connection.factory(factory)
        return self
    }

    // MARK: - ViewModel Access

    /// The child ViewModel instance (if destination case is active)
    public var model: To? {
        guard isActive else { return nil }
        return connection.model
    }

    // MARK: - Dynamic Member Lookup

    public subscript<T>(dynamicMember keyPath: KeyPath<To, T>) -> T? {
        model?[keyPath: keyPath]
    }

    // MARK: - AnyConnection

    func _setupParent(_ parent: (any ViewModel)) {
        guard parent.state is From.State else {
            print("⚠️ CaseConnection: Parent state type mismatch")
            return
        }

        self.parentViewModel = parent
        self.connection._setupParent(parent)

        // Set up observation using generic helper to capture concrete type
        setupObservation(for: parent)
    }

    // MARK: - State Observation

    private func setupObservation<P: ViewModel>(for parent: P) {
        // Now we have the concrete type, so objectWillChange works properly
        stateCancellable = parent.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.handleParentStateChange()
                }
            }

        // Check initial state
        handleParentStateChange()
    }

    private func handleParentStateChange() {
        guard let parent = parentViewModel,
              let parentState = parent.state as? From.State else {
            return
        }

        // Get destination from parent state
        let destination = parentState[keyPath: stateKeyPath]

        // Extract child state using case path
        let childState = destination.flatMap { AnyCasePath(self.casePath).extract(from: $0) }

        if let childState = childState {
            // Case is active - activate or update connection
            if !isActive {
                activateConnection(with: childState)
            } else {
                syncStateToViewModel(childState)
            }
        } else {
            // Case is inactive - deactivate connection
            if isActive {
                deactivateConnection()
            }
        }
    }

    private func activateConnection(with childState: To.State) {
        isActive = true

        // Create or get the ViewModel
        let viewModel = connection.createOrGetViewModel(with: childState)

        // Set the state
        viewModel.state = childState

        // Observe child state changes
        observeChildStateChanges(viewModel)
    }

    private func deactivateConnection() {
        isActive = false
        childStateCancellable?.cancel()
    }

    private func syncStateToViewModel(_ newState: To.State) {
        guard let viewModel = connection.model else { return }

        // Only update if state is different to avoid cycles
        // Simple approach: always update (ViewModel can optimize internally)
        viewModel.state = newState
    }

    private func observeChildStateChanges(_ viewModel: To) {
        // Observe child ViewModel state changes and sync back to parent
        childStateCancellable = viewModel.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.syncChildStateToParent()
                }
            }
    }

    private func syncChildStateToParent() {
        guard let viewModel = connection.model,
              let parent = parentViewModel else {
            return
        }

        let newChildState = viewModel.state

        // Use generic helper to properly update parent state
        updateParentState(parent, childState: newChildState)
    }

    private func updateParentState<P: ViewModel>(_ parent: P, childState: To.State) {
        guard var parentState = parent.state as? From.State else { return }

        // Get current destination
        guard var destination = parentState[keyPath: stateKeyPath] else {
            return
        }

        // Update the case with new state
        do {
            try _ = AnyCasePath(casePath).modify(&destination) { _ in childState }

            // Update parent state
            parentState[keyPath: stateKeyPath] = destination

            // Update using the proper typed method
            parent.updateState { state in
                if var typedState = state as? From.State {
                    typedState[keyPath: stateKeyPath] = destination
                    state = typedState as! P.State
                }
            }
        } catch {
            // Case path doesn't match current enum case - this is normal
        }
    }
}

// MARK: - Helper Extensions

extension StateComponent {
    /// Updates state using a closure
    public func updateState(_ update: (inout State) -> Void) {
        var newState = state
        update(&newState)
        state = newState
    }
}
