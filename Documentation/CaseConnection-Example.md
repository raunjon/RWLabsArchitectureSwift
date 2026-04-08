# CaseConnection Example Usage

This document demonstrates how to use `CaseConnection` for state-based navigation in the RWLabs Architecture.

## Understanding Connection vs CaseConnection

**Important:** When you create a connection for state-based navigation, you're working with **two classes**:

1. **`Connection<VM>`** - The initial builder that takes an output handler
2. **`CaseConnection<ParentState, VM, Case>`** - The actual connection returned by `.connect(state:case:)`

```swift
// Step 1: This creates a Connection<BioEditorViewModel>
Connection<BioEditorViewModel> { output in ... }

// Step 2: Calling .connect(state:case:) returns CaseConnection
.connect(state: \.destination, case: \.bioEditor)
// ↑ Returns CaseConnection<State, BioEditorViewModel, Destination>

// Step 3: .factory() still returns CaseConnection (with factory set)
.factory { ... }
// ↑ Still returns CaseConnection<State, BioEditorViewModel, Destination>
```

### Declaration Options

You have two ways to declare the connection:

**Option 1: Type Inference (Recommended)**
```swift
class Connections: BaseConnections<ProfileViewModel> {
    lazy var bioEditor = Connection<BioEditorViewModel> { output in
        // handle outputs
    }
    .connect(state: \.destination, case: \.bioEditor)
    .factory { BioEditorViewModel(initialState: .init()) }

    // Swift infers: CaseConnection<State, BioEditorViewModel, Destination>
}
```

**Option 2: Explicit Type Annotation (More Verbose)**
```swift
class Connections: BaseConnections<ProfileViewModel> {
    lazy var bioEditor: CaseConnection<
        ProfileViewModel,              // From: parent ViewModel
        BioEditorViewModel,            // To: child ViewModel
        ProfileViewModel.Destination   // Case: destination enum
    > = Connection<BioEditorViewModel> { output in
        // handle outputs
    }
    .connect(state: \.destination, case: \.bioEditor)
    .factory { BioEditorViewModel(initialState: .init()) }
}
```

**Both are correct!** The actual type is always `CaseConnection`. Type inference is usually preferred for brevity.

### Generic Parameter Naming
- `From` - The parent ViewModel type (e.g., `ProfileViewModel`)
- `To` - The child ViewModel type (e.g., `BioEditorViewModel`)
- `Case` - The destination enum type (e.g., `ProfileViewModel.Destination`)

### Architecture Diagram

```
Parent ViewModel
├── State
│   └── destination: Destination?  ← CaseConnection watches this
│       └── .bioEditor(BioEditorViewModel.State)  ← Child state stored here
│
└── Connections
    └── bioEditor: CaseConnection  ← Manages the child ViewModel
        ├── Observes parent.state.destination
        ├── Extracts child state when case = .bioEditor
        ├── Creates/manages BioEditorViewModel
        ├── Syncs child state changes → parent.state.destination
        └── Handles child outputs
```

## What CaseConnection Does

`CaseConnection` is the core class that powers state-based navigation. Here's what it does:

### 1. **Observes Parent State**
```swift
// CaseConnection watches parent.state.destination
// When destination changes, it extracts the child state using CasePath
```

### 2. **Activates When Case Matches**
```swift
// When parent sets: state.destination = .bioEditor(childState)
// CaseConnection:
// - Extracts childState from the .bioEditor case
// - Creates/updates BioEditorViewModel with that state
// - Binds output handler
// - Starts observing child state changes
```

### 3. **Syncs Child State to Parent**
```swift
// When child's state changes (e.g., user types in text field)
// CaseConnection:
// - Detects the change via objectWillChange
// - Extracts updated child state
// - Updates parent: state.destination = .bioEditor(updatedChildState)
// - Parent state now includes child changes!
```

### 4. **Handles Outputs**
```swift
// When child emits output
// CaseConnection calls your output handler with the output
```

### 5. **Deactivates When Case Changes**
```swift
// When parent sets: state.destination = nil (or different case)
// CaseConnection:
// - Stops observing child
// - Keeps ViewModel cached (for potential reuse)
```

## Complete Example: Profile Screen with Bio Editor

### 1. Child ViewModel (Bio Editor)

```swift
import Foundation
import Combine
import RWLabsArchitecture

// MARK: - Bio Editor ViewModel

class BioEditorViewModel: BaseViewModel<BioEditorViewModel.State, BioEditorViewModel.Action, BioEditorViewModel.Output, BioEditorViewModel.Destination> {

    // MARK: State
    struct State: ViewModelState {
        var bioText: String = ""
        var characterLimit: Int = 500
        var isLoading: Bool = false
        var error: Error? = nil
        var destination: Destination? = nil

        var remainingCharacters: Int {
            characterLimit - bioText.count
        }

        var isValid: Bool {
            !bioText.isEmpty && bioText.count <= characterLimit
        }
    }

    // MARK: Destination
    @CasePathable
    enum Destination: RouteDestination {
        case none

        static var featureId: String { "bioEditor" }
        static var initialDestination: Destination { .none }

        var presentationStyle: PresentationStyle {
            .push
        }
    }

    // MARK: Action
    enum Action: ViewModelAction {
        case textChanged(String)
        case saveTapped
        case cancelTapped
    }

    // MARK: Output
    enum Output: ViewModelOutput {
        case bioSaved(String)
        case cancelled
    }

    // MARK: - Lifecycle

    override func send(_ action: Action) {
        switch action {
        case .textChanged(let text):
            state.bioText = text

        case .saveTapped:
            guard state.isValid else { return }
            state.isLoading = true

            // Simulate save
            Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    state.isLoading = false
                    emitOutput(.bioSaved(state.bioText))
                }
            }

        case .cancelTapped:
            emitOutput(.cancelled)
        }
    }
}
```

### 2. Parent ViewModel (Profile)

```swift
import Foundation
import Combine
import RWLabsArchitecture

// MARK: - Profile ViewModel

class ProfileViewModel: BaseViewModel<ProfileViewModel.State, ProfileViewModel.Action, ProfileViewModel.Output, ProfileViewModel.Destination> {

    // MARK: State
    struct State: ViewModelState {
        var userName: String = "John Doe"
        var userBio: String = ""
        var isLoading: Bool = false
        var error: Error? = nil
        var destination: Destination? = nil
    }

    // MARK: Destination
    @CasePathable
    enum Destination: RouteDestination {
        case bioEditor(BioEditorViewModel.State)  // ← Child state stored here
        case settings(SettingsViewModel.State)

        static var featureId: String { "profile" }
        static var initialDestination: Destination { .bioEditor(.init()) }

        var presentationStyle: PresentationStyle {
            switch self {
            case .bioEditor:
                return .modal  // Present as sheet
            case .settings:
                return .push   // Push onto navigation stack
            }
        }
    }

    // MARK: Action
    enum Action: ViewModelAction {
        case editBioTapped
        case settingsTapped
    }

    // MARK: Output
    enum Output: ViewModelOutput {
        case bioUpdated
    }

    // MARK: - Connections

    lazy var connections: Connections = {
        Connections(parent: self)
    }()

    class Connections: BaseConnections<ProfileViewModel> {

        // This creates a CaseConnection!
        //
        // The pattern is:
        // 1. Create Connection<VM> with output handler
        // 2. Call .connect(state:case:) → returns CaseConnection
        // 3. Call .factory { } → CaseConnection with factory set
        //
        // CaseConnection automatically:
        // 1. Observes parent's state.destination
        // 2. Creates BioEditorViewModel when destination = .bioEditor(...)
        // 3. Extracts the child State from the .bioEditor case
        // 4. Syncs child state changes back to parent.state.destination
        // 5. Calls output handler when child emits outputs
        //
        // You can use type inference (shorter):
        //   lazy var bioEditor = Connection<BioEditorViewModel> { ... }
        //
        // Or explicit type annotation (clearer):
        //   lazy var bioEditor: CaseConnection<State, BioEditorViewModel, Destination> = Connection<BioEditorViewModel> { ... }
        //
        // Both are correct! The actual type is always CaseConnection.

        lazy var bioEditor = Connection<BioEditorViewModel> { [weak parent] output in
            guard let parent = parent else { return }

            switch output {
            case .bioSaved(let newBio):
                // Handle the output from child
                parent.handleBioSaved(newBio)

            case .cancelled:
                // Dismiss by clearing destination
                parent.state.destination = nil
            }
        }
        .connect(state: \.destination, case: \.bioEditor)  // ← Magic happens here
        .factory {
            // Factory creates the child ViewModel
            BioEditorViewModel(initialState: .init())
        }

        // You can have multiple connections
        lazy var settings = Connection<SettingsViewModel> { [weak parent] output in
            // Handle settings outputs...
        }
        .connect(state: \.destination, case: \.settings)
        .factory {
            SettingsViewModel(initialState: .init())
        }

        // Access connections in setupConnections to ensure they're wired
        override func setupConnections() {
            _ = bioEditor
            _ = settings
        }
    }

    // MARK: - Actions

    override func send(_ action: Action) {
        switch action {
        case .editBioTapped:
            // Navigate by setting destination with initial child state
            let initialBioState = BioEditorViewModel.State(
                bioText: state.userBio
            )
            state.destination = .bioEditor(initialBioState)

        case .settingsTapped:
            state.destination = .settings(.init())
        }
    }

    // MARK: - Private Handlers

    private func handleBioSaved(_ newBio: String) {
        // Update parent state
        state.userBio = newBio

        // Dismiss the editor
        state.destination = nil

        // Emit output
        emitOutput(.bioUpdated)
    }
}
```

### 3. SwiftUI Views

```swift
import SwiftUI
import RWLabsArchitecture

// MARK: - Profile View

struct ProfileView: View {
    @StateObject var model: ProfileViewModel

    var body: some View {
        VStack(spacing: 20) {
            // User Info
            Text(model.state.userName)
                .font(.title)

            Text(model.state.userBio.isEmpty ? "No bio yet" : model.state.userBio)
                .foregroundColor(.secondary)

            // Edit Bio Button
            Button("Edit Bio") {
                model.send(.editBioTapped)
            }

            // Settings Button
            Button("Settings") {
                model.send(.settingsTapped)
            }
        }
        .padding()
        // Modal presentation for .bioEditor destination
        .sheet(item: $model.modalDestination) { destination in
            switch destination {
            case .bioEditor:
                // Access the child ViewModel through the connection
                if let bioEditorVM = model.connections.bioEditor.model {
                    BioEditorView(model: bioEditorVM)
                }
            default:
                EmptyView()
            }
        }
        // Push navigation for .settings destination
        .navigationDestination(item: $model.pushDestination) { destination in
            switch destination {
            case .settings:
                if let settingsVM = model.connections.settings.model {
                    SettingsView(model: settingsVM)
                }
            default:
                EmptyView()
            }
        }
    }
}

// MARK: - Bio Editor View

struct BioEditorView: View {
    @StateObject var model: BioEditorViewModel
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                // Text Editor
                TextEditor(text: $model.state.bioText)
                    .frame(height: 200)
                    .border(Color.gray, width: 1)

                // Character Count
                Text("\(model.state.remainingCharacters) characters remaining")
                    .foregroundColor(model.state.isValid ? .secondary : .red)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.send(.cancelTapped)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.send(.saveTapped)
                    }
                    .disabled(!model.state.isValid)
                }
            }
            .overlay {
                if model.state.isLoading {
                    ProgressView()
                }
            }
        }
    }
}
```

## How It Works - Step by Step

Understanding the flow of `CaseConnection` in action:

### 1. User Taps "Edit Bio"

```swift
// ProfileViewModel.send(.editBioTapped)
state.destination = .bioEditor(BioEditorViewModel.State(bioText: state.userBio))
```

**What CaseConnection does:**
- `bioEditor` (which is a `CaseConnection`) observes parent's `objectWillChange`
- Detects that `state.destination` changed to `.bioEditor(...)`
- Calls `handleParentStateChange()`

### 2. CaseConnection Activates

```swift
// Inside CaseConnection.handleParentStateChange()
let childState = destination.flatMap { AnyCasePath(casePath).extract(from: $0) }
// Extracts BioEditorViewModel.State from .bioEditor case

if let childState = childState {
    activateConnection(with: childState)
}
```

**What happens:**
- Extracts `BioEditorViewModel.State` from the `.bioEditor` case
- Creates `BioEditorViewModel` using factory
- Sets the child's state to the extracted state
- Binds the output handler
- Starts observing child state changes

### 3. User Edits Bio Text

```swift
// BioEditorView changes the text
TextEditor(text: $model.state.bioText)

// Child ViewModel state changes
model.state.bioText = "New bio text"
```

**What happens:**
- Child's `state.bioText` changes
- Child's `objectWillChange` fires
- `CaseConnection` observes this via `observeChildStateChanges`
- Calls `syncChildStateToParent()`

### 4. Child State Syncs to Parent

```swift
// Inside CaseConnection.syncChildStateToParent()
let newChildState = model.state  // Get updated child state

// Update the case in parent's destination
try _ = AnyCasePath(casePath).modify(&destination) { _ in newChildState }

// Update parent state
parent.updateState { state in
    state.destination = .bioEditor(newChildState)  // Updated state!
}
```

**What happens:**
- Gets the updated child state
- Updates the `.bioEditor` case in parent's destination
- Parent now has the latest child state
- If parent state is persisted/logged, it includes child changes!

### 5. User Saves Bio

```swift
// BioEditorViewModel.send(.saveTapped)
emitOutput(.bioSaved(state.bioText))
```

**What happens:**
- Output handler in Connection receives the output
- Parent handles it in `handleBioSaved()`
- Parent updates its own state
- Parent dismisses by setting `state.destination = nil`

### 6. CaseConnection Deactivates

```swift
// Parent set destination to nil
state.destination = nil
```

**What happens:**
- `CaseConnection` observes parent state change
- `handleParentStateChange()` detects no matching case
- Calls `deactivateConnection()`
- Stops observing child state changes
- Keeps child ViewModel cached for potential reuse

## Benefits of This Pattern

### ✅ Single Source of Truth
```swift
// All navigation state in one place
print(model.state.destination)  // .bioEditor(State(...))
```

### ✅ State Persistence
```swift
// Save entire app state including child ViewModels
let data = try JSONEncoder().encode(model.state)
// Includes the bio editor state if it's active!
```

### ✅ Testable
```swift
func testBioEditor() {
    let vm = ProfileViewModel(initialState: .init())

    // Navigate to bio editor
    vm.send(.editBioTapped)

    // Verify destination is set
    XCTAssertNotNil(vm.state.destination)

    // Access child ViewModel through connection
    let bioEditor = vm.connections.bioEditor.model
    XCTAssertNotNil(bioEditor)

    // Test child behavior
    bioEditor?.send(.textChanged("New bio"))
    XCTAssertEqual(bioEditor?.state.bioText, "New bio")

    // Verify parent state is synced
    if case .bioEditor(let state) = vm.state.destination {
        XCTAssertEqual(state.bioText, "New bio")
    }
}
```

### ✅ Transparent Access
```swift
// Access child properties directly through connection
model.connections.bioEditor.state?.bioText
model.connections.bioEditor.send?(.textChanged("..."))

// Or access the model
if let bioEditor = model.connections.bioEditor.model {
    bioEditor.send(.saveTapped)
}
```

### ✅ Automatic Lifecycle
- Child created when destination case becomes active
- Child deactivated when case changes
- No manual setup/teardown needed
- Memory efficient (weak parent references)

## Advanced Patterns

### Multiple Connections

```swift
class Connections: BaseConnections<ParentViewModel> {
    lazy var detail = Connection<DetailViewModel> { ... }
        .connect(state: \.destination, case: \.detail)
        .factory { DetailViewModel(initialState: .init()) }

    lazy var edit = Connection<EditViewModel> { ... }
        .connect(state: \.destination, case: \.edit)
        .factory { EditViewModel(initialState: .init()) }

    lazy var settings = Connection<SettingsViewModel> { ... }
        .connect(state: \.destination, case: \.settings)
        .factory { SettingsViewModel(initialState: .init()) }

    override func setupConnections() {
        _ = detail
        _ = edit
        _ = settings
    }
}
```

### Passing Data to Child

```swift
// With initialization data
vm.send(.editBioTapped)

// In the action handler:
let initialState = BioEditorViewModel.State(
    bioText: state.userBio,
    characterLimit: 500,
    userId: state.userId  // Pass context
)
state.destination = .bioEditor(initialState)
```

### Handling Multiple Outputs

```swift
lazy var bioEditor = Connection<BioEditorViewModel> { [weak parent] output in
    guard let parent = parent else { return }

    switch output {
    case .bioSaved(let bio):
        parent.updateState { $0.userBio = bio }
        parent.state.destination = nil
        parent.emitOutput(.profileUpdated)

    case .cancelled:
        parent.state.destination = nil

    case .imageUploadRequested:
        parent.showImagePicker()

    case .errorOccurred(let error):
        parent.handleError(error)
    }
}
.connect(state: \.destination, case: \.bioEditor)
.factory { BioEditorViewModel(initialState: .init()) }
```

## Common Patterns

### Dismiss from Child
```swift
// In child output
enum Output: ViewModelOutput {
    case dismiss
}

// In parent connection
lazy var child = Connection<ChildViewModel> { [weak parent] output in
    if case .dismiss = output {
        parent?.state.destination = nil
    }
}
```

### Conditional Navigation
```swift
func showDetail() {
    guard state.isAuthenticated else {
        state.destination = .login
        return
    }

    state.destination = .detail(.init())
}
```

### Chained Navigation
```swift
// Child can have its own destination!
struct ChildState: ViewModelState {
    var destination: ChildDestination?

    enum ChildDestination {
        case subDetail(SubDetailState)
    }
}

// Creates nested navigation hierarchies
```

## CaseConnection API Reference

### Type Definition
```swift
@MainActor
@dynamicMemberLookup
public final class CaseConnection<ParentState: ViewModelState, VM: ViewModel, Case: CasePathable>
```

### Generic Parameters
- `ParentState` - The parent ViewModel's state type (e.g., `ProfileViewModel.State`)
- `VM` - The child ViewModel type (e.g., `BioEditorViewModel`)
- `Case` - The destination enum type (e.g., `ProfileViewModel.Destination`)

### Properties

#### `model: VM?`
Returns the child ViewModel if the destination case is currently active.

```swift
// Access the child ViewModel
if let bioEditor = model.connections.bioEditor.model {
    bioEditor.send(.textChanged("New bio"))
}
```

**Returns:**
- `VM?` - The child ViewModel instance if active, `nil` otherwise

### Methods

#### `factory(_ factory: @escaping () -> VM) -> Self`
Sets the factory for creating the child ViewModel.

```swift
.factory {
    BioEditorViewModel(initialState: .init())
}
```

**Parameters:**
- `factory` - Closure that creates and returns a new ViewModel instance

**Returns:** `Self` for method chaining

### Dynamic Member Lookup

CaseConnection supports `@dynamicMemberLookup`, allowing transparent access to child ViewModel members:

```swift
// Direct property access (returns optional)
let text = model.connections.bioEditor.state?.bioText

// Direct method access (returns optional closure)
model.connections.bioEditor.send?(.textChanged("New text"))

// Equivalent to:
model.connections.bioEditor.model?.state.bioText
model.connections.bioEditor.model?.send(.textChanged("New text"))
```

### Lifecycle

**Activation:** CaseConnection activates when:
- Parent sets `state.destination` to the matching case
- Example: `state.destination = .bioEditor(...)`

**Deactivation:** CaseConnection deactivates when:
- Parent sets `state.destination` to `nil`
- Parent sets `state.destination` to a different case
- Example: `state.destination = nil` or `state.destination = .settings(...)`

**ViewModel Caching:**
- Child ViewModel is cached even after deactivation
- Reused if the same case is activated again
- Call `connection.clear()` to force recreation (not commonly needed)

### State Synchronization

CaseConnection automatically syncs state bi-directionally:

**Parent → Child:**
```swift
// Parent changes destination
parent.state.destination = .bioEditor(State(bioText: "Initial"))
// CaseConnection extracts State and sets child.state.bioText = "Initial"
```

**Child → Parent:**
```swift
// Child changes state
child.state.bioText = "Updated"
// CaseConnection updates parent.state.destination = .bioEditor(State(bioText: "Updated"))
```

### Internal Implementation

CaseConnection uses:
- **CasePaths** for extracting/embedding child state in enum cases
- **Combine** for observing parent and child `objectWillChange`
- **Generic helpers** to work with existential types safely
- **Weak references** to prevent retain cycles

### Complete Type Signature Example

```swift
// Full type (usually inferred)
lazy var bioEditor: CaseConnection<
    ProfileViewModel.State,      // ParentState
    BioEditorViewModel,          // VM
    ProfileViewModel.Destination // Case
> = Connection<BioEditorViewModel> { output in
    // Handle outputs
}
.connect(state: \.destination, case: \.bioEditor)
.factory {
    BioEditorViewModel(initialState: .init())
}
```

### Memory Management

- **CaseConnection** holds a weak reference to parent ViewModel
- **Parent** holds a strong reference to Connections
- **Connections** holds strong references to CaseConnections
- **CaseConnection** holds a strong reference to child ViewModel (cached)

```
ParentViewModel (strong)
    ↓
Connections (strong)
    ↓
CaseConnection (strong)
    ↓ weak
ParentViewModel

CaseConnection (strong)
    ↓
ChildViewModel
```

No retain cycles! ✅
```
