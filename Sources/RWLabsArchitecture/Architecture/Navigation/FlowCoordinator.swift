//
//  FlowCoordinator.swift
//  RWLabsArchitecture
//
//  Coordinates application flows and their lifecycle
//  Manages flow transitions, subflow activation, and flow state
//

import Foundation
import Combine

// MARK: - Flow Coordinator

/// Coordinates application flows and their lifecycle using FlowContext-based architecture
///
/// `FlowCoordinator` is the central orchestrator for flow-based navigation.
/// It manages the flow hierarchy, handles transitions between flows, and maintains
/// both current (FlowContext-based) and legacy flow state.
///
/// # Architecture
/// - **FlowContext-Based**: Each flow gets its own context with independent state
/// - **Hierarchical**: Supports parent-child flow relationships
/// - **Observable**: Publishes state changes for SwiftUI integration
/// - **Command Pattern**: Emits flow commands for platform-specific handling
///
/// # Example
/// ```swift
/// let coordinator = FlowCoordinator()
///
/// // Set initial flow
/// coordinator.setRootFlow(OnboardingFlow())
///
/// // Later, switch to main app
/// coordinator.replaceFlow(MainAppFlow())
///
/// // Activate a subflow
/// coordinator.activateSubflow(EntriesFlow(), in: "mainApp")
/// ```
@MainActor
public final class FlowCoordinator: ObservableObject {

    // MARK: - Published State

    /// Current root flow context
    @Published public private(set) var rootFlowContext: FlowContext?

    /// Legacy flow state for backward compatibility
    @Published public private(set) var state: FlowState

    // MARK: - Private Properties

    /// Registry of all flow contexts by flow ID
    private var flowContextRegistry: [String: FlowContext] = [:]

    /// Subject for emitting flow commands
    private let commandSubject = PassthroughSubject<FlowCommand, Never>()

    /// Flow command publisher for platform-specific implementations
    public var commands: AnyPublisher<FlowCommand, Never> {
        commandSubject.eraseToAnyPublisher()
    }

    /// Registered flow guards for transition validation
    private var flowGuards: [String: (any Flow, any Flow) -> Bool] = [:]

    /// Cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a new flow coordinator
    public init() {
        self.state = FlowState()
    }

    // MARK: - Root Flow Management

    /// Sets the root flow for the application
    ///
    /// This is typically called once at app launch to establish the initial flow.
    /// Clears any existing flow hierarchy and starts fresh.
    ///
    /// - Parameters:
    ///   - flow: The flow to set as root
    ///   - animated: Whether to animate the transition (default: `true`)
    ///
    /// # Example
    /// ```swift
    /// // At app launch
    /// if user.isAuthenticated {
    ///     coordinator.setRootFlow(MainAppFlow())
    /// } else {
    ///     coordinator.setRootFlow(OnboardingFlow())
    /// }
    /// ```
    public func setRootFlow<F: Flow>(_ flow: F, animated: Bool = true) {

        // Validate flow can be entered
        guard flow.canEnter() else {
            print("⚠️ Flow '\(flow.id)' cannot be entered")
            return
        }

        // Exit current flow if exists
        if let currentContext = rootFlowContext {
            currentContext.flow.onExit()
            currentContext.clearSubflows()
        }

        // Create new flow context
        let newContext = FlowContext(flow: flow)
        rootFlowContext = newContext
        flowContextRegistry[flow.id] = newContext

        // Update legacy state for backward compatibility
        state.currentRootFlow = flow
        state.flowStack = [flow]
        state.transitionHistory.append(
            FlowTransition(
                from: nil,
                to: flow.id,
                type: .setRoot
            )
        )

        // Emit command for platform handling
        commandSubject.send(.setRootFlow(flow, animated: animated))

        // Navigate to initial destination
        newContext.navigateToInitial(animated: animated)

        print("✅ Set root flow: \(flow.id)")
    }

    /// Replaces the current flow with a new flow
    ///
    /// Unlike `setRootFlow`, this is used for flow replacement during runtime,
    /// such as transitioning from onboarding to the main app.
    ///
    /// - Parameters:
    ///   - flow: The new flow to set
    ///   - animated: Whether to animate the transition (default: `true`)
    ///
    /// # Example
    /// ```swift
    /// // After completing onboarding
    /// coordinator.replaceFlow(MainAppFlow())
    ///
    /// // After logout
    /// coordinator.replaceFlow(OnboardingFlow())
    /// ```
    public func replaceFlow<F: Flow>(_ flow: F, animated: Bool = true) {

        guard flow.canEnter() else {
            print("⚠️ Flow '\(flow.id)' cannot be entered")
            return
        }

        // Exit current flow if exists
        if let currentContext = rootFlowContext {
            currentContext.flow.onExit()
            currentContext.clearSubflows()
            flowContextRegistry.removeValue(forKey: currentContext.flow.id)
        }

        let fromFlowId = rootFlowContext?.flow.id

        // Create new flow context
        let newContext = FlowContext(flow: flow)
        rootFlowContext = newContext
        flowContextRegistry[flow.id] = newContext

        // Update legacy state
        if !state.flowStack.isEmpty {
            state.flowStack[state.flowStack.count - 1] = flow
        } else {
            state.flowStack = [flow]
            state.currentRootFlow = flow
        }

        state.transitionHistory.append(
            FlowTransition(
                from: fromFlowId,
                to: flow.id,
                type: .replace
            )
        )

        // Emit command
        commandSubject.send(.replaceFlow(flow, animated: animated))

        // Navigate to initial destination
        newContext.navigateToInitial(animated: animated)

        print("✅ Replaced flow with: \(flow.id)")
    }

    /// Resets to the root flow, clearing all subflows
    ///
    /// Useful for "reset to home" functionality or clearing deep navigation stacks.
    ///
    /// - Parameter animated: Whether to animate the transition (default: `true`)
    ///
    /// # Example
    /// ```swift
    /// // User taps "Home" button
    /// coordinator.resetToRoot()
    /// ```
    public func resetToRoot(animated: Bool = true) {
        guard let rootContext = rootFlowContext else {
            print("⚠️ No root flow to reset to")
            return
        }

        // Clear all subflows
        rootContext.clearSubflows()

        // Reset legacy state
        state.flowStack = [rootContext.flow]

        // Emit command
        commandSubject.send(.resetToRoot(animated: animated))

        // Navigate to root flow's initial destination
        rootContext.navigateToInitial(animated: animated)

        print("✅ Reset to root flow: \(rootContext.flow.id)")
    }

    // MARK: - Subflow Management

    /// Activates a subflow from a parent flow context
    ///
    /// Subflows are child flows that can be entered from a parent flow.
    /// The activation behavior depends on the parent's activation mode:
    /// - **Exclusive**: Only one subflow active at a time
    /// - **Concurrent**: Multiple subflows can be active (e.g., tabs)
    ///
    /// - Parameters:
    ///   - subflow: The subflow to activate
    ///   - parentFlowId: The ID of the parent flow (defaults to root flow)
    ///   - animated: Whether to animate the transition (default: `true`)
    /// - Returns: The created or existing flow context for the subflow
    ///
    /// # Example
    /// ```swift
    /// // Activate entries subflow in main app
    /// coordinator.activateSubflow(EntriesFlow(), in: "mainApp")
    ///
    /// // Activate from default parent (root)
    /// coordinator.activateSubflow(SettingsFlow())
    /// ```
    @discardableResult
    public func activateSubflow<F: Flow>(
        _ subflow: F,
        in parentFlowId: String? = nil,
        animated: Bool = true
    ) -> FlowContext? {
        let anySubflow = subflow

        // Validate subflow can be entered
        guard anySubflow.canEnter() else {
            print("⚠️ Subflow '\(anySubflow.id)' cannot be entered")
            return nil
        }

        // Determine parent context
        let parentContext: FlowContext?
        if let parentFlowId = parentFlowId {
            parentContext = flowContextRegistry[parentFlowId]
        } else {
            parentContext = rootFlowContext
        }

        guard let parent = parentContext else {
            print("⚠️ No parent flow context found")
            return nil
        }

        // Activate subflow in parent context
        guard let subflowContext = parent.activateSubflow(anySubflow) else {
            return nil
        }

        // Register in global registry
        flowContextRegistry[anySubflow.id] = subflowContext

        // Update legacy state for exclusive mode
        if parent.flow.activationMode == .exclusive {
            state.flowStack.append(anySubflow)
            state.transitionHistory.append(
                FlowTransition(
                    from: parent.flow.id,
                    to: anySubflow.id,
                    type: .enterSubflow
                )
            )
        }

        // Emit command
        commandSubject.send(.enterSubflow(anySubflow, animated: animated))

        // Update active flow context
        activeFlowContext = subflowContext

        print("✅ Activated subflow: \(anySubflow.id) in \(parent.flow.id) (mode: \(parent.flow.activationMode))")

        return subflowContext
    }

    /// Deactivates a subflow
    ///
    /// Calls the subflow's `onExit()` lifecycle method and removes it from
    /// the parent's active subflows.
    ///
    /// - Parameters:
    ///   - subflowId: The ID of the subflow to deactivate
    ///   - animated: Whether to animate the transition (default: `true`)
    ///
    /// # Example
    /// ```swift
    /// coordinator.deactivateSubflow("entries")
    /// ```
    public func deactivateSubflow(_ subflowId: String, animated: Bool = true) {
        guard let subflowContext = flowContextRegistry[subflowId] else {
            print("⚠️ Subflow '\(subflowId)' not found")
            return
        }

        guard let parentContext = subflowContext.parentContext else {
            print("⚠️ Cannot deactivate: subflow has no parent")
            return
        }

        // Call onExit lifecycle method
        subflowContext.flow.onExit()

        // Deactivate in parent context
        parentContext.deactivateSubflow(subflowId)

        // Update legacy state for exclusive mode
        if parentContext.flow.activationMode == .exclusive {
            if let index = state.flowStack.firstIndex(where: { $0.id == subflowId }) {
                state.flowStack.remove(at: index)
            }

            state.transitionHistory.append(
                FlowTransition(
                    from: subflowId,
                    to: parentContext.flow.id,
                    type: .exitSubflow
                )
            )
        }

        // Emit command
        commandSubject.send(.exitSubflow(animated: animated))

        print("✅ Deactivated subflow: \(subflowId), parent: \(parentContext.flow.id)")
    }

    // MARK: - Flow Context Access

    /// Gets the flow context for a specific flow ID
    /// - Parameter flowId: The ID of the flow
    /// - Returns: The flow context if it exists, `nil` otherwise
    public func flowContext(for flowId: String) -> FlowContext? {
        flowContextRegistry[flowId]
    }

    /// Gets the currently active flow context
    ///
    /// In exclusive mode, this is the most recently activated subflow.
    /// In concurrent mode (e.g., tabs), this is set when a tab is selected.
    public var activeFlowContext: FlowContext?

    // MARK: - Guards

    /// Registers a guard for flow transitions
    ///
    /// Guards validate whether a transition from one flow to another is allowed.
    ///
    /// - Parameters:
    ///   - flowId: The ID of the flow to guard
    ///   - guard: Closure that returns `true` if transition is allowed
    ///
    /// # Example
    /// ```swift
    /// coordinator.registerGuard(for: "checkout") { fromFlow, toFlow in
    ///     // Don't allow checkout if cart is empty
    ///     return !shoppingCart.isEmpty
    /// }
    /// ```
    public func registerGuard(
        for flowId: String,
        guard: @escaping (any Flow, any Flow) -> Bool
    ) {
        flowGuards[flowId] = `guard`
        print("✅ Registered guard for flow: \(flowId)")
    }

    /// Removes a guard for a flow
    /// - Parameter flowId: The ID of the flow
    public func removeGuard(for flowId: String) {
        flowGuards.removeValue(forKey: flowId)
    }

    // MARK: - Query Methods

    /// Checks if a specific flow is currently active
    /// - Parameter flowId: The ID of the flow to check
    /// - Returns: `true` if the flow is the active flow
    public func isFlowActive(_ flowId: String) -> Bool {
        state.activeFlow?.id == flowId
    }

    /// Checks if a flow exists in the current flow stack
    /// - Parameter flowId: The ID of the flow to check
    /// - Returns: `true` if the flow is in the stack
    public func isFlowInStack(_ flowId: String) -> Bool {
        state.flowStack.contains { $0.id == flowId }
    }

    /// Returns the depth of the current flow in the hierarchy
    /// - Returns: The depth (0 for root flow, 1 for first subflow, etc.)
    public var flowDepth: Int {
        state.flowStack.count - 1
    }

    /// Gets all available subflows from the current flow
    /// - Returns: Array of available subflows
    public func availableSubflows() -> [any Flow] {
        state.activeFlow?.subflows ?? []
    }

    // MARK: - Legacy Methods (Deprecated)

    /// Legacy method for entering a subflow
    /// - Parameters:
    ///   - subflow: The subflow to enter
    ///   - animated: Whether to animate the transition
    @available(*, deprecated, message: "Use activateSubflow(_:in:animated:) instead")
    public func enterSubflow<F: Flow>(_ subflow: F, animated: Bool = true) {
        activateSubflow(subflow, animated: animated)
    }

    /// Legacy method for exiting a subflow
    /// - Parameter animated: Whether to animate the transition
    @available(*, deprecated, message: "Use deactivateSubflow(_:animated:) instead")
    public func exitSubflow(animated: Bool = true) {
        guard state.flowStack.count > 1 else {
            print("⚠️ Cannot exit: no subflow to exit from")
            return
        }

        let exitingFlowId = state.flowStack.last!.id
        deactivateSubflow(exitingFlowId, animated: animated)
    }
}
