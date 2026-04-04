# Fix for "setupParent is not called" Issue

## Problem

When using `Connection<VM>.connect(state:case:)` pattern with lazy vars in `BaseConnections`, the connection's `setupParent` method was not being called, resulting in the connection returning `nil` even after setting `state.destination`.

###Root Cause

The issue occurs because:

1. Lazy properties are not evaluated until they're first accessed
2. `BaseConnections.wireConnections()` uses Mirror reflection to find connection properties
3. Mirror reflection cannot "see" lazy properties that haven't been evaluated yet
4. Therefore, `wireConnections()` couldn't find and setup the connection

## Solution

Added a `setupConnections()` method to `BaseConnections` that subclasses can override to force-evaluate their lazy connection properties.

### How to Fix Your Code

In your `Connections` class that extends `BaseConnections`, override `setupConnections()` and access each lazy connection property:

```swift
class EntriesViewModel: BaseViewModel<...> {

    lazy var connections: Connections = Connections(parent: self)

    class Connections: BaseConnections<EntriesViewModel> {

        lazy var entry = Connection<EntryViewModel> { [weak parent] output in
            guard let parent = parent else { return }
            switch output {
            case .entryUpdated(let entry):
                parent.send(.updateEntry(entry))
            }
        }
        .connect(state: \EntriesViewModel.State.destination, case: \.view)
        .factory {
            EntryViewModel(initialState: .init(item: .mock))
        }

        // Add this method to force lazy var evaluation
        override func setupConnections() {
            _ = entry  // Access the lazy var to force evaluation
        }
    }
}
```

### Why This Works

1. When `Connections(parent: self)` is called, the init runs
2. Init calls `setupConnections()`
3. Your override accesses `_ = entry`, forcing the lazy var to evaluate
4. The lazy var creates the `PresentedCaseComponentConnection` object
5. Init then calls `wireConnections()`
6. Mirror reflection now finds the evaluated `entry` property
7. `wireConnections()` calls `_setupParent()` on it
8. Connection is properly initialized!

## When Do You Need This?

### Required:
- ✅ When using `.connect(state:case:)` which returns `PresentedCaseComponentConnection`

### Not Required:
- ❌ When using `.connect(to:)` which returns `Connection<VM>`
- ❌ Regular `Connection` objects auto-wire themselves on first access via `ensureParentInjected()`

## Example: Multiple Connections

```swift
class Connections: BaseConnections<MyViewModel> {

    lazy var entry = Connection<EntryVM> { ... }
        .connect(state: \.destination, case: \.entry)
        .factory { ... }

    lazy var filter = Connection<FilterVM> { ... }
        .connect(state: \.destination, case: \.filter)
        .factory { ... }

    lazy var settings = Connection<SettingsVM> { ... }
        .connect(to: \.settingsVM)  // Regular connection, doesn't need setup

    override func setupConnections() {
        _ = entry    // Required - uses .connect(state:case:)
        _ = filter   // Required - uses .connect(state:case:)
        // settings doesn't need to be accessed - it's a regular Connection
    }
}
```

## Debugging

If you want to verify the connection is being set up, look for these debug logs:

```
🔍 BaseConnections.wireConnections: Starting wire connections for Connections
   Checking child: entry, type: PresentedCaseComponentConnection<State, EntryViewModel, Destination>
   ✅ Found AnyConnection #1: entry
🔧 PresentedCaseComponentConnection._setupParent called for EntryViewModel
🔧 ParentAccessor: Initialized, setting up objectWillChange observer
✅ PresentedCaseComponentConnection: Setting up observer
```

## Alternative: Fallback Auto-Setup

If you don't want to override `setupConnections()`, the connection will try to auto-setup itself on first access via the `ensureSetup()` method. This uses additional Mirror reflection which may be slower.

However, **it's recommended to use the `setupConnections()` override approach** for better performance and clarity.
