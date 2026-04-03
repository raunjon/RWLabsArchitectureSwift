//
//  OptionalConnection.swift
//  ThirtyPlusPanel
//
//  Created by Raunak Joneja on 18/03/26.
//

import SwiftUI
import Combine

@MainActor
@dynamicMemberLookup
public final class OptionalConnection<VM: ViewModel>: @MainActor AnyConnection {

    // MARK: - Properties

    /// Handles outputs emitted by the child ViewModel
    private var outputHandler: ((VM.Output) -> Void)?

    /// Factory used to lazily create the ViewModel (optional)
    private var factoryClosure: (() -> VM)?

    /// Stores the keyPath to the parent's state property (type-erased)
    private var storedKeyPath: AnyKeyPath?

    // Lazily initialized closures to interact with parent state
    private var getFromState: (() -> VM?)?
    private var saveToState: ((VM?) -> Void)?
    private var clearFromState: (() -> Void)?

    /// Cached instance to avoid repeated state lookups
    private var cachedViewModel: VM?

    /// Weak reference to parent to avoid retain cycles
    private weak var parentRef: (any StateComponent)?

    // MARK: - Initialization

    /// Initialize with an output handler
    ///
    /// Example:
    /// ```swift
    /// OptionalConnection<FilterViewModel> { output in
    ///     parent?.handle(output)
    /// }
    /// ```
    public init(outputHandler: @escaping (VM.Output) -> Void) {
        self.outputHandler = outputHandler
    }

    /// Initialize without output handling
    public init() {
        self.outputHandler = nil
    }

    // MARK: - Fluent API

    /// Connects this ViewModel to a parent state property (optional)
    ///
    /// Example:
    /// ```swift
    /// .connect(to: \.filterViewModel)
    /// ```
    public func connect<ParentState>(
        to keyPath: WritableKeyPath<ParentState, VM?>
    ) -> Self {
        self.storedKeyPath = keyPath
        return self
    }
    
    public func connect<Parent:StateComponent>(from parent: Parent?,
                                               to keyPath: WritableKeyPath<Parent.State, VM?>
    ) -> Self {
        return connect(to: keyPath).attach(parent)
    }
    
    public func attach<Parent:StateComponent>(_ parent: Parent?) -> Self    {
        guard let parent else { return self }
        self.setupParent(parent)
        return self
        
    }

    /// Provides a factory for lazy ViewModel creation
    ///
    /// If not provided, ViewModel will only be read from state (no creation)
    public func factory(_ factory: @escaping () -> VM) -> Self {
        self.factoryClosure = factory
        return self
    }

    // MARK: - ViewModel Access

    /// Access the underlying ViewModel (if present)
    ///
    /// Resolution order:
    /// 1. Return cached instance if available
    /// 2. Fetch from parent state
    /// 3. Create via factory (if provided)
    /// 4. Otherwise return nil
    public var model: VM? {
        ensureSetup()

        // 1. Return cached instance
        if let cached = cachedViewModel {
            return cached
        }

        // 2. Try to fetch from state
        if let existing = getFromState?() {
            cachedViewModel = existing
            bindOutputIfPossible(to: existing)
            return existing
        }

        // 3. Create using factory (if available)
        guard let factory = factoryClosure else {
            return nil
        }

        let newVM = factory()
        bindOutputIfPossible(to: newVM)

        // Persist to state
        saveToState?(newVM)

        // Cache locally
        cachedViewModel = newVM

        return newVM
    }

    // MARK: - Lifecycle

    /// Clears the ViewModel from state and cache
    ///
    /// Next access will:
    /// - return nil (if no factory)
    /// - or create a new instance (if factory exists)
    public func clear() {
        clearFromState?()
        cachedViewModel = nil
    }

    // MARK: - Dynamic Member Lookup

    /// Enables transparent optional access to ViewModel members
    ///
    /// Example:
    /// ```swift
    /// connections.filter.state?.searchText
    /// connections.filter.send?(.apply)
    /// ```
    public subscript<T>(dynamicMember keyPath: KeyPath<VM, T>) -> T? {
        model?[keyPath: keyPath]
    }

    // MARK: - Internal Setup

    /// Called by BaseConnections to inject parent reference
    internal func setupParent<Parent: StateComponent>(_ parent: Parent) {
        self.parentRef = parent
    }

    /// Ensures state accessors are initialized once
    private func ensureSetup() {
        guard getFromState == nil, let parent = parentRef else { return }

        guard let kp = storedKeyPath else {
            fatalError("OptionalConnection must call .connect(to:) before accessing viewModel")
        }

        setupAccessors(parent: parent, keyPath: kp)
    }

    /// Sets up closures to interact with parent state using the provided keyPath
    private func setupAccessors<Parent: StateComponent>(
        parent: Parent,
        keyPath: AnyKeyPath
    ) {
        guard let typedKeyPath = keyPath as? WritableKeyPath<Parent.State, VM?> else {
            fatalError("KeyPath type mismatch in OptionalConnection")
        }

        // Read from state
        self.getFromState = { [weak parent] in
            parent?.state[keyPath: typedKeyPath]
        }

        // Write to state
        self.saveToState = { [weak parent] vm in
            parent?.updateState { state in
                state[keyPath: typedKeyPath] = vm
            }
        }

        // Clear from state
        self.clearFromState = { [weak parent] in
            parent?.updateState { state in
                state[keyPath: typedKeyPath] = nil
            }
        }
    }

    // MARK: - Private Helpers

    /// Binds output handler if both ViewModel and handler exist
    private func bindOutputIfPossible(to viewModel: VM?) {
        guard let vm = viewModel,
              let outputHandler = outputHandler else { return }

        vm.onOutput(outputHandler)
    }
    
    func _setupParent(_ parent: any StateComponent) {
        if let parent = parent as? any StateComponent {
            self.setupParent(parent)
        }
    }
}
