# Connections

A connection links a parent ViewModel to a child ViewModel whose state lives in the parent's state. The connection creates the child, keeps the two states in sync in both directions, and delivers the child's outputs to the parent.

| Kind | Parent state holds | Child exists | Use for |
|---|---|---|---|
| **Direct**: `Connection.connect(from:to:)` | The child's state, always | For the parent's lifetime | Tabs, embedded panels |
| **Case**: `Connection.connect(state:case:parent:)` | The child's state as the payload of one enum case | While that case is set | Sheets, pushes, alerts, root flows |
| **Optional**: `Connection.connect(state:parent:)` | The child's state, optionally (`State?`) | While the value is non-`nil` | Inline components shown on demand |

Navigation and presentation build on case connections; see [Navigation.md](Navigation.md). Root flows and tab bars combine direct and case connections; see [Flows.md](Flows.md).

## Setting Up

Each ViewModel that has children declares a `Connections` class: one `lazy var` per child.

```swift
@Component
final class ProfileModel: ComponentModel<ProfileModel.State, ProfileModel.Action, ProfileModel.Output> {
    struct State {
        var stats = StatsModel.State()          // a direct child's state
    }                                           // destination: Destination? is generated

    enum Destination {
        case editor(EditorModel.State)          // case children's states
    }

    final class Connections: ViewModelConnections<ProfileModel> {
        lazy var stats: StatsModel = Connection<StatsModel>()
            .connect(from: parent!, to: \.stats)

        lazy var editor = Connection<EditorModel> { [weak parent] output in
            switch output {
            case .saved(let bio): parent?.send(.bioSaved(bio))
            }
        }
        .connect(state: \.destination, case: \.editor, parent: parent)
    }
    …
}
```

`@Component` writes the `connections` property, `HasConnections`, and a `setupConnections()` that touches every `lazy var`. Without the macro, write those three yourself:

```swift
lazy var connections = Connections(parent: self)       // on the model, which adopts HasConnections
override func setupConnections() { _ = stats; _ = editor }   // in Connections
```

- **`ViewModelConnections<Parent>`** holds a `weak var parent`. Its `init(parent:)` calls `setupConnections()`, then gives every connection property that has been evaluated its parent.
- **`setupConnections()`:** touch each case connection here (`_ = editor`); `@Component` generates this. A `lazy var` is invisible until it's first read. Touching it makes the connection observe the parent from the start, rather than from the first time a view reads it, and deep links need it in order to find the child.
- **`[weak parent]`** in output handlers avoids a retain cycle.
- **`HasConnections`** is only needed for deep links (see [Flows.md](Flows.md#deep-links)).

## Direct Connections

```swift
lazy var stats: StatsModel = Connection<StatsModel> { [weak parent] output in … }
    .connect(from: parent!, to: \.stats)
```

`connect(from:to:)` builds the child from `parent.state.stats` and returns it, not a wrapper:
- **Child edits** are copied into `parent.state.stats`.
- **Parent changes** to `state.stats` (a reset, a reload) are copied into the child.
- **Outputs** go to the handler for as long as the child exists.

The link that does this is owned by the child and holds both models weakly, so it never keeps either alive.

## Case Connections

```swift
lazy var editor = Connection<EditorModel> { [weak parent] output in … }
    .connect(state: \.destination, case: \.editor, parent: parent)
```

The child exists while `parent.state.destination` is `.editor(…)`:
- **Activation:** setting `.editor(payload)` creates the child as `EditorModel(initialState: payload)`. To give the child a starting state, put it in the payload: `state.destination = .editor(.init(bio: profile.bio))`.
- **Syncing:**
  - the child's edits are written back into the `.editor` payload;
  - assigning a new `.editor(…)` payload while it's open updates the existing child in place, rather than recreating it.
- **Deactivation:** setting `destination` to `nil` *or to another case* drops the child.
- **Dismissal:** setting `bindingModel` to `nil`, which SwiftUI does when a sheet is swiped down or a screen is popped, clears the parent's `destination`. It only does so if the destination is still this case.

Members:

| Member | |
|---|---|
| `model: To?` | The child while the case is set. Reading it activates the child straight away if the parent already holds the case. |
| `bindingModel: Binding<To?>` | For `.sheet(item:)`, `.navigationDestination(item:)` and `.customAlert(item:)`. The `present` and `push` helpers use it for you. |
| `connection.title` | Dynamic member lookup into the child (`connection.model?.title`) |

The state key path can point at any optional `@CasePathable` enum, not just `destination`. Root flows use `\.flow` the same way.

## Optional Connections

For a child that comes and goes inline, such as a component the screen shows on demand, keep its state optional on the parent:

```swift
struct State: ViewModelState {
    var filter: FilterModel.State?          // the child's state, not the child
    …
}

lazy var filter = Connection<FilterModel> { [weak parent] output in
    switch output {
    case .close: parent?.state.filter = nil
    }
}
.connect(state: \.filter, parent: parent)

// Parent
state.filter = .init(selected: .recent)    // child created from the state
state.filter = nil                         // child dropped

// View
if let filter = model.connections.filter.model {
    FilterView(model: filter)
}
```

It behaves like a case connection, and its type is `CaseConnection<Parent, FilterModel, FilterModel.State?>`:
- the child exists while the value is non-`nil`, and edits sync both ways;
- assigning a new value while the child exists updates it in place;
- it works with `.present` and `.push`, and dismissing sets the value back to `nil`.

The old `OptionalConnection`, which stored the child ViewModel itself in state, was removed. State holds only data, so it can be copied, synced and deep-linked. Build any custom setup a child needs into its `init(initialState:)` or its `@Injected` dependencies.

## How Syncing Works

Both direct and case connections observe `objectWillChange` on the parent and on the child. That publisher fires *before* a value changes, so each side reads the new value on the next main-queue turn.

- **No echo loops:** writing one side fires the other side's `objectWillChange`. A flag set during each write makes the observer ignore its own echo, so one edit causes exactly one change on each side.
- **No lost typing:** while a child edit is still waiting to be copied to the parent, the parent's older value isn't pushed back into the child. An unrelated parent change can't overwrite what the user just typed.
- **States need no equality:** `ViewModelState` isn't `Equatable`, and nothing in the sync compares states.

`CaseConnectionSyncTests` and `ConnectionLifecycleTests` cover all of this.

## Memory

Nothing in a connection keeps its parent or child alive:
- the connections object holds the parent weakly;
- a direct child owns its sync link, which holds both models weakly;
- case connections and their bindings capture weakly.

When a screen's parent ViewModel goes away, its children and connections go too. `ConnectionLifecycleTests` checks this; keep it passing when changing captures.

## Troubleshooting

| Symptom | Check |
|---|---|
| A case connection's `model` stays `nil` after setting the destination | Pass `parent: parent` to `connect(state:case:parent:)`, or touch the connection in `setupConnections()`. Then check that the `case:` key path matches the case you set. |
| A connection logs "expected a parent of type …" | The connection's `From` type doesn't match the `Connections` class's parent. |
| A deep link stops at a screen | Its model adopts `HasConnections`, its `Destination` handles the URL name, and the connection is touched in `setupConnections()`. |

## Testing

Connections sync on the next main-queue turn, so let it run before asserting:

```swift
@MainActor
func testEditReachesParent() async {
    DependencyContainer.shared.registerSingleton(ErrorService.self, instance: StubErrorService())
    let parent = ProfileModel(initialState: .init())
    parent.connections.stats.send(.rename("new"))

    for _ in 0..<5 {   // drain the main queue
        await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
    }
    XCTAssertEqual(parent.state.stats.name, "new")
}
```

Every `BaseViewModel` injects an `ErrorService`, so register one in `setUp`.
