//
//  NavigationCoordinatable.swift
//  RWLabsArchitecture
//
//  Protocol for view models that support navigation coordination
//

import SwiftUI
import Combine

// MARK: - NavigationCoordinatable Protocol

/// Protocol for view models that participate in navigation coordination
///
/// View models conforming to this protocol get automatic navigation capabilities
/// including destination management through `state.destination`, modal/alert presentation,
/// and navigation bindings.
///
/// # Example
/// ```swift
/// class ProductViewModel: BaseViewModel<State, Action, Output, Destination> {
///     struct State: ViewModelState {
///         var destination: Destination?
///         // ... other state properties
///     }
///
///     enum Destination: RouteDestination {
///         case detail(productId: String)
///         case settings
///     }
///
///     func showDetail(productId: String) {
///         state.destination = .detail(productId: productId)
///     }
/// }
/// ```
public protocol NavigationCoordinatable: StateComponent where State: ViewModelState {

    // MARK: - Required Properties

    /// Binding for alert-style destinations
    var alertDestination: Binding<State.Destination?> { get }

    /// Binding for custom alert-style destinations
    var customAlertDestination: Binding<State.Destination?> { get }

    /// Binding for modal-style destinations
    var modalDestination: Binding<State.Destination?> { get }

    /// Binding for push navigation destinations
    var pushDestination: Binding<State.Destination?> { get }

    /// The navigation coordinator instance
    var navigationCoordinator: NavigationCoordinator { get set }

    // MARK: - Required Methods

    /// Sets the navigation coordinator
    /// - Parameter navigationCoordinator: The coordinator to use
    func setCoordinator(_ navigationCoordinator: NavigationCoordinator)

    var isSheetPresented: Binding<Bool> { get }
    var isCustomAlertPresented: Binding<Bool> { get }
}

// MARK: - Default Implementation

public extension NavigationCoordinatable {

    /// Default implementation of setCoordinator
    func setCoordinator(_ navigationCoordinator: NavigationCoordinator) {
        self.navigationCoordinator = navigationCoordinator
    }
}

// MARK: - ViewModel Integration

/// Extension providing navigation integration for ViewModels using state-based destinations
@MainActor
public extension NavigationCoordinatable where Self: ViewModel, Self.ObjectWillChangePublisher == ObservableObjectPublisher {

    // MARK: - Alert Destination

    /// Binding for alert-style destinations
    ///
    /// Filters `state.destination` to only show destinations with `.alert` presentation style
    ///
    /// # Usage
    /// ```swift
    /// .alert(item: viewModel.alertDestination) { destination in
    ///     // Configure alert based on destination
    /// }
    /// ```
    var alertDestination: Binding<State.Destination?> {
        Binding(
            get: {
                guard let dest = self.state.destination,
                      dest.presentationStyle == .alert else { return nil }
                return dest
            },
            set: { newValue in
                self.updateState { $0.destination = newValue }
            }
        )
    }

    // MARK: - Custom Alert Destination

    /// Binding for custom alert-style destinations
    ///
    /// Filters `state.destination` to only show destinations with `.customAlert` presentation style
    ///
    /// # Usage
    /// ```swift
    /// .sheet(item: viewModel.customAlertDestination) { destination in
    ///     CustomAlertView(destination: destination)
    /// }
    /// ```
    var customAlertDestination: Binding<State.Destination?> {
        Binding(
            get: {
                guard let dest = self.state.destination,
                      dest.presentationStyle == .customAlert else { return nil }
                return dest
            },
            set: { newValue in
                self.updateState { $0.destination = newValue }
            }
        )
    }

    // MARK: - Modal Destination

    /// Binding for modal-style destinations
    ///
    /// Filters `state.destination` to only show destinations with `.modal` or `.fullScreen` presentation style
    ///
    /// # Usage
    /// ```swift
    /// .sheet(item: viewModel.modalDestination) { destination in
    ///     DestinationView(destination: destination)
    /// }
    /// ```
    var modalDestination: Binding<State.Destination?> {
        Binding(
            get: {
                guard let dest = self.state.destination,
                      dest.presentationStyle == .modal || dest.presentationStyle == .fullScreen else { return nil }
                return dest
            },
            set: { newValue in
                self.updateState { $0.destination = newValue }
            }
        )
    }

    // MARK: - Push Destination

    /// Binding for push navigation destinations
    ///
    /// Filters `state.destination` to only show destinations with `.push` presentation style
    ///
    /// # Usage
    /// ```swift
    /// .navigationDestination(item: viewModel.pushDestination) { destination in
    ///     DestinationView(destination: destination)
    /// }
    /// ```
    var pushDestination: Binding<State.Destination?> {
        Binding(
            get: {
                guard let dest = self.state.destination,
                      dest.presentationStyle == .push else { return nil }
                return dest
            },
            set: { newValue in
                self.updateState { $0.destination = newValue }
            }
        )
    }

    // MARK: - Convenience Bindings

    /// Boolean binding for sheet presentation
    ///
    /// Returns `true` when a modal destination is set, `false` otherwise
    var isSheetPresented: Binding<Bool> {
        Binding(
            get: { self.modalDestination.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    self.updateState { $0.destination = nil }
                }
            }
        )
    }

    /// Boolean binding for custom alert presentation
    ///
    /// Returns `true` when a custom alert destination is set, `false` otherwise
    var isCustomAlertPresented: Binding<Bool> {
        Binding(
            get: { self.customAlertDestination.wrappedValue != nil },
            set: { newValue in
                if !newValue {
                    self.updateState { $0.destination = nil }
                }
            }
        )
    }
}
