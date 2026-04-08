# Case-Based Connection Pattern

## Overview

`PresentedCaseComponentConnection` enables automatic management of child ViewModels whose **states** are stored within enum cases in parent state. This pattern is ideal for modal presentations, sheets, and other destination-based navigation where the destination is represented as an enum.

**Important:** The enum case must store the child ViewModel's **State**, not the ViewModel itself:

```swift
// ✅ Correct - stores State
enum Destination: CasePathable {
    case bioEditor(TextEntryModel.State)
}

// ❌ Incorrect - stores ViewModel
enum Destination: CasePathable {
    case bioEditor(TextEntryModel)
}
```

## Key Features

1. **Automatic Activation**: Connection becomes active when destination enum case is set
2. **Bidirectional Sync**: Child ViewModel state syncs with parent destination enum
3. **Output Handling**: Outputs are automatically listened to when connection is active
4. **Type-Safe**: Leverages CasePaths for compile-time safety with enums

## Basic Usage

### 1. Define Parent State with Destination Enum

```swift
class ProfileViewModel: BaseViewModel<State, Action, Output, Destination> {

    struct State: ViewModelState {
        var id: User.ID
        var profile: Profile?
        var isLoadingProfile = false
        var destination: Destination?

        var isLoading: Bool = false
        var error: Error? = nil
    }

    // Destination enum must conform to CasePathable
    enum Destination: CasePathable {
        case bioEditor(TextEntryModel.State)
        case locationEditor(TextEntryModel.State)
        case settings(SettingsViewModel.State)
    }
}
```

### 2. Create Connection with Output Handler

```swift
class Connections: BaseConnections<ProfileViewModel> {

    lazy var bioEditor = Connection<TextEntryModel> { [weak parent] output in
        guard let parent = parent else { return }

        switch output {
        case .textUpdated(let bio):
            Task { @MainActor in
                do {
                    try await parent.graphTask(UpdateProfileMutation(bio: bio))
                    parent.state.profile?.bio = bio
                    parent.track(Analytics.Profile.SectionUpdated(
                        section: .bio,
                        actionType: !(parent.state.profile?.bio?.isEmpty ?? true) ? .updated : .created
                    ))
                } catch {
                    parent.handleError(error)
                }
            }
        }
    }
    .connect(state: \.destination, case: \.bioEditor)
    .factory {
        TextEntryModel(initialState: .init(
            title: "Edit Bio",
            placeholder: "Tell us about yourself..."
        ))
    }
}
```

### 3. Activate Connection by Setting Destination

```swift
extension ProfileViewModel {

    func editBio() {
        // Setting the destination automatically:
        // 1. Creates the child ViewModel (if factory provided)
        // 2. Initializes it with state from the enum case
        // 3. Starts listening to its outputs
        // 4. Syncs child state changes back to parent

        let initialState = TextEntryModel.State(
            text: state.profile?.bio ?? "",
            title: "Edit Bio",
            placeholder: "Tell us about yourself..."
        )

        state.destination = .bioEditor(initialState)
    }

    func dismissEditor() {
        // Setting destination to nil deactivates the connection
        state.destination = nil
    }
}
```

### 4. Access Child ViewModel in SwiftUI View

```swift
struct ProfileView: View {
    @StateObject var model: ProfileViewModel

    var body: some View {
        VStack {
            // ... profile UI ...

            Button("Edit Bio") {
                model.editBio()
            }
        }
        .sheet(item: $model.state.destination) { destination in
            switch destination {
            case .bioEditor:
                // The connection automatically provides the ViewModel
                if let bioEditorVM = model.connections.bioEditor.model {
                    TextEntryView(model: bioEditorVM)
                }

            case .locationEditor:
                if let locationEditorVM = model.connections.locationEditor.model {
                    TextEntryView(model: locationEditorVM)
                }

            case .settings:
                if let settingsVM = model.connections.settings.model {
                    SettingsView(model: settingsVM)
                }
            }
        }
    }
}
```

## Advanced Usage

### Multiple Connections to Same ViewModel Type

You can have multiple connections to the same ViewModel type for different destinations:

```swift
lazy var bioEditor = Connection<TextEntryModel> { [weak parent] output in
    // Handle bio updates
}
.connect(state: \.destination, case: \.bioEditor)
.factory { TextEntryModel(initialState: .init(title: "Edit Bio")) }

lazy var locationEditor = Connection<TextEntryModel> { [weak parent] output in
    // Handle location updates
}
.connect(state: \.destination, case: \.locationEditor)
.factory { TextEntryModel(initialState: .init(title: "Edit Location")) }
```

### Accessing Child ViewModel Properties

Use dynamic member lookup for convenient access:

```swift
// Access child ViewModel properties directly
if let text = model.connections.bioEditor.state?.text {
    print("Current bio text: \(text)")
}

// Send actions to child
model.connections.bioEditor.send?(.textChanged("New bio"))

// Check if connection is active
if model.connections.bioEditor.model != nil {
    print("Bio editor is active")
}
```

### State Synchronization

The connection automatically keeps the child ViewModel state and parent destination enum in sync:

```swift
// When child ViewModel state changes...
bioEditorViewModel.state.text = "New bio text"

// ...it automatically updates the parent destination
// parent.state.destination = .bioEditor(updatedState)

// This works in both directions!
```

## How It Works

### 1. Destination Observation

The connection observes the parent's `destination` property. When the specified enum case becomes active, the connection:

- Extracts the child state from the enum using CasePaths
- Creates or retrieves the child ViewModel
- Initializes the child ViewModel with the extracted state
- Starts observing child ViewModel changes

### 2. Output Handling

When the connection is active, outputs from the child ViewModel are automatically handled by the closure you provided:

```swift
Connection<ChildVM> { output in
    // This closure is only called when connection is active
}
```

### 3. State Sync

Any changes to the child ViewModel's state are automatically written back to the parent's destination enum:

```
Child VM State Change → Parent Destination Enum Update → SwiftUI Re-renders
```

### 4. Lifecycle

- **Activation**: When `destination` is set to the matching case
- **Deactivation**: When `destination` is set to `nil` or a different case
- **Caching**: Child ViewModels are cached and reused when reactivated

## Best Practices

### 1. Use for Modal Presentations

This pattern is ideal for sheets, popovers, and full-screen covers:

```swift
.sheet(item: $model.state.destination) { destination in
    switch destination {
    case .bioEditor:
        if let vm = model.connections.bioEditor.model {
            TextEntryView(model: vm)
        }
    }
}
```

### 2. Initialize with Proper State

Always initialize the enum case with the appropriate initial state:

```swift
func editBio() {
    let initialState = TextEntryModel.State(
        text: state.profile?.bio ?? "",
        // ... other properties
    )
    state.destination = .bioEditor(initialState)
}
```

### 3. Handle Dismissal

Clear the destination to dismiss:

```swift
func dismissEditor() {
    state.destination = nil
}
```

### 4. Error Handling in Output Handlers

Always handle errors in your output handlers:

```swift
Connection<ChildVM> { [weak parent] output in
    Task {
        do {
            try await parent?.performOperation()
        } catch {
            parent?.handleError(error)
        }
    }
}
```

## Comparison with Direct Connection

### Case-Based Connection (Recommended for Destinations)

```swift
// ✅ For enum-based destinations
lazy var editor = Connection<EditorVM> { output in
    // Handle output
}
.connect(state: \.destination, case: \.editor)
.factory { EditorVM(initialState: .init()) }
```

**Pros:**
- Automatic activation/deactivation
- Enum-based type safety
- Natural SwiftUI binding with `.sheet(item:)`
- Bidirectional state sync

### Direct Connection (For Persistent Children)

```swift
// ✅ For always-present child ViewModels
lazy var settings = Connection<SettingsVM> { output in
    // Handle output
}
.connect(to: \.settingsViewModel)
.factory { SettingsVM(initialState: .init()) }
```

**Pros:**
- Simpler for non-optional children
- No enum overhead
- Direct property access

## Complete Example

See the example below for a complete implementation:

```swift
// MARK: - Parent ViewModel

class ProfileViewModel: BaseViewModel<State, Action, Output, Destination> {

    struct State: ViewModelState {
        var profile: Profile?
        var destination: Destination?
        var isLoading: Bool = false
        var error: Error? = nil
    }

    enum Destination: CasePathable, Identifiable {
        case bioEditor(TextEntryModel.State)
        case avatarPicker(ImagePickerModel.State)

        var id: String {
            switch self {
            case .bioEditor: return "bioEditor"
            case .avatarPicker: return "avatarPicker"
            }
        }
    }

    lazy var connections = Connections(parent: self)

    class Connections: BaseConnections<ProfileViewModel> {

        lazy var bioEditor = Connection<TextEntryModel> { [weak parent] output in
            guard let parent = parent else { return }

            switch output {
            case .save(let text):
                Task {
                    await parent.saveBio(text)
                }
            case .cancel:
                parent.state.destination = nil
            }
        }
        .connect(state: \.destination, case: \.bioEditor)
        .factory {
            TextEntryModel(initialState: .init(
                title: "Edit Bio",
                maxLength: 500
            ))
        }

        lazy var avatarPicker = Connection<ImagePickerModel> { [weak parent] output in
            guard let parent = parent else { return }

            switch output {
            case .imageSelected(let image):
                Task {
                    await parent.uploadAvatar(image)
                }
            case .cancelled:
                parent.state.destination = nil
            }
        }
        .connect(state: \.destination, case: \.avatarPicker)
        .factory {
            ImagePickerModel(initialState: .init())
        }
    }

    func editBio() {
        let initialState = TextEntryModel.State(
            text: state.profile?.bio ?? "",
            title: "Edit Bio",
            maxLength: 500
        )
        state.destination = .bioEditor(initialState)
    }

    func changeAvatar() {
        state.destination = .avatarPicker(.init())
    }

    private func saveBio(_ bio: String) async {
        // Save bio logic
        state.profile?.bio = bio
        state.destination = nil
    }

    private func uploadAvatar(_ image: UIImage) async {
        // Upload avatar logic
        state.destination = nil
    }
}

// MARK: - SwiftUI View

struct ProfileView: View {
    @StateObject var model: ProfileViewModel

    var body: some View {
        VStack {
            // Profile display
            Text(model.state.profile?.bio ?? "No bio")

            Button("Edit Bio") {
                model.editBio()
            }

            Button("Change Avatar") {
                model.changeAvatar()
            }
        }
        .sheet(item: $model.state.destination) { destination in
            switch destination {
            case .bioEditor:
                if let vm = model.connections.bioEditor.model {
                    TextEntryView(model: vm)
                }

            case .avatarPicker:
                if let vm = model.connections.avatarPicker.model {
                    ImagePickerView(model: vm)
                }
            }
        }
    }
}
```

## Troubleshooting

### Connection Returns nil

**Problem:** `model.connections.childVM.model` returns `nil`

**Solution:** Ensure:
1. The destination enum is set to the matching case
2. A factory is provided: `.factory { ChildVM(initialState: .init()) }`
3. The case path matches: `.connect(state: \.destination, case: \.childCase)`

### State Not Syncing

**Problem:** Child ViewModel state changes don't update parent

**Solution:** Ensure:
1. Child ViewModel publishes changes via `@Published var state`
2. The destination enum conforms to `CasePathable` (or use `@CasePathable` macro)
3. The parent observes `objectWillChange`

### Output Handler Not Called

**Problem:** Child ViewModel outputs are not triggering the handler

**Solution:** Ensure:
1. The connection is active (destination is set)
2. Child ViewModel calls `sendOutput()` or uses the output publisher
3. The output handler is properly retained (use `[weak parent]`)

## See Also

- [Connection.swift](../Sources/RWLabsArchitecture/Architecture/Navigation/Connections/Connection.swift)
- [BaseConnections.swift](../Sources/RWLabsArchitecture/Architecture/Navigation/Connections/BaseConnections.swift)
- [ViewModelConnections.swift](../Sources/RWLabsArchitecture/Architecture/Navigation/Connections/ViewModelConnections.swift)
