//
//  ViewModelConnections.swift
//  RWLabsArchitecture
//
//  Protocol and helper types for managing ViewModel connections
//  Defines the pattern for parent-child ViewModel relationships
//

import SwiftUI
import Combine

// MARK: - HasConnections Protocol

/// Protocol that ViewModels can adopt to declare they support connections
///
/// ViewModels that manage child ViewModels should conform to this protocol
/// to indicate they have a connections object.
///
/// # Example
/// ```swift
/// class ProductListViewModel: BaseViewModel, HasConnections {
///     typealias ConnectionsType = Connections
///
///     lazy var connections: Connections = {
///         Connections(parent: self)
///     }()
/// }
/// ```
protocol HasConnections: AnyObject {
    /// The type of connections this ViewModel uses
    associatedtype ConnectionsType: ViewModelConnections

    /// The connections instance managing child ViewModels
    var connections: ConnectionsType { get }
}

// MARK: - ViewModelConnections Protocol

/// Base protocol for all Connections classes
///
/// Each ViewModel's Connections class should conform to this protocol.
/// Connections classes centralize the management of child ViewModels,
/// providing a clean separation between parent logic and child coordination.
///
/// # Architecture Benefits
/// - **Organized**: All child ViewModels in one place
/// - **Type-Safe**: Leverages Swift generics for compile-time safety
/// - **Testable**: Easy to mock connections for testing
/// - **Lazy**: Child ViewModels created only when needed
///
/// # Example
/// ```swift
/// class Connections: ViewModelConnections {
///     typealias ParentViewModel = ProductListViewModel
///     weak var parent: ProductListViewModel?
///
///     required init(parent: ProductListViewModel) {
///         self.parent = parent
///     }
///
///     lazy var detailViewModel: ProductDetailViewModel = {
///         let vm = ProductDetailViewModel(initialState: .init())
///         vm.onOutput { [weak parent] output in
///             parent?.handleDetailOutput(output)
///         }
///         return vm
///     }()
/// }
/// ```
public protocol ViewModelConnections: AnyObject {

    // MARK: - Associated Types

    /// The type of parent ViewModel this connections class serves
    associatedtype ParentViewModel: AnyObject

    // MARK: - Required Properties

    /// Weak reference to the parent ViewModel
    ///
    /// Must be weak to avoid retain cycles in the parent-child relationship.
    var parent: ParentViewModel? { get set }

    // MARK: - Required Initializer

    /// Initializes the connections with a parent ViewModel
    /// - Parameter parent: The parent ViewModel that owns this connections instance
    init(parent: ParentViewModel)
}

// MARK: - ObservableObject Extension

extension ObservableObject {

    /// Helper to create connections for a ViewModel
    ///
    /// Provides a type-safe way to create connections instances while
    /// ensuring the parent type matches the connections' required type.
    ///
    /// - Parameter connectionsType: The type of connections to create
    /// - Returns: A new connections instance linked to this ViewModel
    ///
    /// # Example
    /// ```swift
    /// class MyViewModel: ObservableObject {
    ///     lazy var connections: Connections = {
    ///         createConnections(Connections.self)
    ///     }()
    ///
    ///     class Connections: ViewModelConnections {
    ///         weak var parent: MyViewModel?
    ///         required init(parent: MyViewModel) {
    ///             self.parent = parent
    ///         }
    ///     }
    /// }
    /// ```
    func createConnections<T: ViewModelConnections>(_ connectionsType: T.Type) -> T where T.ParentViewModel == Self {
        T(parent: self)
    }
}

// MARK: - Connection Template Documentation

/// Connection Pattern Template
///
/// Use this template when creating Connections classes in your ViewModels:
///
/// ```swift
/// class YourViewModel: BaseViewModel<State, Action, Output, Destination> {
///
///     // MARK: - Connections
///
///     lazy var connections: Connections = {
///         Connections(parent: self)
///     }()
///
///     class Connections: ViewModelConnections {
///         weak var parent: YourViewModel?
///
///         required init(parent: YourViewModel) {
///             self.parent = parent
///         }
///
///         // MARK: - Child ViewModels
///
///         // Singleton child (reused across accesses)
///         lazy var childViewModel: ChildViewModel = {
///             let viewModel = ChildViewModel(initialState: .init())
///             viewModel.onOutput { [weak parent] output in
///                 parent?.handleChildOutput(output)
///             }
///             return viewModel
///         }()
///
///         // Factory method (new instance each call)
///         func createDetailViewModel(id: String) -> DetailViewModel {
///             let viewModel = DetailViewModel(initialState: .init(id: id))
///             viewModel.onOutput { [weak parent] output in
///                 parent?.handleDetailOutput(output)
///             }
///             return viewModel
///         }
///     }
///
///     // MARK: - Output Handlers
///
///     private func handleChildOutput(_ output: ChildViewModel.Output) {
///         switch output {
///         case .someEvent:
///             // Handle child event
///             break
///         }
///     }
/// }
/// ```
///
/// # Patterns
///
/// ## 1. Singleton Children (Lazy Properties)
/// Use for child ViewModels that should be reused:
/// ```swift
/// lazy var settings: SettingsViewModel = {
///     let vm = SettingsViewModel(initialState: .init())
///     vm.onOutput { [weak parent] output in
///         parent?.handleSettingsOutput(output)
///     }
///     return vm
/// }()
/// ```
///
/// ## 2. Factory Methods (Dynamic Creation)
/// Use for creating new child instances:
/// ```swift
/// func createItemDetail(id: Int) -> ItemDetailViewModel {
///     let vm = ItemDetailViewModel(initialState: .init(id: id))
///     vm.onOutput { [weak parent] output in
///         parent?.handleItemDetailOutput(output)
///     }
///     return vm
/// }
/// ```
///
/// ## 3. Tab-Based Children
/// For tab bar or segmented control UIs:
/// ```swift
/// lazy var homeTab: HomeViewModel = { /* ... */ }()
/// lazy var searchTab: SearchViewModel = { /* ... */ }()
/// lazy var profileTab: ProfileViewModel = { /* ... */ }()
/// ```
