# Robust Navigation & Connections Architecture

## Problem Statement

You want to:
1. **Avoid optional child ViewModels** in Connections without force unwrapping
2. **Automatically handle push vs modal** navigation by just setting `destination`
3. **Clean architecture** where `self.destination = .someDestination` automatically determines presentation style

## The Solution

### 1. Automatic Push/Modal Navigation ✅ **Already Works!**

The architecture **already handles this automatically** via `PresentationStyle`.

```swift
// ✅ Just set the destination - it automatically pushes or shows modal!
viewModel.destination = .detail(entry: entry)

// The PresentationStyle determines how it's presented:
enum EntriesDestination: RouteDestination {
    case main
    case detail(Entry)
    case filter

    var presentationStyle: PresentationStyle {
        switch self {
        case .main:
            return .push          // ← Pushes onto NavigationStack
        case .detail:
            return .modal         // ← Shows as sheet
        case .filter:
            return .customAlert   // ← Shows as custom alert
        }
    }
}
```

**How it works:**
- `destination` setter calls `navigate(to:)` (NavigationCoordinatable.swift:109)
- `navigate(to:)` calls `navigationCoordinator.navigate(to:)` (line 96)
- `NavigationCoordinator` checks `destination.presentationStyle` and routes accordingly
- `FlowView` protocol binds `.navigationDestination` for push, `.sheet` for modal (BaseViewNavigatable.swift:286-294)

### 2. Non-Optional Child ViewModels in Connections

#### Pattern 1: Lazy Properties (Singleton Children)

**✅ Recommended for reusable children**

```swift
class EntriesViewModel: BaseViewModel<State, Action, Output, Destination> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: EnhancedBaseConnections<EntriesViewModel> {

        // ✅ NON-OPTIONAL, lazy, created once
        lazy var filterViewModel: FilterViewModel = {
            createChild(
                FilterViewModel(initialState: .init()),
                outputHandler: { [weak parent] output in
                    switch output {
                    case .filterApplied(let filter):
                        parent?.applyFilter(filter)
                    }
                }
            )
        }()

        // ✅ Always accessible without unwrapping
        func getFilter() -> FilterViewModel {
            filterViewModel  // No optionals!
        }
    }
}

// Usage - no optionals, no force unwrapping!
let filter = viewModel.connections.filterViewModel
```

#### Pattern 2: Factory Methods (Dynamic Children)

**✅ Recommended for creating new instances**

```swift
class Connections: EnhancedBaseConnections<EntriesViewModel> {

    // ✅ Returns non-optional, newly created ViewModel
    func createEntryDetail(entry: Entry) -> EntryDetailViewModel {
        createChild(
            EntryDetailViewModel(initialState: .init(entry: entry)),
            outputHandler: { [weak parent] output in
                switch output {
                case .entryUpdated(let entry):
                    parent?.updateEntry(entry)
                case .entryDeleted(let id):
                    parent?.deleteEntry(id)
                }
            }
        )
    }
}

// Usage
let detailVM = viewModel.connections.createEntryDetail(entry: entry)
// detailVM is non-optional! ✅
```

#### Pattern 3: State-Bound ViewModels (For Selected Items)

**✅ For ViewModels that depend on optional state**

```swift
struct EntriesState: ViewModelState {
    var entries: [Entry] = []
    var selectedEntry: Entry?  // Optional - user hasn't selected yet
    var isLoading: Bool = false
    var error: (any Error)? = nil
}

class EntriesViewModel: BaseViewModel<EntriesState, Action, Output, Destination> {

    // ✅ Computed property that returns optional
    var selectedEntryViewModel: EntryViewModel? {
        guard let entry = state.selectedEntry else { return nil }
        return connections.createEntryDetail(entry: entry)
    }

    // OR create and cache in connections
    class Connections: EnhancedBaseConnections<EntriesViewModel> {
        private var cachedDetailViewModel: EntryViewModel?

        func detailViewModel(for entry: Entry?) -> EntryViewModel? {
            guard let entry else {
                cachedDetailViewModel = nil
                return nil
            }

            // Create new if entry changed or no cache
            if cachedDetailViewModel?.state.entry.id != entry.id {
                cachedDetailViewModel = createEntryDetail(entry: entry)
            }

            return cachedDetailViewModel
        }
    }
}

// Usage
if let detailVM = viewModel.selectedEntryViewModel {
    // Work with detailVM - still type-safe, no force unwrap
}
```

## Complete Working Example

### Step 1: Define Your ViewModel

```swift
import RWLabsArchitecture

// MARK: - State, Action, Output, Destination

struct EntriesState: ViewModelState {
    var entries: [Entry] = []
    var selectedEntry: Entry?
    var isLoading: Bool = false
    var error: (any Error)? = nil
}

enum EntriesAction: ViewModelAction {
    case fetchEntries
    case selectEntry(Entry)
    case deleteEntry(Int)
}

enum EntriesOutput: ViewModelOutput {
    case entriesFetched
    case entryDeleted(Int)
}

enum EntriesDestination: String, RouteDestination {
    case main
    case detail
    case filter

    static var initialDestination: EntriesDestination { .main }
    static var featureId: String { "entries" }

    var presentationStyle: PresentationStyle {
        switch self {
        case .main:
            return .push
        case .detail:
            return .modal      // ← Shows as sheet
        case .filter:
            return .push       // ← Pushes onto stack
        }
    }
}

// MARK: - ViewModel

class EntriesViewModel: BaseViewModel<EntriesState, EntriesAction, EntriesOutput, EntriesDestination> {

    // ✅ Connections with non-optional children
    lazy var connections: Connections = Connections(parent: self)

    // MARK: - Actions

    override func send(_ action: EntriesAction) {
        switch action {
        case .fetchEntries:
            fetchEntries()

        case .selectEntry(let entry):
            updateState { $0.selectedEntry = entry }
            // ✅ Automatically shows as modal based on PresentationStyle
            destination = .detail

        case .deleteEntry(let id):
            deleteEntry(id)
        }
    }

    override func onAppear() {
        send(.fetchEntries)
    }

    // MARK: - Business Logic

    private func fetchEntries() {
        // Fetch logic...
    }

    private func deleteEntry(_ id: Int) {
        updateState {
            $0.entries.removeAll { $0.id == id }
        }
        sendOutput(.entryDeleted(id))
    }

    // MARK: - Output Handlers

    func handleFilterApplied(_ filter: Filter) {
        // Apply filter to entries
    }

    func handleEntryUpdated(_ entry: Entry) {
        updateState {
            if let index = $0.entries.firstIndex(where: { $0.id == entry.id }) {
                $0.entries[index] = entry
            }
        }
    }

    // MARK: - Connections

    class Connections: EnhancedBaseConnections<EntriesViewModel> {

        // ✅ NON-OPTIONAL singleton child
        lazy var filterViewModel: FilterViewModel = {
            createChild(
                FilterViewModel(initialState: .init()),
                outputHandler: { [weak parent] output in
                    switch output {
                    case .filterApplied(let filter):
                        parent?.handleFilterApplied(filter)
                    }
                }
            )
        }()

        // ✅ Factory for detail ViewModels
        func createEntryDetail(entry: Entry) -> EntryDetailViewModel {
            createChild(
                EntryDetailViewModel(initialState: .init(entry: entry)),
                outputHandler: { [weak parent] output in
                    switch output {
                    case .entryUpdated(let entry):
                        parent?.handleEntryUpdated(entry)
                    }
                }
            )
        }

        // ✅ Get detail ViewModel for selected entry (optional but safe)
        var selectedEntryViewModel: EntryDetailViewModel? {
            guard let entry = parent?.state.selectedEntry else { return nil }
            return createEntryDetail(entry: entry)
        }
    }
}
```

### Step 2: Use in View

```swift
struct EntriesTabView: FlowView {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var flow: EntriesFlow
    @ObservedObject var viewModel: EntriesViewModel
    @EnvironmentObject var navigator: SwiftUINavigator

    var content: some View {
        EntriesView(viewModel: viewModel)
            .navigationTitle("Entries")
    }

    // ✅ FlowView automatically handles push vs modal
    func destinationView(for destination: EntriesDestination) -> some View {
        switch destination {
        case .main:
            EmptyView()

        case .detail:
            // ✅ No force unwrap needed!
            if let detailVM = viewModel.connections.selectedEntryViewModel {
                EntryDetailView(viewModel: detailVM)
            } else {
                EmptyView()
            }

        case .filter:
            // ✅ Non-optional access!
            FilterView(viewModel: viewModel.connections.filterViewModel)
        }
    }
}
```

## Key Benefits

### ✅ No Optional Unwrapping
```swift
// ❌ OLD
if let vm = viewModel.connections.filterViewModel {
    vm.send(.apply)  // Annoying optional chaining
}

// ✅ NEW
viewModel.connections.filterViewModel.send(.apply)  // Direct access!
```

### ✅ Automatic Presentation Style
```swift
// ✅ Just set destination - automatic push/modal!
viewModel.destination = .detail  // Shows as modal (based on PresentationStyle)
viewModel.destination = .filter  // Pushes onto stack
```

### ✅ Type-Safe Connections
```swift
// ✅ Compile-time safety
let filter: FilterViewModel = viewModel.connections.filterViewModel
// No runtime crashes, no force unwrapping!
```

### ✅ Clean Output Handling
```swift
class Connections: EnhancedBaseConnections<ParentViewModel> {
    lazy var child: ChildViewModel = {
        createChild(
            ChildViewModel(initialState: .init()),
            outputHandler: { [weak parent] output in
                // Automatic forwarding to parent
                parent?.handleChildOutput(output)
            }
        )
    }()
}
```

## Advanced Patterns

### Pattern: Cross-Flow Navigation (Embedding)

For your CheckIn → Entries example:

```swift
enum CheckInDestination: RouteDestination {
    case main
    case entries(ticket: String)  // Embed EntriesView in CheckIn flow

    var presentationStyle: PresentationStyle {
        switch self {
        case .main:
            return .push
        case .entries:
            return .modal  // Or .push to embed in same stack
        }
    }
}

class CheckInViewModel: BaseViewModel<State, Action, Output, CheckInDestination> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: EnhancedBaseConnections<CheckInViewModel> {

        // ✅ Factory to create EntriesViewModel with ticket
        func createEntriesView(ticket: String) -> EntriesViewModel {
            EntriesViewModel(initialState: .init(ticket: ticket))
        }
    }

    override func send(_ action: Action) {
        switch action {
        case .checkIn(let ticket):
            // ✅ Automatically shows as modal
            destination = .entries(ticket: ticket)
        }
    }
}

// In View
func destinationView(for destination: CheckInDestination) -> some View {
    switch destination {
    case .main:
        content.anyView()
    case .entries(let ticket):
        // ✅ Create embedded EntriesView
        EntriesView(
            viewModel: viewModel.connections.createEntriesView(ticket: ticket)
        ).anyView()
    }
}
```

## Summary

### What You Get:

1. **✅ Automatic Push/Modal** - Set `destination`, presentation style handled automatically
2. **✅ No Force Unwrapping** - Lazy properties give non-optional ViewModels
3. **✅ Type Safety** - Compile-time guarantees, no runtime crashes
4. **✅ Clean Architecture** - Separation of concerns, testable, maintainable

### Migration Path:

1. Use `EnhancedBaseConnections` instead of `BaseConnections`
2. Make child ViewModels `lazy var` properties (non-optional)
3. Use `createChild()` helper for automatic output handling
4. Set `destination` directly - presentation style is automatic

No changes needed to the core architecture - it already supports everything you need!
