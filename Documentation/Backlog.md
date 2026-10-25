# Backlog

Designed or agreed during the 2026-10 library review, but not built yet.

## `popToRoot()` and `close()` on models

**Problem.** A push stack is a chain of destinations: Root → A → B → C. Popping to the root means `root.state.destination = nil`; the root's connection then drops A, which drops B and C. But C has no reference to the root, so today it has to send an output up through every level.

**Design.**

1. **The connection records the parent.** When a `CaseConnection` creates a child, it stores a weak link on the child: the parent model and the connection that created it. This is internal, so apps write nothing.
2. **The helpers record how a child is shown.** `.push(connection)` marks its connection as pushed, and `.present(connection)` marks it as a sheet. For `showDestination`, the destination's `presentationStyle` gives the same information.
3. **Two new methods on `BaseViewModel`:**
   - **`popToRoot()`** walks up the parent links while each step was a push, then clears `destination` on the screen at the bottom of that stack. Inside a sheet that has its own `NavigationStack`, it stops at the sheet: it pops within the sheet and doesn't close it. Called on a stack root, it clears its own pushed destination, if there is one.
   - **`close()`** asks the model's own parent to clear its destination, which pops or dismisses just this screen. A child then doesn't need an output only to close itself.

```swift
// In any pushed screen's model
case .doneTapped:   popToRoot()   // back to the root of this NavigationStack
case .cancelTapped: close()       // pop / dismiss just this screen
```

**Estimate.** About 60 lines plus tests. The walking logic can be unit-tested with a chain of models, without any UI.

**To verify in the simulator.** Check that clearing the root's destination makes SwiftUI pop every pushed screen in one go. It should, because each pushed screen's own `navigationDestination` goes away with it.

## Other deferred items

- **Item-editing helper.** This would replace the deleted `ViewModelItemState`. It would keep the original item, track whether it's been modified, and offer revert and save, for detail and edit screens. Decide at the end of the review whether it's worth adding.
- **Clearer deep-link warning.** When the walker can't reach a child because the model doesn't adopt `HasConnections`, say exactly that, instead of the generic "isn't handled by X" message.