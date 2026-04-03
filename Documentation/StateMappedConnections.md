# State-Mapped Connections Pattern

## Overview

The **State-Mapped Connections** pattern solves the problem of managing child ViewModels without optionals or force unwrapping, while allowing state mutations through direct property access.

## The Problem

```swift
// ❌ OLD: Optional child ViewModels
struct EntriesState {
    var entries: [Entry] = []
}

class EntriesViewModel: BaseViewModel<...> {
    var filterViewModel: FilterViewModel?  // Always optional!

    // Can't mutate without recreating
    filterViewModel?.send(.apply)  // Optional chaining
}
```

## The Solution

### 1. Store ViewModels in State

```swift
struct EntriesState: ViewModelState {
    var entries: [Entry] = []
    var isLoading: Bool = false
    var error: (any Error)? = nil

    // ✅ Child ViewModels stored in state
    var filterViewModel: FilterViewModel?
    var selectedEntryViewModel: EntryDetailViewModel?
}
```

### 2. Access via Connections with `getOrCreate`

```swift
class EntriesViewModel: BaseViewModel<EntriesState, Action, Output, Destination> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: EnhancedBaseConnections<EntriesViewModel> {

        // ✅ Non-optional access!
        var filterViewModel: FilterViewModel {
            getOrCreate(
                at: \.filterViewModel,
                factory: { FilterViewModel(initialState: .init()) },
                outputHandler: { [weak parent] output in
                    switch output {
                    case .filterApplied(let filter):
                        parent?.applyFilter(filter)
                    }
                }
            )
        }

        // ✅ Optional access for selection-dependent ViewModels
        var selectedEntryViewModel: EntryDetailViewModel? {
            guard let entry = parent?.state.selectedEntry else { return nil }

            return getOrCreate(
                at: \.selectedEntryViewModel,
                factory: { EntryDetailViewModel(initialState: .init(entry: entry)) },
                outputHandler: { [weak parent] output in
                    parent?.handleDetailOutput(output)
                }
            )
        }

        // ✅ Factory for dynamic creation (not state-stored)
        func createEntryDetail(entry: Entry) -> EntryDetailViewModel {
            createChild(
                EntryDetailViewModel(initialState: .init(entry: entry)),
                outputHandler: { [weak parent] output in
                    parent?.handleDetailOutput(output)
                }
            )
        }

        // ✅ Clear from state when done
        func clearFilter() {
            clear(at: \.filterViewModel)
        }
    }
}
```

## Benefits

### ✅ No Force Unwrapping
```swift
// Direct access, no optionals!
viewModel.connections.filterViewModel.send(.apply)
```

### ✅ State Persistence
```swift
// ViewModel is created once and stored in state
let filter1 = viewModel.connections.filterViewModel
let filter2 = viewModel.connections.filterViewModel
// filter1 === filter2  ✅ Same instance!
```

### ✅ Mutability via State
```swift
// Update child ViewModel through state
viewModel.updateState { state in
    state.filterViewModel?.send(.clear)
}
```

### ✅ Automatic Output Handling
```swift
// Output handler configured once at creation
var filterViewModel: FilterViewModel {
    getOrCreate(
        at: \.filterViewModel,
        factory: { FilterViewModel(initialState: .init()) },
        outputHandler: { [weak parent] output in
            // Automatically handles outputs!
            parent?.applyFilter(output)
        }
    )
}
```

### ✅ Clean Lifecycle Management
```swift
// Clear when no longer needed
connections.clearFilter()  // Sets state.filterViewModel = nil
```

## Complete Example

```swift
import RWLabsArchitecture

// MARK: - State

struct EntriesState: ViewModelState {
    var entries: [Entry] = []
    var selectedEntry: Entry?
    var isLoading: Bool = false
    var error: (any Error)? = nil

    // Child ViewModels stored in state
    var filterViewModel: FilterViewModel?
    var selectedEntryViewModel: EntryDetailViewModel?
}

// MARK: - ViewModel

class EntriesViewModel: BaseViewModel<EntriesState, EntriesAction, EntriesOutput, EntriesDestination> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: EnhancedBaseConnections<EntriesViewModel> {

        // Singleton child - non-optional
        var filterViewModel: FilterViewModel {
            getOrCreate(
                at: \.filterViewModel,
                factory: { FilterViewModel(initialState: .init()) },
                outputHandler: { [weak parent] output in
                    switch output {
                    case .filterApplied(let filter):
                        parent?.applyFilter(filter)
                    }
                }
            )
        }

        // Selection-dependent child - optional
        var selectedEntryViewModel: EntryDetailViewModel? {
            guard let entry = parent?.state.selectedEntry else { return nil }

            return getOrCreate(
                at: \.selectedEntryViewModel,
                factory: { EntryDetailViewModel(initialState: .init(entry: entry)) },
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

        // Factory for dynamic creation
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

        func clearFilter() {
            clear(at: \.filterViewModel)
        }
    }

    // MARK: - Actions

    override func send(_ action: EntriesAction) {
        switch action {
        case .fetchEntries:
            fetchEntries()

        case .selectEntry(let entry):
            updateState { $0.selectedEntry = entry }
            destination = .detail  // Shows selected entry detail

        case .clearSelection:
            updateState { $0.selectedEntry = nil }
            connections.clear(at: \.selectedEntryViewModel)

        case .applyFilter:
            // ✅ Non-optional access!
            connections.filterViewModel.send(.apply)
        }
    }

    override func onAppear() {
        send(.fetchEntries)
    }

    // MARK: - Output Handlers

    private func applyFilter(_ filter: Filter) {
        updateState {
            // Filter entries based on filter
        }
    }

    private func updateEntry(_ entry: Entry) {
        updateState {
            if let index = $0.entries.firstIndex(where: { $0.id == entry.id }) {
                $0.entries[index] = entry
            }
        }
    }

    private func deleteEntry(_ id: Int) {
        updateState {
            $0.entries.removeAll { $0.id == id }
        }
    }
}

// MARK: - Usage in View

struct EntriesTabView: FlowView {
    @ObservedObject var viewModel: EntriesViewModel

    var content: some View {
        VStack {
            // ✅ Non-optional access to filter
            FilterBar(viewModel: viewModel.connections.filterViewModel)

            EntriesList(viewModel: viewModel)
        }
    }

    func destinationView(for destination: EntriesDestination) -> some View {
        switch destination {
        case .main:
            EmptyView()

        case .detail:
            // ✅ Safe optional unwrapping
            if let detailVM = viewModel.connections.selectedEntryViewModel {
                EntryDetailView(viewModel: detailVM)
            } else {
                EmptyView()
            }

        case .filter:
            // ✅ Non-optional!
            FilterView(viewModel: viewModel.connections.filterViewModel)
        }
    }
}
```

## API Reference

### EnhancedBaseConnections Methods

#### `getOrCreate(at:factory:)`
Gets or creates a child ViewModel stored in state (no output handling).

```swift
var myChild: ChildViewModel {
    getOrCreate(at: \.myChildViewModel) {
        ChildViewModel(initialState: .init())
    }
}
```

#### `getOrCreate(at:factory:outputHandler:)`
Gets or creates a child ViewModel with automatic output handling.

```swift
var myChild: ChildViewModel {
    getOrCreate(
        at: \.myChildViewModel,
        factory: { ChildViewModel(initialState: .init()) },
        outputHandler: { [weak parent] output in
            parent?.handleChildOutput(output)
        }
    )
}
```

#### `createChild(_:outputHandler:)`
Creates a new child ViewModel (not stored in state).

```swift
func createDetail(id: Int) -> DetailViewModel {
    createChild(
        DetailViewModel(initialState: .init(id: id)),
        outputHandler: { [weak parent] output in
            parent?.handleOutput(output)
        }
    )
}
```

#### `clear(at:)`
Clears a child ViewModel from state.

```swift
func clearFilter() {
    clear(at: \.filterViewModel)
}
```

## When to Use Each Pattern

### State-Stored (`getOrCreate`)
Use when:
- Child ViewModel should persist across accesses
- State needs to be preserved
- Want non-optional access
- Example: Filter, Settings

### Factory (`createChild`)
Use when:
- Need new instance each time
- No state persistence required
- Example: Detail views, temporary screens

### Optional State-Stored
Use when:
- Depends on optional parent state
- May not always exist
- Example: Selected item detail

## Summary

**State-Mapped Connections provides:**
- ✅ Non-optional child ViewModels
- ✅ State persistence and mutability
- ✅ Automatic output handling
- ✅ Clean lifecycle management
- ✅ Type-safe access
- ✅ No force unwrapping

**Your architecture now supports:**
1. `viewModel.destination = .detail` → Automatic push/modal ✅
2. `viewModel.connections.filterViewModel` → Non-optional access ✅
3. State-mapped child ViewModels → Fully mutable ✅
