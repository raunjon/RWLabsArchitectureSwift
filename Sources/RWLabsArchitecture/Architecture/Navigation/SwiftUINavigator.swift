//
//  SwiftUINavigator.swift
//  RWLabsArchitecture
//
//  SwiftUI-specific navigation implementation
//  Bridges between platform-agnostic navigation coordinator and SwiftUI views
//

import SwiftUI
import Combine

// MARK: - SwiftUI Navigator

/// Platform-specific navigator for SwiftUI
///
/// `SwiftUINavigator` observes `NavigationCoordinator` commands and provides
/// bindings for SwiftUI's navigation APIs (NavigationStack, sheets, alerts, etc.)
///
/// # Architecture
/// - Observes navigation commands from the coordinator
/// - Provides typed path bindings for NavigationStack
/// - Logs navigation events for debugging
///
/// # Example
/// ```swift
/// struct ProductListView: View {
///     @StateObject var viewModel: ProductViewModel
///     @StateObject var navigator: SwiftUINavigator<ProductDestination>
///
///     init(viewModel: ProductViewModel) {
///         self._viewModel = StateObject(wrappedValue: viewModel)
///         self._navigator = StateObject(wrappedValue:
///             SwiftUINavigator(coordinator: viewModel.navigationCoordinator)
///         )
///     }
///
///     var body: some View {
///         NavigationStack(path: navigator.pathBinding(for: ProductDestination.self)) {
///             // Your view content
///         }
///     }
/// }
/// ```
@MainActor
public final class SwiftUINavigator: ObservableObject {

    // MARK: - Properties

    /// Reference to the navigation coordinator
    public var coordinator: NavigationCoordinator

    /// Cancellables for subscriptions
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    /// Creates a new SwiftUI navigator
    /// - Parameter coordinator: The navigation coordinator to observe
    public init(coordinator: NavigationCoordinator) {
        self.coordinator = coordinator
        observeCommands()
    }

    // MARK: - Path Bindings

    /// Returns a typed path binding for NavigationStack
    ///
    /// This binding allows SwiftUI's NavigationStack to:
    /// - Read the current navigation path from the coordinator
    /// - Update the coordinator when the user navigates back (e.g., swipe gesture)
    ///
    /// - Parameter type: The destination type
    /// - Returns: A binding to the navigation path array
    ///
    /// # Example
    /// ```swift
    /// NavigationStack(path: navigator.pathBinding(for: ProductDestination.self)) {
    ///     ProductListView()
    ///         .navigationDestination(for: ProductDestination.self) { destination in
    ///             ProductDetailView(destination: destination)
    ///         }
    /// }
    /// ```
    public func pathBinding<D: RouteDestination>(for type: D.Type) -> Binding<NavigationPath> {
        Binding(
            get: {
                self.coordinator.path
            },
            set: { newPath in
                // When SwiftUI modifies the path (e.g., user swipes back),
                // sync it back to the coordinator
                self.coordinator.updatePath(for: type, path: newPath)
            }
        )
    }

    // MARK: - Command Observation

    /// Observes navigation commands from the coordinator
    ///
    /// In SwiftUI, most navigation is handled declaratively through state changes.
    /// This method primarily logs commands for debugging purposes.
    private func observeCommands() {
        coordinator.commands
            .sink { [weak self] command in
                self?.handleCommand(command)
            }
            .store(in: &cancellables)
    }

    /// Handles a navigation command
    ///
    /// In SwiftUI, navigation is declarative and driven by state changes.
    /// This method logs commands for debugging and could be extended for
    /// side effects or analytics.
    ///
    /// - Parameter command: The navigation command to handle
    private func handleCommand(_ command: NavigationCommand) {
        switch command {
        case .navigate(let destination, let animated):
            print("📍 Navigate to: \(destination.id) (animated: \(animated))")

        case .pop(let animated):
            print("📍 Pop (animated: \(animated))")

        case .popToRoot(let featureId, let animated):
            print("📍 Pop to root for feature: \(featureId) (animated: \(animated))")

        case .dismiss(let animated):
            print("📍 Dismiss (animated: \(animated))")

        case .reset:
            print("📍 Reset navigation")
        }
    }
}

// MARK: - Environment Key (Commented Out)

// Alternative approach: Inject coordinator via environment
// Uncomment if you prefer environment-based dependency injection

//private struct NavigationCoordinatorKey: @preconcurrency EnvironmentKey {
//    @MainActor
//    static let defaultValue = NavigationCoordinator()
//}
//
//public extension EnvironmentValues {
//    var navigationCoordinator: NavigationCoordinator {
//        get { self[NavigationCoordinatorKey.self] }
//        set { self[NavigationCoordinatorKey.self] = newValue }
//    }
//}
