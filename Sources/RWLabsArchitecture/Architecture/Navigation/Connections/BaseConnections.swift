//
//  BaseConnections.swift
//  RWLabsArchitecture
//
//  Base implementation of ViewModelConnections
//  Provides minimal boilerplate for connections classes
//

import SwiftUI
import Combine
import CasePathsCore

// MARK: - BaseConnections

/// Base implementation of ViewModelConnections protocol
///
/// `BaseConnections` provides a minimal implementation of the `ViewModelConnections`
/// protocol, handling the parent reference management. Subclass this to create
/// connections for your ViewModels.
///
/// # Usage
///
/// ## Basic Subclassing
/// ```swift
/// class ProductListViewModel: BaseViewModel<State, Action, Output, Destination> {
///
///     lazy var connections: Connections = {
///         Connections(parent: self)
///     }()
///
///     class Connections: BaseConnections<ProductListViewModel> {
///         // Add your child ViewModels here
///
///         lazy var detailViewModel: ProductDetailViewModel = {
///             let vm = ProductDetailViewModel(initialState: .init())
///             vm.onOutput { [weak parent] output in
///                 parent?.handleDetailOutput(output)
///             }
///             return vm
///         }()
///     }
/// }
/// ```
///
/// ## With Multiple Children
/// ```swift
/// class MainAppViewModel: BaseViewModel<State, Action, Output, Destination> {
///
///     class Connections: BaseConnections<MainAppViewModel> {
///
///         // Tab ViewModels (singleton, reused)
///         lazy var homeTab: HomeViewModel = {
///             let vm = HomeViewModel(initialState: .init())
///             vm.onOutput { [weak parent] output in
///                 parent?.handleHomeOutput(output)
///             }
///             return vm
///         }()
///
///         lazy var settingsTab: SettingsViewModel = {
///             let vm = SettingsViewModel(initialState: .init())
///             vm.onOutput { [weak parent] output in
///                 parent?.handleSettingsOutput(output)
///             }
///             return vm
///         }()
///
///         // Factory for dynamic creation
///         func createProductDetail(id: String) -> ProductDetailViewModel {
///             let vm = ProductDetailViewModel(initialState: .init(productId: id))
///             vm.onOutput { [weak parent] output in
///                 parent?.handleProductDetailOutput(output)
///             }
///             return vm
///         }
///     }
/// }
/// ```
///
/// # Benefits
/// - **Less Boilerplate**: No need to manually implement parent property
/// - **Type-Safe**: Generic over ParentViewModel type
/// - **Memory Safe**: Parent is automatically weak to prevent retain cycles
/// - **Main Actor Isolated**: Safe for SwiftUI integration
@MainActor
open class ViewModelConnections<ParentViewModel: ViewModel>: @MainActor Connectable {

    // MARK: - Properties
//    public typealias C1<From: ViewModelState, Case: CasePathable> = CaseConnection<From, ParentViewModel, Case>

    /// Weak reference to the parent ViewModel
    ///
    /// Automatically managed by BaseConnections to prevent retain cycles.
    public weak var parent: ParentViewModel? {
        didSet {
            print("🔧 BaseConnections.parent didSet: \(parent != nil ? "set" : "nil")")
        }
    }

    // MARK: - Initialization

    /// Initializes the connections with a parent ViewModel
    ///
    /// - Parameter parent: The parent ViewModel that owns this connections instance
    ///
    /// # Example
    /// ```swift
    /// let connections = Connections(parent: model)
    /// ```
//    required public init(parent: ParentViewModel) {
//        self.parent = parent
//    }

    required public init(parent: ParentViewModel) {
        self.parent = parent

        // Setup connections - subclasses should override setupConnections()
        // to access their lazy connection properties, which will force evaluation
        // and allow wireConnections() to find them
        setupConnections()

        // Now wire the connections that were accessed in setupConnections()
        wireConnections()
    }

    /// Override this method in subclasses to access lazy connection properties
    /// This forces their evaluation so wireConnections() can find them.
    ///
    /// # Example
    /// ```swift
    /// override func setupConnections() {
    ///     _ = entry  // Access the lazy var to force evaluation
    ///     _ = filter
    /// }
    /// ```
    ///
    /// **Note**: This is only needed for connections using `.connect(state:case:)`
    /// which return `PresentedCaseComponentConnection`. Regular `Connection` objects
    /// will auto-wire themselves on first access.
    open func setupConnections() {
        // Default implementation does nothing
        // Subclasses override to access their lazy connection properties
    }
    /// Helper to set up a connection with parent reference
    ///
    /// Use in lazy var closures:
    /// ```swift
    /// lazy var filter: Connection<FilterViewModel> = {
    ///     self.setup(
    ///         Connection<FilterViewModel> { output in ... }
    ///         .connect(to: \.filterViewModel)
    ///     )
    /// }()
    /// ```
    public func setup<VM: ViewModel>(_ connection: Connection<VM>) -> Connection<VM> where ParentViewModel: ViewModel {
        if let parent = parent {
            connection._setupParent(parent)
        }
        return connection
    }
    
    private func wireConnections() {
        guard let parent = parent as? any ViewModel else {
            print("⚠️ BaseConnections.wireConnections: parent is not StateComponent")
            return
        }

        print("🔍 BaseConnections.wireConnections: Starting wire connections for \(type(of: self))")

        let mirror = Mirror(reflecting: self)

        var connectionCount = 0
        for child in mirror.children {
            print("   Checking child: \(child.label ?? "unlabeled"), type: \(type(of: child.value))")

            if let connection = child.value as? AnyConnection {
                connectionCount += 1
                print("   ✅ Found AnyConnection #\(connectionCount): \(child.label ?? "unlabeled")")
                connection._setupParent(parent)
            }
        }

        print("🔍 BaseConnections.wireConnections: Found \(connectionCount) connections")
    }
}

// MARK: - Example Implementations

#if DEBUG

/// Example 1: Simple Parent with Single Child
///
/// Demonstrates basic parent-child connection with output handling.
class ExampleParentViewModel: ObservableObject {

    // MARK: - State

    @Published var state = State()

    struct State {
        var items: [String] = []
        var isLoading: Bool = false
    }

    // MARK: - Connections

    lazy var connections: Connections = {
        Connections(parent: self)
    }()

    class Connections: Connectable {
        weak var parent: ExampleParentViewModel?

        required init(parent: ExampleParentViewModel) {
            self.parent = parent
        }

        // Singleton child connection
        lazy var detailViewModel: ExampleChildViewModel = {
            let model = ExampleChildViewModel()
            model.onUpdate { [weak parent] data in
                parent?.handleChildUpdate(data)
            }
            return model
        }()
    }

    // MARK: - Output Handlers

    private func handleChildUpdate(_ data: String) {
        state.items.append(data)
    }
}

class ExampleChildViewModel: ObservableObject {
    @Published var data: String = ""

    private var updateHandler: ((String) -> Void)?

    func onUpdate(_ handler: @escaping (String) -> Void) {
        self.updateHandler = handler
    }

    func sendUpdate(_ data: String) {
        updateHandler?(data)
    }
}

// MARK: -

/// Example 2: Parent with Multiple Tab Children
///
/// Demonstrates tab-based navigation with multiple concurrent children.
class ExampleTabViewModel: ObservableObject {

    // MARK: - Types

    enum Tab {
        case home, settings, profile
    }

    // MARK: - State

    @Published var selectedTab: Tab = .home

    // MARK: - Connections

    lazy var connections: Connections = {
        Connections(parent: self)
    }()

    class Connections: Connectable {
        weak var parent: ExampleTabViewModel?

        required init(parent: ExampleTabViewModel) {
            self.parent = parent
        }

        // Tab ViewModels (created once, reused)
        lazy var home: HomeViewModel = {
            let vm = HomeViewModel()
            // Setup output handling if needed
            return vm
        }()

        lazy var settings: SettingsViewModel = {
            let vm = SettingsViewModel()
            // Setup output handling if needed
            return vm
        }()

        lazy var profile: ProfileViewModel = {
            let vm = ProfileViewModel()
            // Setup output handling if needed
            return vm
        }()
    }
}

class HomeViewModel: ObservableObject {}
class SettingsViewModel: ObservableObject {}
class ProfileViewModel: ObservableObject {}

// MARK: -

/// Example 3: Parent with Dynamic Child Creation
///
/// Demonstrates factory pattern for creating child ViewModels on demand.
class ExampleListViewModel: ObservableObject {

    // MARK: - Types

    struct Item: Identifiable {
        let id: Int
        let name: String
    }

    // MARK: - State

    @Published var items: [Item] = []

    // MARK: - Connections

    lazy var connections: Connections = {
        Connections(parent: self)
    }()

    class Connections: Connectable {
        weak var parent: ExampleListViewModel?

        required init(parent: ExampleListViewModel) {
            self.parent = parent
        }

        // Factory method for creating detail ViewModels
        // Creates a new instance each time it's called
        func itemDetail(for item: Item) -> ItemDetailViewModel {
            let model = ItemDetailViewModel(item: item)
            model.onUpdate { [weak parent] updatedItem in
                parent?.handleItemUpdate(updatedItem)
            }
            return model
        }
    }

    // MARK: - Output Handlers

    private func handleItemUpdate(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        }
    }
}

class ItemDetailViewModel: ObservableObject {
    let item: ExampleListViewModel.Item
    private var updateHandler: ((ExampleListViewModel.Item) -> Void)?

    init(item: ExampleListViewModel.Item) {
        self.item = item
    }

    func onUpdate(_ handler: @escaping (ExampleListViewModel.Item) -> Void) {
        self.updateHandler = handler
    }
}

#endif
