//
//  Connection.swift
//  RWLabsArchitecture
//
//  Wires a child ViewModel to state stored in its parent
//

import SwiftUI
import Combine
import CasePaths
import ObjectiveC

/// Implemented by connections that `ViewModelConnections` hands its parent to
protocol AnyConnection: AnyObject {
    func _setupParent(_ parent: any ViewModel)
}

@MainActor
private var directLinkKey: UInt8 = 0

// MARK: - Connection

/// Builds a connection from a parent ViewModel to a child, optionally handling the child's outputs.
///
/// Two ways to connect:
///
/// ```swift
/// // The child's state is always present on the parent (tabs, embedded panels)
/// lazy var home: HomeModel = Connection<HomeModel> { [weak parent] output in … }
///     .connect(from: parent!, to: \.home)
///
/// // The child's state is one case of the parent's destination enum (sheets, pushes)
/// lazy var editor = Connection<EditorModel> { [weak parent] output in … }
///     .connect(state: \.destination, case: \.editor, parent: parent)
/// ```
///
/// Either way the child's state stays in sync with the parent's, in both directions.
@MainActor
@dynamicMemberLookup
public final class Connection<To: ViewModel>: @MainActor AnyConnection {
    private let outputHandler: ((To.Output) -> Void)?
    private var cachedViewModel: To? {
        didSet {
            if cachedViewModel == nil { onClear() }
        }
    }
    private var outputCancellable: AnyCancellable?

    /// Called when the cached child is cleared; `CaseConnection` uses it to clear the parent's destination
    var onClear: () -> Void = {}

    /// A connection whose child's outputs go to `outputHandler`
    public init(outputHandler: @escaping (To.Output) -> Void) {
        self.outputHandler = outputHandler
    }

    /// A connection that ignores the child's outputs
    public init() {
        self.outputHandler = nil
    }

    // MARK: Connecting

    /// Connects to one case of the parent's `@CasePathable` destination enum (or any optional
    /// enum on its state). The child exists while that case is set, built from the case's payload.
    public func connect<From: ViewModel, Case: CasePathable>(
        state stateKeyPath: WritableKeyPath<From.State, Case?>,
        case casePath: CaseKeyPath<Case, To.State>,
        parent: From?
    ) -> CaseConnection<From, To, Case> {
        CaseConnection(connection: self, stateKeyPath: stateKeyPath, casePath: casePath, parent: parent)
    }

    /// Connects to an optional child state on the parent. The child exists while the value is
    /// non-`nil`, built from it; setting it to `nil` drops the child.
    ///
    /// ```swift
    /// var filter: FilterModel.State?          // parent state
    /// lazy var filter = Connection<FilterModel>().connect(state: \.filter, parent: parent)
    /// ```
    public func connect<From: ViewModel>(
        state keyPath: WritableKeyPath<From.State, To.State?>,
        parent: From?
    ) -> CaseConnection<From, To, To.State?> {
        CaseConnection(connection: self, optional: keyPath, parent: parent)
    }

    /// Connects to a child state that's always present on the parent, and returns the child.
    ///
    /// The child is built from `parent.state[keyPath: keyPath]`. Its state changes are copied
    /// into the parent, and the parent's changes to that state are copied into the child.
    public func connect<From: ViewModel>(from parent: From, to keyPath: WritableKeyPath<From.State, To.State>) -> To {
        let child = To(initialState: parent.state[keyPath: keyPath])
        let link = DirectLink(parent: parent, child: child, keyPath: keyPath, outputHandler: outputHandler)
        // The child is all the caller keeps, so it owns the link that syncs it
        objc_setAssociatedObject(child, &directLinkKey, link, .OBJC_ASSOCIATION_RETAIN)
        return child
    }

    // MARK: Child

    /// The cached child, if one has been created
    public var model: To? {
        get { cachedViewModel }
        set { cachedViewModel = newValue }
    }

    /// A binding to `model`
    public var bindingModel: Binding<To?> {
        Binding(
            get: { [weak self] in self?.model },
            set: { [weak self] in self?.model = $0 }
        )
    }

    /// Drops the cached child and stops listening to its outputs
    public func clear() {
        cachedViewModel = nil
        outputCancellable?.cancel()
        outputCancellable = nil
    }

    /// Reads a member of the child: `connection.title` for `connection.model?.title`
    public subscript<T>(dynamicMember keyPath: KeyPath<To, T>) -> T? {
        model?[keyPath: keyPath]
    }

    func _setupParent(_ parent: any ViewModel) {}

    /// The cached child, or a new one built from `childState` with the output handler attached
    func createOrGetViewModel(with childState: To.State) -> To {
        if let cachedViewModel { return cachedViewModel }
        let child = To(initialState: childState)
        cachedViewModel = child
        if let outputHandler {
            outputCancellable = child.outputs.sink(receiveValue: outputHandler)
        }
        return child
    }
}

// MARK: - DirectLink

/// Keeps a directly connected child and its parent's state in sync, and delivers the child's
/// outputs. Owned by the child; holds both models weakly, so neither is kept alive by it.
@MainActor
private final class DirectLink<From: ViewModel, To: ViewModel> {
    private weak var parent: From?
    private weak var child: To?
    private let keyPath: WritableKeyPath<From.State, To.State>
    private var cancellables = Set<AnyCancellable>()

    // Each push fires the other side's objectWillChange synchronously; these flags ignore that echo
    private var isPushingToChild = false
    private var isPushingToParent = false
    /// A child change is waiting to be copied to the parent; don't overwrite the child until it has been
    private var childSyncPending = false

    init(parent: From, child: To, keyPath: WritableKeyPath<From.State, To.State>, outputHandler: ((To.Output) -> Void)?) {
        self.parent = parent
        self.child = child
        self.keyPath = keyPath

        if let outputHandler {
            child.outputs.sink(receiveValue: outputHandler).store(in: &cancellables)
        }

        child.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.isPushingToChild else { return }
                self.childSyncPending = true
                // objectWillChange fires before the value changes; read it on the next turn
                DispatchQueue.main.async { [weak self] in self?.pushChildToParent() }
            }
            .store(in: &cancellables)

        parent.objectWillChange
            .sink { [weak self] _ in
                guard let self, !self.isPushingToParent else { return }
                DispatchQueue.main.async { [weak self] in self?.pushParentToChild() }
            }
            .store(in: &cancellables)
    }

    private func pushChildToParent() {
        childSyncPending = false
        guard let parent, let child else { return }
        isPushingToParent = true
        parent.state[keyPath: keyPath] = child.state
        isPushingToParent = false
    }

    private func pushParentToChild() {
        guard !childSyncPending, let parent, let child else { return }
        isPushingToChild = true
        child.state = parent.state[keyPath: keyPath]
        isPushingToChild = false
    }
}

// MARK: - CaseConnection

/// A child whose state is held optionally by its parent: one case of an optional enum on the
/// parent's state (usually `destination`), or a plain optional child state.
///
/// While the parent holds the child's state, the child exists: it's built from that state, and
/// the two stay in sync in both directions. When the parent's value becomes `nil` (or another
/// case), the child is dropped. Setting `bindingModel` to `nil` (a dismissed sheet, a pop)
/// clears the parent's value.
///
/// Created with `Connection.connect(state:case:parent:)` or `Connection.connect(state:parent:)`.
@MainActor
@dynamicMemberLookup
public final class CaseConnection<From: ViewModel, To: ViewModel, Case>: @MainActor AnyConnection {
    let connection: Connection<To>
    /// The child's state in the parent's state, if the parent currently holds it
    private let readPayload: (From.State) -> To.State?
    /// Writes the child's state into the parent's state; `false` if the parent no longer holds it
    private let writePayload: (inout From.State, To.State) -> Bool
    /// Sets the parent's value to `nil`; `false` (and no change) if it doesn't hold this child's state
    private let clearPayload: (inout From.State) -> Bool
    private weak var parentViewModel: (any ViewModel)?
    private var stateCancellable: AnyCancellable?
    private var childStateCancellable: AnyCancellable?
    private var isActive = false

    // Each push fires the other side's objectWillChange synchronously; these flags ignore that echo
    private var isPushingToChild = false
    private var isPushingToParent = false
    /// A child change is waiting to be copied to the parent; don't overwrite the child until it has been
    private var childSyncPending = false

    /// One case of an optional enum
    init(
        connection: Connection<To>,
        stateKeyPath: WritableKeyPath<From.State, Case?>,
        casePath: CaseKeyPath<Case, To.State>,
        parent: From?
    ) where Case: CasePathable {
        self.connection = connection
        readPayload = { state in
            state[keyPath: stateKeyPath].flatMap { AnyCasePath(casePath).extract(from: $0) }
        }
        writePayload = { state, childState in
            guard var value = state[keyPath: stateKeyPath],
                  (try? AnyCasePath(casePath).modify(&value, { $0 = childState })) != nil else {
                return false
            }
            state[keyPath: stateKeyPath] = value
            return true
        }
        clearPayload = { state in
            guard let value = state[keyPath: stateKeyPath],
                  AnyCasePath(casePath).extract(from: value) != nil else {
                return false
            }
            state[keyPath: stateKeyPath] = nil
            return true
        }
        connection.onClear = { [weak self] in self?.clearParentDestination() }
        if let parent {
            _setupParent(parent)
        }
    }

    /// A plain optional child state
    init(
        connection: Connection<To>,
        optional keyPath: WritableKeyPath<From.State, To.State?>,
        parent: From?
    ) where Case == To.State? {
        self.connection = connection
        readPayload = { $0[keyPath: keyPath] }
        writePayload = { state, childState in
            guard state[keyPath: keyPath] != nil else { return false }
            state[keyPath: keyPath] = childState
            return true
        }
        clearPayload = { state in
            guard state[keyPath: keyPath] != nil else { return false }
            state[keyPath: keyPath] = nil
            return true
        }
        connection.onClear = { [weak self] in self?.clearParentDestination() }
        if let parent {
            _setupParent(parent)
        }
    }

    // MARK: Child

    /// The child while the parent holds its state, otherwise `nil`.
    ///
    /// Always reflects the parent's state at the moment it's read, so a SwiftUI re-render
    /// straight after the state changes sees the right answer without waiting for the
    /// connection's main-queue observer.
    public var model: To? {
        get {
            syncWithParentNow()
            return isActive ? connection.model : nil
        }
        set {
            connection.model = newValue
        }
    }

    /// For `.sheet(item:)` / `.navigationDestination(item:)`; setting `nil` clears the parent's value
    public var bindingModel: Binding<To?> {
        Binding(
            get: { [weak self] in self?.model },
            set: { [weak self] newValue in
                guard let self else { return }
                if newValue == nil {
                    clearParentDestination()
                }
                model = newValue
            }
        )
    }

    /// Reads a member of the child: `connection.title` for `connection.model?.title`
    public subscript<T>(dynamicMember keyPath: KeyPath<To, T>) -> T? {
        model?[keyPath: keyPath]
    }

    // MARK: Parent

    func _setupParent(_ parent: any ViewModel) {
        guard let typedParent = parent as? From else {
            Log.w("CaseConnection: expected a parent of type \(From.self), got \(type(of: parent))")
            return
        }
        parentViewModel = typedParent
        observe(typedParent)
    }

    private func observe<P: ViewModel>(_ parent: P) {
        stateCancellable = parent.objectWillChange
            .sink { [weak self] _ in
                // Ignore the echo of our own child → parent push
                guard let self, !self.isPushingToParent else { return }
                // objectWillChange fires before the value changes; read it on the next turn
                DispatchQueue.main.async { [weak self] in self?.handleParentStateChange() }
            }
        handleParentStateChange()
    }

    /// Activates or deactivates straight away to match the parent's current state
    private func syncWithParentNow() {
        if let childState = currentPayload() {
            if !isActive { activate(with: childState) }
        } else if isActive {
            deactivate()
        }
    }

    private func handleParentStateChange() {
        if let childState = currentPayload() {
            if isActive {
                pushToChild(childState)
            } else {
                activate(with: childState)
            }
        } else if isActive {
            deactivate()
        }
    }

    /// The child's state in the parent's current state, if the parent holds it
    private func currentPayload() -> To.State? {
        guard let parentState = parentViewModel?.state as? From.State else { return nil }
        return readPayload(parentState)
    }

    // MARK: Lifecycle

    private func activate(with childState: To.State) {
        isActive = true
        let child = connection.createOrGetViewModel(with: childState)
        child.state = childState
        childStateCancellable = child.objectWillChange
            .sink { [weak self] _ in
                // Ignore the echo of our own parent → child push
                guard let self, !self.isPushingToChild else { return }
                self.childSyncPending = true
                // objectWillChange fires before the value changes; read it on the next turn
                DispatchQueue.main.async { [weak self] in self?.pushToParent() }
            }
    }

    private func deactivate() {
        isActive = false
        childStateCancellable?.cancel()
        connection.clear()
    }

    // MARK: Syncing

    private func pushToChild(_ childState: To.State) {
        // The child has a newer change on its way to the parent; pushing now would overwrite it
        guard !childSyncPending, let child = connection.model else { return }
        isPushingToChild = true
        child.state = childState
        isPushingToChild = false
    }

    private func pushToParent() {
        childSyncPending = false
        guard let child = connection.model, let parent = parentViewModel else { return }
        pushPayload(child.state, to: parent)
    }

    private func pushPayload<P: ViewModel>(_ childState: To.State, to parent: P) {
        guard var parentState = parent.state as? From.State,
              writePayload(&parentState, childState) else {
            return
        }
        isPushingToParent = true
        parent.state = parentState as! P.State
        isPushingToParent = false
    }

    /// Clears the parent's value, but only if it still holds this child's state
    private func clearParentDestination() {
        guard let parent = parentViewModel else { return }
        clearValue(of: parent)
    }

    private func clearValue<P: ViewModel>(of parent: P) {
        guard var parentState = parent.state as? From.State,
              clearPayload(&parentState) else {
            return
        }
        parent.state = parentState as! P.State
    }
}

// MARK: - Deep Links

extension CaseConnection: DeepLinkChildProviding {
    /// Processes the parent's current value now rather than on the next main-queue turn,
    /// so a deep link can continue into the child straight after setting the destination.
    func deepLinkChild() -> (any ViewModel)? {
        handleParentStateChange()
        return isActive ? connection.model : nil
    }
}
