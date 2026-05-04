# Flow Architecture

## Overview

The Flow architecture provides a hierarchical system for managing application flows (e.g., authenticated vs. non-authenticated states) with support for subflows. This works alongside the existing NavigationCoordinator to provide a complete navigation solution.

## Concepts

### Flow vs. Navigation

- **Flow**: High-level application state representing major user journeys (e.g., authenticated, onboarding, checkout)
- **Navigation**: Low-level screen-to-screen transitions within a flow

Think of it as:
- **FlowCoordinator** manages which "app mode" you're in
- **NavigationCoordinator** manages where you navigate within that mode

### Key Components

1. **Flow Protocol**: Defines a logical flow with:
   - Unique identifier
   - Initial destination
   - Subflows (optional hierarchical flows)
   - Entry guards (`canEnter()`)
   - Exit hooks (`onExit()`)

2. **FlowCoordinator**: Manages flow lifecycle:
   - Setting root flows
   - Entering/exiting subflows
   - Flow transitions with validation
   - Flow state tracking

3. **FlowContainer**: SwiftUI view that observes flow state and renders appropriate UI

## Basic Usage

### 1. Define Your Flows

```swift
import RWLabsArchitecture

// Define destinations for your flow
enum AuthenticatedDestination: Destination {
    case home
    case profile
    case settings

    static var featureId: String { "authenticated" }
    var presentationStyle: PresentationStyle { .push }
}

// Define the flow
struct AuthenticatedFlow: Flow {
    let id = "authenticated"

    static var initialDestination: any Destination {
        AuthenticatedDestination.home
    }

    func canEnter() -> Bool {
        // Check authentication state
        return AuthService.shared.isAuthenticated
    }

    func onExit() {
        // Cleanup when exiting flow
        print("User logged out")
    }
}
```

### 2. Create Subflows (Optional)

```swift
struct OnboardingFlow: Flow {
    let id = "onboarding"

    static var initialDestination: any Destination {
        OnboardingDestination.step1
    }

    func canEnter() -> Bool {
        // Only show onboarding if not seen before
        return !UserDefaults.app.bool(forKey: "hasSeenOnboarding")
    }

    func onExit() {
        // Mark as completed
        UserDefaults.app.set(true, forKey: "hasSeenOnboarding")
    }
}

// Add as subflow to parent flow
struct NonAuthenticatedFlow: Flow {
    let id = "nonAuthenticated"

    static var initialDestination: any Destination {
        NonAuthenticatedDestination.welcome
    }

    var subflows: [any Flow] {
        [OnboardingFlow()]
    }
}
```

### 3. Setup in AppCoordinator

```swift
AppCoordinator.shared.onSetupInitialFlow = { flowCoordinator in
    // Determine initial flow based on app state
    if AuthService.shared.isAuthenticated {
        flowCoordinator.setRootFlow(AuthenticatedFlow(), animated: false)
    } else {
        flowCoordinator.setRootFlow(NonAuthenticatedFlow(), animated: false)
    }

    // Register flow guards (optional)
    flowCoordinator.registerGuard(for: "authenticated") { from, to in
        return AuthService.shared.isAuthenticated
    }
}
```

### 4. Create Flow Views

```swift
struct FlowRootView: View {
    @EnvironmentObject var flowCoordinator: FlowCoordinator
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var navigator: SwiftUINavigator

    var body: some View {
        FlowContainer(flowCoordinator: flowCoordinator) { activeFlow in
            Group {
                if let flow = activeFlow {
                    switch flow.id {
                    case "authenticated":
                        AuthenticatedFlowView()
                    case "nonAuthenticated":
                        NonAuthenticatedFlowView()
                    default:
                        Text("Unknown flow")
                    }
                }
            }
        }
    }
}

struct AuthenticatedFlowView: View {
    @EnvironmentObject var navigationCoordinator: NavigationCoordinator
    @EnvironmentObject var navigator: SwiftUINavigator

    var body: some View {
        NavigationStack(path: navigator.pathBinding(for: AuthenticatedDestination.home)) {
            HomeView()
                .navigationDestination(for: AnyDestination.self) { destination in
                    // Handle navigation within this flow
                    destinationView(for: destination)
                }
        }
    }

    @ViewBuilder
    private func destinationView(for destination: AnyDestination) -> some View {
        if let authDest = destination.base as? AuthenticatedDestination {
            switch authDest {
            case .home: HomeView()
            case .profile: ProfileView()
            case .settings: SettingsView()
            }
        }
    }
}
```

### 5. Use in Your App

```swift
@main
struct MyApp: App {
    @StateObject private var appCoordinator = AppCoordinator.shared

    init() {
        AppCoordinator.shared.onSetupInitialFlow = { flowCoordinator in
            // Setup flows...
        }
    }

    var body: some Scene {
        WindowGroup {
            if let navCoordinator = appCoordinator.navigationCoordinator,
               let flowCoordinator = appCoordinator.flowCoordinator {
                let navigator = SwiftUINavigator(coordinator: navCoordinator)

                FlowRootView()
                    .environmentObject(navCoordinator)
                    .environmentObject(flowCoordinator)
                    .environmentObject(navigator)
            }
        }
    }
}
```

## Flow Operations

### Set Root Flow
```swift
flowCoordinator.setRootFlow(AuthenticatedFlow(), animated: true)
```

### Enter Subflow
```swift
// From parent flow, enter a subflow
flowCoordinator.enterSubflow(OnboardingFlow(), animated: true)
```

### Exit Subflow
```swift
// Return to parent flow
flowCoordinator.exitSubflow(animated: true)
```

### Replace Flow
```swift
// Replace current flow with a new one (e.g., login → authenticated)
flowCoordinator.replaceFlow(AuthenticatedFlow(), animated: true)
```

### Reset to Root
```swift
// Reset to the root flow, exiting all subflows
flowCoordinator.resetToRoot(animated: true)
```

## Flow Guards

Guards control whether a flow can be entered:

```swift
// Register a guard
flowCoordinator.registerGuard(for: "authenticated") { fromFlow, toFlow in
    // Return true if transition is allowed
    return AuthService.shared.isAuthenticated
}

// Remove a guard
flowCoordinator.removeGuard(for: "authenticated")
```

## Common Patterns

### Authentication Flow

```swift
// Non-authenticated → Authenticated
func handleSuccessfulLogin(coordinator: FlowCoordinator) {
    coordinator.replaceFlow(AuthenticatedFlow(), animated: true)
}

// Authenticated → Non-authenticated
func handleLogout(coordinator: FlowCoordinator) {
    coordinator.replaceFlow(NonAuthenticatedFlow(), animated: true)
}
```

### Onboarding

```swift
struct NonAuthenticatedFlow: Flow {
    var subflows: [any Flow] {
        [OnboardingFlow()]
    }
}

// Start onboarding
flowCoordinator.enterSubflow(OnboardingFlow())

// Complete onboarding
flowCoordinator.exitSubflow() // Returns to NonAuthenticatedFlow
```

### Multi-Step Process (e.g., Checkout)

```swift
struct CheckoutFlow: Flow {
    let id = "checkout"

    var subflows: [any Flow] {
        [
            ShippingFlow(),
            PaymentFlow(),
            ConfirmationFlow()
        ]
    }
}

// Progress through checkout
flowCoordinator.enterSubflow(ShippingFlow())
// ... complete shipping
flowCoordinator.exitSubflow()
flowCoordinator.enterSubflow(PaymentFlow())
// ... etc
```

### Temporary Detours

```swift
// Enter a temporary flow (e.g., profile completion)
flowCoordinator.enterSubflow(ProfileCompletionFlow())

// Return to main flow when done
flowCoordinator.exitSubflow()
```

## Query Methods

```swift
// Check if a flow is active
if flowCoordinator.isFlowActive("authenticated") {
    // ...
}

// Check if flow is in stack
if flowCoordinator.isFlowInStack("onboarding") {
    // ...
}

// Get flow depth (0 = root, 1+ = subflows)
let depth = flowCoordinator.flowDepth

// Get available subflows from current flow
let subflows = flowCoordinator.availableSubflows()
```

## State Observation

Access flow state in your views:

```swift
struct MyView: View {
    @EnvironmentObject var flowCoordinator: FlowCoordinator

    var body: some View {
        VStack {
            Text("Active Flow: \(flowCoordinator.state.activeFlow?.id ?? "none")")
            Text("Flow Depth: \(flowCoordinator.flowDepth)")
        }
        .onFlowChange(flowCoordinator) { newFlow in
            print("Flow changed to: \(newFlow?.id ?? "none")")
        }
    }
}
```

## Integration with NavigationCoordinator

FlowCoordinator and NavigationCoordinator work together:

1. **FlowCoordinator** manages which flow is active
2. When entering a flow, FlowCoordinator navigates to its `initialDestination`
3. **NavigationCoordinator** handles all navigation within that flow
4. When switching flows, FlowCoordinator automatically navigates to the new flow's initial destination

```swift
// Switch flows - FlowCoordinator handles the navigation
flowCoordinator.replaceFlow(AuthenticatedFlow())

// Navigate within current flow - use NavigationCoordinator
navigationCoordinator.navigate(to: AuthenticatedDestination.profile)
```

## Best Practices

1. **One Flow = One User Context**: Each flow should represent a distinct user journey or app state
2. **Use Subflows for Multi-Step Processes**: Break complex flows into manageable subflows
3. **Implement canEnter() Guards**: Always validate flow transitions
4. **Clean Up in onExit()**: Reset state, clear caches, cancel operations
5. **Keep Flows Focused**: Don't nest too deeply (2-3 levels max)
6. **Document Flow Transitions**: Comment complex flow logic for maintainability

## Example Use Cases

- **Authentication**: NonAuthenticated ↔ Authenticated flows
- **Onboarding**: First-time user experience as a subflow
- **Feature Tours**: Guided tours as temporary subflows
- **Checkout**: Multi-step purchase process
- **Profile Setup**: Required profile completion flow
- **Guest Mode**: Different flow for guest users vs. authenticated
- **Admin Mode**: Separate flow for admin features

## Debugging

Enable flow transition logging:

```swift
// Transitions are automatically logged:
// ✅ Set root flow: nonAuthenticated
// ✅ Entered subflow: onboarding from nonAuthenticated
// ✅ Exited subflow: onboarding, returned to nonAuthenticated
// ✅ Replaced flow with: authenticated

// Access transition history
for transition in flowCoordinator.state.transitionHistory {
    print("From: \(transition.from ?? "none") → To: \(transition.to)")
}
```

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                        App                              │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │          AppCoordinator                          │  │
│  │  ┌──────────────┐    ┌────────────────────┐    │  │
│  │  │NavigationCo  │    │  FlowCoordinator   │    │  │
│  │  │ordinator     │◄───│                    │    │  │
│  │  └──────────────┘    └────────────────────┘    │  │
│  └─────────────────────────────────────────────────┘  │
│                                                         │
│  ┌─────────────────────────────────────────────────┐  │
│  │          FlowRootView                            │  │
│  │                                                  │  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │ NonAuthenticatedFlow                     │  │  │
│  │  │   ├─ WelcomeView                         │  │  │
│  │  │   ├─ LoginView                           │  │  │
│  │  │   └─ Subflows:                           │  │  │
│  │  │       └─ OnboardingFlow                  │  │  │
│  │  │           ├─ Step1                       │  │  │
│  │  │           ├─ Step2                       │  │  │
│  │  │           └─ Step3                       │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  │                        ↕                         │  │
│  │  ┌──────────────────────────────────────────┐  │  │
│  │  │ AuthenticatedFlow                        │  │  │
│  │  │   ├─ HomeView                            │  │  │
│  │  │   ├─ ProfileView                         │  │  │
│  │  │   └─ SettingsView                        │  │  │
│  │  └──────────────────────────────────────────┘  │  │
│  └─────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```
