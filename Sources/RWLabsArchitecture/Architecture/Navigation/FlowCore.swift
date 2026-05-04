//
//  FlowCore.swift
//  RWLabsArchitecture
//
//  Flow-based navigation architecture
//  Defines flows, flow hierarchies, and flow management
//

import Foundation
import Combine

// MARK: - Flow Specializations

/// Protocol for flows that use a tab bar structure
///
/// Tab bar flows can have multiple concurrent subflows, where each tab
/// represents a different subflow that can be active simultaneously.
///
/// # Example
/// ```swift
/// class MainAppFlow: TabBarFlow {
///     enum Tab: Int {
///         case dashboard, entries, chat, more
///     }
///
///     var initialTab: Tab { .entries }
///     var subflows: [any Flow] {
///         [DashboardFlow(), EntriesFlow(), ChatFlow(), MoreFlow()]
///     }
/// }
/// ```
public protocol TabBarFlow: Flow {
    /// The type representing tab items
    associatedtype Tabitem = Int

    /// The initial tab to display when entering this flow
    var initialTab: Tabitem { get }
}

extension TabBarFlow {
    /// Tab bar flows use concurrent activation by default
    public var activationMode: FlowActivationMode {
        .concurrent
    }
}

/// Protocol for individual tab flows within a tab bar
///
/// Each tab in a tab bar is represented by a flow conforming to this protocol.
public protocol BaseTabFlow: NavigationFlow {
    /// The type representing tab items
    associatedtype Tabitem = Int

    /// The tab this flow represents
    var tab: Tabitem { get }
}

extension BaseTabFlow {
    /// Tab flows use exclusive activation by default
    public var activationMode: FlowActivationMode {
        .exclusive
    }
}

/// Protocol for flows that include navigation capabilities
///
/// Navigation flows have their own navigation coordinator for managing
/// the navigation stack within that flow.
public protocol NavigationFlow: Flow {
}

// MARK: - Flow Activation Mode

/// Defines how subflows of a flow should be activated
///
/// This determines whether multiple subflows can be active simultaneously
/// or if only one can be active at a time.
public enum FlowActivationMode: Equatable {
    /// Only one subflow can be active at a time
    /// - Use for: Stack-based navigation, wizards, linear flows
    case exclusive

    /// Multiple subflows can be active concurrently
    /// - Use for: Tab bars, split views, multi-pane layouts
    case concurrent
}

// MARK: - Flow Protocol

/// Represents a logical flow in the application
///
/// A flow is a self-contained unit of navigation representing a feature or
/// user journey. Flows can contain subflows, creating a hierarchical structure.
///
/// # Architecture
/// - **Hierarchical**: Flows can contain subflows
/// - **Lifecycle**: Each flow can validate entry and perform cleanup on exit
/// - **Flexible**: Supports both exclusive and concurrent subflow activation
///

public protocol Flow: Identifiable, ObservableObject where ID == String {
    // MARK: - Required Properties

    /// Unique identifier for the flow
    var id: String { get }

    /// Child flows that can be entered from this flow
    var subflows: [any Flow] { get }

    /// Defines how subflows should be activated
    /// - `.exclusive`: Only one subflow active at a time (default)
    /// - `.concurrent`: Multiple subflows can be active (e.g., tab bar)
    var activationMode: FlowActivationMode { get }

    // MARK: - Lifecycle Methods

    /// Determines if this flow can be entered
    /// - Returns: `true` if the flow can be entered, `false` otherwise
    ///
    /// # Use Cases
    /// - Check authentication state
    /// - Validate prerequisites
    /// - Check feature flags
    func canEnter() -> Bool

    /// Called when exiting the flow
    ///
    /// # Use Cases
    /// - Cleanup resources
    /// - Save state
    /// - Analytics tracking
    func onExit()
}

// MARK: - Flow Default Implementations

extension Flow {

}

extension Flow {
    /// Default: No subflows
    public var subflows: [any Flow] { [] }

    /// Default: Exclusive activation mode
    public var activationMode: FlowActivationMode { .exclusive }

    /// Default: Flow can always be entered
    public func canEnter() -> Bool { true }

    /// Default: No cleanup needed
    public func onExit() {}
}

// MARK: - Flow State

/// Represents the current state of flows in the application
///
/// Maintains the flow hierarchy and tracks transitions for debugging.
public struct FlowState: Equatable {

    // MARK: - Properties

    /// The currently active root flow
    public var currentRootFlow: (any Flow)?

    /// Stack of active flows (parent flows + current flow)
    /// The last element is the currently active flow
    public var flowStack: [any Flow]

    /// History of flow transitions for debugging
    public var transitionHistory: [FlowTransition]

    // MARK: - Initialization

    public init(
        currentRootFlow: (any Flow)? = nil,
        flowStack: [any Flow] = [],
        transitionHistory: [FlowTransition] = []
    ) {
        self.currentRootFlow = currentRootFlow
        self.flowStack = flowStack
        self.transitionHistory = transitionHistory
    }

    // MARK: - Computed Properties

    /// Returns the currently active flow (last in stack)
    public var activeFlow: (any Flow)? {
        flowStack.last
    }

    /// Returns the parent flow of the currently active flow
    public var parentFlow: (any Flow)? {
        guard flowStack.count > 1 else { return nil }
        return flowStack[flowStack.count - 2]
    }

    // MARK: - Equatable

    public static func == (lhs: FlowState, rhs: FlowState) -> Bool {
        lhs.currentRootFlow?.id == rhs.currentRootFlow?.id &&
        lhs.flowStack.map(\.id) == rhs.flowStack.map(\.id)
    }
}

// MARK: - Flow Transition

/// Represents a transition between flows
///
/// Used for debugging, analytics, and understanding flow navigation patterns.
public struct FlowTransition: Identifiable, Equatable {

    // MARK: - Properties

    /// Unique identifier for this transition
    public let id: UUID

    /// The flow we're transitioning from (nil for initial flow)
    public let from: String?

    /// The flow we're transitioning to
    public let to: String

    /// The type of transition
    public let type: TransitionType

    /// When this transition occurred
    public let timestamp: Date

    // MARK: - Transition Types

    /// Types of flow transitions
    public enum TransitionType: Equatable {
        /// Setting a new root flow
        case setRoot

        /// Entering a subflow
        case enterSubflow

        /// Exiting a subflow
        case exitSubflow

        /// Replacing current flow with another
        case replace
    }

    // MARK: - Initialization

    public init(from: String?, to: String, type: TransitionType) {
        self.id = UUID()
        self.from = from
        self.to = to
        self.type = type
        self.timestamp = Date()
    }

    // MARK: - Equatable

    public static func == (lhs: FlowTransition, rhs: FlowTransition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Generic Flow Wrapper

/// Generic wrapper for Flow protocol that preserves type information
///
/// `AnyFlow` is a generic class that wraps a specific flow type while maintaining
/// full type safety for its associated `Destination` type. Unlike true type erasure,
/// this wrapper preserves compile-time type information.
///
/// # Use Cases
/// - **Flow Decorators**: Add behavior while preserving type
/// - **Flow Proxies**: Intercept flow lifecycle methods
/// - **Testing**: Mock specific flows with type safety
///
/// # Important Notes
/// - This is **not** type erasure - it's a generic wrapper
/// - Cannot store different `AnyFlow<>` types in homogeneous collections
/// - For heterogeneous flow collections, use `any Flow` instead
///
/// # Example
/// ```swift
/// // Decorator pattern
/// class LoggingFlow<F: Flow>: AnyFlow<F> {
///     override func canEnter() -> Bool {
///         print("Checking if \(id) can enter")
///         return super.canEnter()
///     }
/// }
///
/// let onboarding = LoggingFlow(OnboardingFlow())
/// // Type: AnyFlow<OnboardingFlow>
/// // Destination: OnboardingDestination (fully typed)
/// ```
///
/// # When to Use `AnyFlow<F>` vs `any Flow`
/// - Use `AnyFlow<F>` when wrapping a **known** specific flow type
/// - Use `any Flow` for **heterogeneous** collections (FlowState, FlowCommand)
public class AnyFlow<F: Flow>: Flow, Equatable {

    public let id: String
    private let _subflows: () -> [any Flow]
    private let _activationMode: () -> FlowActivationMode
    private let _canEnter: () -> Bool
    private let _onExit: () -> Void

    public init(_ flow: F) {
        self.id = flow.id
        self._subflows = { flow.subflows }
        self._activationMode = { flow.activationMode }
        self._canEnter = { flow.canEnter() }
        self._onExit = { flow.onExit() }
    }

    public var subflows: [any Flow] {
        _subflows()
    }

    public var activationMode: FlowActivationMode {
        _activationMode()
    }

    public func canEnter() -> Bool {
        _canEnter()
    }

    public func onExit() {
        _onExit()
    }

    public static func == (lhs: AnyFlow, rhs: AnyFlow) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Flow Command

/// Commands emitted by FlowCoordinator for platform-specific implementations
///
/// Flow coordinators emit these commands to signal flow transitions.
/// Platform-specific code observes and executes these commands.
public enum FlowCommand {
    /// Set a new root flow
    case setRootFlow(any Flow, animated: Bool)

    /// Enter a subflow
    case enterSubflow(any Flow, animated: Bool)

    /// Exit the current subflow
    case exitSubflow(animated: Bool)

    /// Replace the current flow with another
    case replaceFlow(any Flow, animated: Bool)

    /// Reset to the root flow
    case resetToRoot(animated: Bool)
}

// MARK: - Flow Context

/// Encapsulates a flow with its own navigation coordinator and subflow contexts
///
/// Each flow context maintains independent navigation state and manages its subflows.
/// This enables nested navigation hierarchies where each flow has its own navigation stack.
///
/// # Example
/// ```swift
/// let mainAppContext = FlowContext(flow: MainAppFlow())
/// let entriesContext = mainAppContext.activateSubflow(EntriesFlow())
/// ```
@MainActor
public final class FlowContext: ObservableObject, @MainActor Identifiable {

    // MARK: - Properties

    /// Unique identifier matching the flow's ID
    public var id: String { flow.id }

    /// The flow represented by this context
    public let flow: any Flow

    /// Reference to parent flow context (nil for root flows)
    public weak var parentContext: FlowContext?

    /// Active subflow contexts (for concurrent activation mode)
    @Published public private(set) var activeSubflowContexts: [String: FlowContext] = [:]

    /// Currently active exclusive subflow context (for exclusive activation mode)
    @Published public private(set) var activeExclusiveSubflow: FlowContext?

    /// Timestamp when this context was created
    public let createdAt: Date

    /// Whether this context is currently active
    @Published public var isActive: Bool = false

    // MARK: - Initialization

    /// Creates a new flow context
    /// - Parameters:
    ///   - flow: The flow to wrap
    ///   - parentContext: The parent flow context (nil for root flows)
    public init(
        flow: any Flow,
        parentContext: FlowContext? = nil
    ) {
        self.flow = flow
        self.parentContext = parentContext
        self.createdAt = Date()
    }

    // MARK: - Subflow Management

    /// Activates a subflow and returns its context
    ///
    /// Behavior depends on the parent flow's activation mode:
    /// - **Concurrent**: Subflow is activated alongside other active subflows
    /// - **Exclusive**: Previous subflow is deactivated before activating new one
    ///
    /// - Parameter subflow: The subflow to activate
    /// - Returns: The created or existing flow context for the subflow
    public func activateSubflow(_ subflow: any Flow) -> FlowContext? {
        guard flow.subflows.contains(where: { $0.id == subflow.id }) else {
            print("⚠️ Subflow '\(subflow.id)' is not available from flow '\(flow.id)'")
            return nil
        }

        switch flow.activationMode {
        case .concurrent:
            // For concurrent mode, allow multiple active subflows
            if let existingContext = activeSubflowContexts[subflow.id] {
                existingContext.isActive = true
                return existingContext
            }

            let newContext = FlowContext(
                flow: subflow,
                parentContext: self
            )
            newContext.isActive = true
            activeSubflowContexts[subflow.id] = newContext
            return newContext

        case .exclusive:
            // For exclusive mode, deactivate current and activate new
            activeExclusiveSubflow?.isActive = false

            if let existingContext = activeSubflowContexts[subflow.id] {
                existingContext.isActive = true
                activeExclusiveSubflow = existingContext
                return existingContext
            }

            let newContext = FlowContext(
                flow: subflow,
                parentContext: self
            )
            newContext.isActive = true
            activeSubflowContexts[subflow.id] = newContext
            activeExclusiveSubflow = newContext
            return newContext
        }
    }

    /// Deactivates a subflow
    /// - Parameter flowId: The ID of the subflow to deactivate
    public func deactivateSubflow(_ flowId: String) {
        if let context = activeSubflowContexts[flowId] {
            context.isActive = false

            if flow.activationMode == .exclusive {
                activeExclusiveSubflow = nil
            }
        }
    }

    /// Gets the context for a specific subflow
    /// - Parameter flowId: The ID of the subflow
    /// - Returns: The flow context if it exists
    public func subflowContext(for flowId: String) -> FlowContext? {
        activeSubflowContexts[flowId]
    }

    /// Gets all currently active subflow contexts
    /// - Returns: Array of active flow contexts
    public func activeSubflows() -> [FlowContext] {
        switch flow.activationMode {
        case .concurrent:
            return activeSubflowContexts.values.filter { $0.isActive }
        case .exclusive:
            return activeExclusiveSubflow.map { [$0] } ?? []
        }
    }

    /// Deactivates all subflows and clears their contexts
    public func clearSubflows() {
        for context in activeSubflowContexts.values {
            context.isActive = false
            context.flow.onExit()
        }
        activeSubflowContexts.removeAll()
        activeExclusiveSubflow = nil
    }

    // MARK: - Navigation Helpers (Placeholder)

    /// Navigate to a specific destination within this flow's context
    /// - Parameters:
    ///   - destination: The destination to navigate to
    ///   - animated: Whether to animate the navigation
    ///
    /// **Note**: Implementation commented out pending refactoring
    public func navigate(to destination: any ViewModelDestination, animated: Bool = true) {
        // navigator.navigate(to: destination, animated: animated)
    }
}
