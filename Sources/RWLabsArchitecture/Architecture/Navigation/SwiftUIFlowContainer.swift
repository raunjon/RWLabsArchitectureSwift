//
//  SwiftUIFlowContainer.swift
//  RWLabsArchitecture
//
//  SwiftUI containers for flow-based navigation
//  Provides view containers that observe and respond to flow state changes
//

import SwiftUI
import Combine

// MARK: - Flow Container

/// SwiftUI container that manages flow-based UI structure
///
/// Observes `FlowCoordinator` and renders the appropriate flow UI based on
/// the current flow context.
///
/// # Example
/// ```swift
/// FlowContainer(flowCoordinator: appCoordinator.flowCoordinator) { flowContext in
///     if let context = flowContext {
///         switch context.flow {
///         case let onboarding as OnboardingFlow:
///             OnboardingFlowView(flow: onboarding)
///         case let mainApp as MainAppFlow:
///             MainAppFlowView(flow: mainApp)
///         default:
///             EmptyView()
///         }
///     }
/// }
/// ```
@MainActor
public struct FlowContainer<Content: View>: View {

    // MARK: - Properties

    /// The flow coordinator being observed
    @ObservedObject private var flowCoordinator: FlowCoordinator

    /// View builder that creates content based on flow context
    private let content: (FlowContext?) -> Content

    // MARK: - Initialization

    /// Creates a flow container
    /// - Parameters:
    ///   - flowCoordinator: The flow coordinator to observe
    ///   - content: View builder receiving the current flow context
    public init(
        flowCoordinator: FlowCoordinator,
        @ViewBuilder content: @escaping (FlowContext?) -> Content
    ) {
        self.flowCoordinator = flowCoordinator
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        content(flowCoordinator.rootFlowContext)
    }
}

// MARK: - Legacy Flow Container

/// Legacy flow container for backward compatibility
///
/// Use `FlowContainer` with `FlowContext` instead for new code.
@MainActor
public struct LegacyFlowContainer<Content: View>: View {

    // MARK: - Properties

    /// The flow coordinator being observed
    @ObservedObject private var flowCoordinator: FlowCoordinator

    /// View builder that creates content based on flow
    private let content: ((any Flow)?) -> Content

    // MARK: - Initialization

    /// Creates a legacy flow container
    /// - Parameters:
    ///   - flowCoordinator: The flow coordinator to observe
    ///   - content: View builder receiving the current flow
    @available(*, deprecated, message: "Use FlowContainer with FlowContext instead")
    public init(
        flowCoordinator: FlowCoordinator,
        @ViewBuilder content: @escaping ((any Flow)?) -> Content
    ) {
        self.flowCoordinator = flowCoordinator
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        content(flowCoordinator.state.activeFlow)
    }
}

// MARK: - Concurrent Subflow Container

/// Container for rendering concurrent subflows (e.g., tab bar)
///
/// Observes a flow context and renders all active subflows, suitable
/// for tab bar or multi-pane layouts.
///
/// # Example
/// ```swift
/// ConcurrentSubflowContainer(flowContext: mainAppFlowContext) { subflows in
///     TabView {
///         ForEach(subflows) { subflow in
///             SubflowView(flowContext: subflow)
///                 .tabItem {
///                     Label(subflow.flow.title, systemImage: subflow.flow.icon)
///                 }
///         }
///     }
/// }
/// ```
@MainActor
public struct ConcurrentSubflowContainer<Content: View>: View {

    // MARK: - Properties

    /// The flow context being observed
    @ObservedObject private var flowContext: FlowContext

    /// View builder that creates content from active subflows
    private let content: ([FlowContext]) -> Content

    // MARK: - Initialization

    /// Creates a concurrent subflow container
    /// - Parameters:
    ///   - flowContext: The parent flow context to observe
    ///   - content: View builder receiving array of active subflow contexts
    public init(
        flowContext: FlowContext,
        @ViewBuilder content: @escaping ([FlowContext]) -> Content
    ) {
        self.flowContext = flowContext
        self.content = content
    }

    // MARK: - Body

    public var body: some View {
        content(flowContext.activeSubflows())
    }
}

// MARK: - Flow Transition Modifier

/// View modifier that observes flow changes
///
/// Executes a closure whenever the active flow changes, useful for
/// analytics, logging, or side effects.
public struct FlowTransitionModifier: ViewModifier {

    // MARK: - Properties

    /// The flow coordinator being observed
    @ObservedObject var flowCoordinator: FlowCoordinator

    /// Action to perform when flow changes
    let onFlowChange: ((any Flow)?) -> Void

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .onChange(of: flowCoordinator.state.activeFlow?.id) { _, newFlowId in
                onFlowChange(flowCoordinator.state.activeFlow)
            }
    }
}

// MARK: - View Extension

extension View {

    /// Observes flow changes and executes a closure
    ///
    /// - Parameters:
    ///   - flowCoordinator: The flow coordinator to observe
    ///   - action: Closure called when the flow changes
    /// - Returns: The modified view
    ///
    /// # Example
    /// ```swift
    /// ContentView()
    ///     .onFlowChange(appCoordinator.flowCoordinator) { newFlow in
    ///         print("Navigated to flow: \(newFlow?.id ?? "none")")
    ///         analytics.track("flow_change", properties: ["flow_id": newFlow?.id])
    ///     }
    /// ```
    public func onFlowChange(
        _ flowCoordinator: FlowCoordinator,
        perform action: @escaping ((any Flow)?) -> Void
    ) -> some View {
        modifier(FlowTransitionModifier(
            flowCoordinator: flowCoordinator,
            onFlowChange: action
        ))
    }
}

// MARK: - Environment Key

/// Environment key for FlowCoordinator injection
public struct FlowCoordinatorKey: EnvironmentKey {
    public static let defaultValue: FlowCoordinator? = nil
}

extension EnvironmentValues {

    /// Access the flow coordinator from the environment
    ///
    /// # Example
    /// ```swift
    /// struct SomeView: View {
    ///     @Environment(\.flowCoordinator) var flowCoordinator
    ///
    ///     var body: some View {
    ///         Button("Go to Onboarding") {
    ///             flowCoordinator?.setRootFlow(OnboardingFlow())
    ///         }
    ///     }
    /// }
    /// ```
    public var flowCoordinator: FlowCoordinator? {
        get { self[FlowCoordinatorKey.self] }
        set { self[FlowCoordinatorKey.self] = newValue }
    }
}

extension View {

    /// Injects the flow coordinator into the environment
    ///
    /// - Parameter coordinator: The flow coordinator to inject
    /// - Returns: The modified view
    ///
    /// # Example
    /// ```swift
    /// ContentView()
    ///     .flowCoordinator(appCoordinator.flowCoordinator)
    /// ```
    public func flowCoordinator(_ coordinator: FlowCoordinator) -> some View {
        environment(\.flowCoordinator, coordinator)
    }
}
