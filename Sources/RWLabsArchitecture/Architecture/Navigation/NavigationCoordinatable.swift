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
/// including destination management, modal/alert presentation, and navigation bindings.
///
/// # Example
/// ```swift
/// class ProductViewModel: ViewModel, NavigationCoordinatable {
///     typealias D = ProductDestination
///
///     var navigationCoordinator = NavigationCoordinator<ProductDestination>()
///
///     func showDetail(productId: String) {
///         navigate(to: .detail(productId: productId))
///     }
/// }
/// ```
public protocol NavigationCoordinatable: ObservableObject {

    // MARK: - Associated Type

    /// The destination type for this view model's feature
    associatedtype D: RouteDestination

    // MARK: - Required Properties

    /// The current destination (read/write)
    var destination: D? { get set }

    /// Binding for alert-style destinations
    var alertDestination: Binding<D?> { get }

    /// Binding for custom alert-style destinations
    var customAlerttDestination: Binding<D?> { get }

    /// Binding for modal-style destinations
    var modalDestination: Binding<D?> { get }

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

/// Extension providing navigation integration for ViewModels
@MainActor
public extension NavigationCoordinatable where Self: ViewModel, Self.ObjectWillChangePublisher == ObservableObjectPublisher {

    // MARK: - Outputs

    /// Default outputs publisher (empty for navigation-only view models)
    var outputs: AnyPublisher<Output, Never> {
        Empty().eraseToAnyPublisher()
    }

    // MARK: - Navigation

    /// Navigates to a destination
    ///
    /// - Parameter destination: The destination to navigate to, or `nil` to do nothing
    ///
    /// # Example
    /// ```swift
    /// viewModel.navigate(to: .detail(productId: "123"))
    /// ```
    @MainActor
    func navigate(to destination: D?) {
        navigationCoordinator.navigate(to: destination)
        objectWillChange.send()
    }

    /// The current navigation destination
    ///
    /// Reading returns the top of the navigation stack, or the initial destination if empty.
    /// Setting navigates to the new destination.
    var destination: D? {
        get {
            navigationCoordinator.currentDestination() as? D
        }
        set {
            self.navigate(to: newValue)
        }
    }

    // MARK: - Alert Destination

    /// Binding for alert-style destinations
    ///
    /// Use this binding to present system alerts:
    /// ```swift
    /// .alert(item: viewModel.alertDestination) { destination in
    ///     // Configure alert
    /// }
    /// ```
    var alertDestination: Binding<D?> {
        .init {
            self.navigationCoordinator.presentedDestinations?.presentationStyle == .alert
            ? self.navigationCoordinator.presentedDestinations as? Self.D
                : nil
        } set: { newValue in
            if self.navigationCoordinator.presentedDestinations == nil ||
                self.navigationCoordinator.presentedDestinations?.presentationStyle == .alert {
                self.navigationCoordinator.presentedDestinations = newValue
            }
        }
    }

    // MARK: - Custom Alert Destination

    /// Binding for custom alert-style destinations
    ///
    /// Use this binding to present custom alert views:
    /// ```swift
    /// .sheet(item: viewModel.customAlerttDestination) { destination in
    ///     CustomAlertView(destination: destination)
    /// }
    /// ```
    var customAlerttDestination: Binding<D?> {
        .init {
            self.navigationCoordinator.presentedDestinations?.presentationStyle == .customAlert
            ? self.navigationCoordinator.presentedDestinations as? D
                : nil
        } set: { newValue in
            if self.navigationCoordinator.presentedDestinations == nil ||
                self.navigationCoordinator.presentedDestinations?.presentationStyle == .customAlert {
                self.navigate(to: newValue)
            }
        }
    }

    // MARK: - Modal Destination

    /// Binding for modal-style destinations
    ///
    /// Use this binding to present modal sheets:
    /// ```swift
    /// .sheet(item: viewModel.modalDestination) { destination in
    ///     DestinationView(destination: destination)
    /// }
    /// ```
    var modalDestination: Binding<D?> {
        .init {
            self.navigationCoordinator.presentedDestinations?.presentationStyle == .modal
            ? self.navigationCoordinator.presentedDestinations as? D
                : nil
        } set: { [self] newValue in
            if self.navigationCoordinator.presentedDestinations == nil ||
                self.navigationCoordinator.presentedDestinations?.presentationStyle == .modal {
                self.navigate(to: newValue)
            }
        }
    }
    
    public var isSheetPresented: Binding<Bool> {
           Binding(
            get: { self.modalDestination.wrappedValue != nil },
               set: { newValue in
                   if !newValue {
//                       self.modalDestination.wrappedValue = nil
                   }
               }
           )
       }
    
    public var isCustomAlertPresented: Binding<Bool> {
           Binding(
            get: {
                self.customAlerttDestination.wrappedValue != nil
            },
               set: { newValue in
                   if !newValue {
                       self.customAlerttDestination.wrappedValue = nil
                   }
               }
           )
       }

}
