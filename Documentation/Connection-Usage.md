# Connection<VM> Usage Guide

## Overview

`Connection<VM>` provides a fluent API for managing state-mapped child ViewModels with clean syntax and automatic setup.

## Basic Pattern

```swift
Connection<FilterViewModel> { output in
    parent?.applyFilter(output)
}
.connect(to: \.filterViewModel)
.factory { FilterViewModel(initialState: .init()) }
```

## Complete Example

### 1. Define Your State

```swift
struct EntriesState: ViewModelState {
    var entries: [Entry] = []
    var selectedEntry: Entry?
    var isLoading: Bool = false
    var error: (any Error)? = nil

    // ✅ Child ViewModels stored in state
    var filterViewModel: FilterViewModel?
    var selectedEntryViewModel: EntryDetailViewModel?
}
```

### 2. Create Connections Class

```swift
class EntriesViewModel: BaseViewModel<EntriesState, EntriesAction, EntriesOutput, EntriesDestination> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: BaseConnections<EntriesViewModel> {

        // ✅ Non-optional ViewModel (always available)
        lazy var filter: Connection<FilterViewModel> = {
            setup(
                Connection<FilterViewModel> { [weak parent] output in
                    switch output {
                    case .filterApplied(let filter):
                        parent?.applyFilter(filter)
                    }
                }
                .connect(to: \.filterViewModel)
                .factory { FilterViewModel(initialState: .init()) }
            )
        }()

        // ✅ Optional ViewModel (depends on selection)
        lazy var selectedEntry: Connection<EntryDetailViewModel> = {
            setup(
                Connection<EntryDetailViewModel> { [weak parent] output in
                    switch output {
                    case .entryUpdated(let entry):
                        parent?.updateEntry(entry)
                    case .entryDeleted(let id):
                        parent?.deleteEntry(id)
                    }
                }
                .connect(to: \.selectedEntryViewModel)
                .factory {
                    guard let entry = parent?.state.selectedEntry else {
                        fatalError("Cannot create EntryDetailViewModel without selected entry")
                    }
                    return EntryDetailViewModel(initialState: .init(entry: entry))
                }
            )
        }()
    }
}
```

### 3. Use in Your ViewModel

```swift
class EntriesViewModel: BaseViewModel<...> {

    override func send(_ action: EntriesAction) {
        switch action {
        case .applyFilter:
            // ✅ Transparent access - no .model needed!
            connections.filter.send(.apply)

        case .selectEntry(let entry):
            updateState { $0.selectedEntry = entry }
            destination = .detail

        case .clearSelection:
            updateState { $0.selectedEntry = nil }
            connections.selectedEntry.clear()
        }
    }

    private func applyFilter(_ filter: Filter) {
        updateState {
            // Apply filter logic
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
```

### 4. Use in SwiftUI Views

```swift
struct EntriesView: View {
    @ObservedObject var model: EntriesViewModel

    var body: some View {
        VStack {
            // ✅ Direct access to child ViewModel
            FilterBar(model: model.connections.filter.model)

            List(model.state.entries) { entry in
                EntryRow(entry: entry)
                    .onTapGesture {
                        model.send(.selectEntry(entry))
                    }
            }
        }
        .sheet(item: $model.destination) { destination in
            switch destination {
            case .detail:
                // ✅ Access child ViewModel for detail
                if let detailVM = model.state.selectedEntryViewModel {
                    EntryDetailView(model: detailVM)
                }
            }
        }
    }
}
```

## Features

### ✅ Transparent Access

Use `@dynamicMemberLookup` to access ViewModel members directly:

```swift
// Instead of:
connections.filter.model.send(.apply)

// You can write:
connections.filter.send(.apply)
connections.filter.state.searchText
```

### ✅ State Persistence

ViewModels are created once and stored in state:

```swift
let filter1 = model.connections.filter
let filter2 = model.connections.filter
// filter1 === filter2  ✅ Same instance!
```

### ✅ Automatic Output Handling

Output handler configured once at creation:

```swift
Connection<FilterViewModel> { output in
    // Automatically called when child emits output
    parent?.applyFilter(output)
}
```

### ✅ Lifecycle Management

Clear ViewModels when no longer needed:

```swift
connections.filter.clear()  // Removes from state
```

### ✅ Factory Pattern

Optional factory for custom initialization:

```swift
.factory {
    FilterViewModel(initialState: .init(userId: "custom"))
}
```

### ✅ Optional ViewModels

Support both optional and non-optional ViewModels:

```swift
// Non-optional: Factory creates instance
lazy var filter: Connection<FilterViewModel> = {
    setup(Connection<FilterViewModel> { ... }
        .connect(to: \.filterViewModel)
        .factory { FilterViewModel(initialState: .init()) }
    )
}()

// Optional: Factory can check preconditions
lazy var selectedEntry: Connection<EntryDetailViewModel> = {
    setup(Connection<EntryDetailViewModel> { ... }
        .connect(to: \.selectedEntryViewModel)
        .factory {
            guard let entry = parent?.state.selectedEntry else {
                fatalError("No entry selected")
            }
            return EntryDetailViewModel(initialState: .init(entry: entry))
        }
    )
}()
```

## API Reference

### Initialization

```swift
// With output handler
Connection<VM> { output in
    // Handle output
}

// Without output handler
Connection<VM>()
```

### Methods

#### `.connect(to:)`
Binds the connection to a state property.

```swift
.connect(to: \.filterViewModel)
```

#### `.factory(_:)`
Sets a custom factory for ViewModel creation.

```swift
.factory {
    FilterViewModel(initialState: .init())
}
```

#### `.clear()`
Clears the ViewModel from state.

```swift
connections.filter.clear()
```

### Properties

#### `.model`
Access the underlying ViewModel instance.

```swift
let vm = connections.filter.model
```

#### Dynamic member lookup
Access ViewModel members transparently.

```swift
connections.filter.send(.apply)      // Calls filter.model.send(.apply)
connections.filter.state.searchText  // Calls filter.model.state.searchText
```

## Best Practices

### 1. Use `[weak parent]` in output handlers

```swift
Connection<FilterViewModel> { [weak parent] output in
    parent?.applyFilter(output)
}
```

### 2. Store child ViewModels in parent state

```swift
struct EntriesState: ViewModelState {
    var filterViewModel: FilterViewModel?  // ✅ In state
}
```

### 3. Use lazy vars for connections

```swift
lazy var filter: Connection<FilterViewModel> = {
    setup(...)
}()
```

### 4. Call `.clear()` when done

```swift
override func send(_ action: Action) {
    case .dismissDetail:
        connections.detail.clear()
        destination = nil
}
```

### 5. Provide factory for non-optional ViewModels

```swift
.factory { FilterViewModel(initialState: .init()) }
```

## Summary

**Connection<VM> provides:**
- ✅ Fluent API: `Connection<VM> { output }.connect(to: \.property)`
- ✅ Transparent access via `@dynamicMemberLookup`
- ✅ State-mapped storage with persistence
- ✅ Automatic output handling
- ✅ Optional factory for custom initialization
- ✅ Lifecycle management with `.clear()`
- ✅ Support for both optional and non-optional ViewModels
