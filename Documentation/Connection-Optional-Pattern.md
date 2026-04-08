# Optional Connection<VM?> Pattern

## Overview

`Connection<VM>` supports both optional and non-optional ViewModel types. When using `Connection<VM?>` (optional), the factory is optional and can return `nil`.

## When to Use Optional vs Non-Optional

### Non-Optional `Connection<VM>`
Use when the ViewModel should **always exist** and be created if not in state.

```swift
lazy var filter: Connection<FilterViewModel> = {
    Connection<FilterViewModel> { output in
        parent?.applyFilter(output)
    }
    .connect(to: \ParentState.filterViewModel)
    .factory { FilterViewModel(initialState: .init()) }  // Required!
}()
```

**Characteristics:**
- ✅ Factory is **required**
- ✅ Always returns a non-nil ViewModel
- ✅ Created automatically on first access
- ❌ Crashes if factory not provided

### Optional `Connection<VM?>`
Use when the ViewModel **may not exist** and creation depends on conditions.

```swift
lazy var selectedEntry: Connection<EntryViewModel?> = {
    Connection<EntryViewModel?> { output in
        parent?.handleEntry(output)
    }
    .connect(to: \ParentState.selectedEntryViewModel)
    .factory {
        // Factory can return nil
        guard let entry = parent?.state.selectedEntry else { return nil }
        return EntryViewModel(initialState: .init(item: entry))
    }
}()
```

**Characteristics:**
- ✅ Factory is **optional**
- ✅ Factory can return `nil`
- ✅ Returns `nil` if not in state and factory returns `nil`
- ✅ No crash if factory omitted or returns `nil`

## Examples

### Example 1: Optional with Factory Returning Nil

```swift
class EntriesViewModel: BaseViewModel<...> {
    struct State: ViewModelState {
        var selectedEntry: Entry?
        var selectedEntryViewModel: EntryViewModel?
    }

    class Connections: BaseConnections<EntriesViewModel> {
        lazy var selectedEntry: Connection<EntryViewModel?> = {
            Connection<EntryViewModel?> { (output: EntryOutput) in
                switch output {
                case .entryUpdated(let entry):
                    parent?.updateEntry(entry)
                }
            }
            .connect(to: \EntriesState.selectedEntryViewModel)
            .factory {
                // Returns nil when no entry is selected
                guard let entry = parent?.state.selectedEntry else { return nil }
                return EntryViewModel(initialState: .init(item: entry))
            }
        }()
    }

    func showDetail() {
        // Optional unwrapping required
        if let detailVM = connections.selectedEntry.model {
            destination = .detail(detailVM)
        }
    }
}
```

### Example 2: Optional Without Factory

```swift
class ParentViewModel: BaseViewModel<...> {
    struct State: ViewModelState {
        // ViewModel may or may not exist in state
        var optionalChild: ChildViewModel?
    }

    class Connections: BaseConnections<ParentViewModel> {
        lazy var optionalChild: Connection<ChildViewModel?> = {
            Connection<ChildViewModel?> { output in
                parent?.handleOutput(output)
            }
            .connect(to: \ParentState.optionalChild)
            // No factory - returns nil if not in state
        }()
    }

    func useChild() {
        // Returns nil if not in state
        if let child = connections.optionalChild.model {
            child.send(.doSomething)
        }
    }
}
```

### Example 3: Non-Optional with Required Factory

```swift
class DashboardViewModel: BaseViewModel<...> {
    struct State: ViewModelState {
        var filterViewModel: FilterViewModel?
    }

    class Connections: BaseConnections<DashboardViewModel> {
        lazy var filter: Connection<FilterViewModel> = {
            Connection<FilterViewModel> { output in
                parent?.applyFilter(output)
            }
            .connect(to: \DashboardState.filterViewModel)
            .factory {
                // Always creates - never returns nil
                FilterViewModel(initialState: .init())
            }
        }()
    }

    func applyFilter() {
        // No optional unwrapping needed!
        connections.filter.send(.apply)
    }
}
```

## Implementation Details

The `Connection<VM>` class automatically detects if `VM` is an Optional type:

```swift
private func createViewModel() -> VM {
    if let factory = factoryClosure {
        return factory()
    }

    // If VM is Optional (e.g., EntryViewModel?), return nil
    if let nilValue = Optional<Any>.none as? VM {
        return nilValue
    }

    // If VM is non-optional and no factory, crash with helpful message
    fatalError("Connection<\(VM.self)> requires .factory { }...")
}
```

## Best Practices

### 1. Use Optional for Selection-Based ViewModels

```swift
// User may or may not have selected an item
lazy var selectedItem: Connection<ItemDetailViewModel?> = {
    Connection<ItemDetailViewModel?> { ... }
    .connect(to: \State.selectedItemViewModel)
    .factory {
        guard let item = parent?.state.selectedItem else { return nil }
        return ItemDetailViewModel(initialState: .init(item: item))
    }
}()
```

### 2. Use Non-Optional for Always-Available ViewModels

```swift
// Filter is always available
lazy var filter: Connection<FilterViewModel> = {
    Connection<FilterViewModel> { ... }
    .connect(to: \State.filterViewModel)
    .factory { FilterViewModel(initialState: .init()) }
}()
```

### 3. Handle Optional ViewModels Gracefully

```swift
// Good ✅
if let detailVM = connections.selectedEntry.model {
    destination = .detail(detailVM)
}

// Bad ❌ - Force unwrapping
destination = .detail(connections.selectedEntry.model!)
```

### 4. Use Guard for Early Returns

```swift
func showDetail() {
    guard let detailVM = connections.selectedEntry.model else {
        Log.warning("No entry selected")
        return
    }
    destination = .detail(detailVM)
}
```

## Summary

| Pattern | Factory | Returns | Use When |
|---------|---------|---------|----------|
| `Connection<VM>` | Required | Non-nil | ViewModel always exists |
| `Connection<VM?>` | Optional | Nil or VM | ViewModel conditionally exists |

**Key Point**: With `Connection<VM?>`, you have the flexibility to:
- Omit the factory entirely (returns `nil` if not in state)
- Provide a factory that returns `nil` conditionally
- Provide a factory that always creates (but still returns optional for consistency)
