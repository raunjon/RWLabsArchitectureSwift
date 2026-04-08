# Platform-Agnostic Navigation Architecture

## Overview

This navigation system is designed to be:
- **Platform-agnostic**: Core logic works across iOS, macOS, tvOS, etc.
- **View-agnostic**: Works with both SwiftUI and UIKit
- **Modular**: Each feature defines its own destinations
- **Scalable**: Easy to add new features without modifying core code
- **Deep linking ready**: Built-in URL routing support

## Architecture Layers

```
┌─────────────────────────────────────┐
│   Features (Auth, Products, etc.)   │
│   - Define Destination enums        │
│   - Implement FeatureRouter         │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   NavigationCoordinator (Core)      │
│   - Platform-agnostic               │
│   - Manages state                   │
│   - Emits commands                  │
│   - Handles deep links              │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│   Platform Navigators               │
│   - SwiftUINavigator                │
│   - UIKitNavigator (future)         │
│   - AppKitNavigator (future)        │
└─────────────────────────────────────┘
```

## Quick Start

### 1. Define Your Feature Destination

```swift
// Features/Auth/LoginFeature.swift
public enum LoginDestination: Destination {
    case login
    case signUp
    case forgotPassword

    public static var featureId: String { "auth" }

    public var presentationStyle: PresentationStyle {
        switch self {
        case .forgotPassword:
            return .modal
        default:
            return .push
        }
    }
}
```

### 2. Create a Feature Router (for deep linking)

```swift
public struct LoginFeatureRouter: FeatureRouter {
    public static var featureId: String { "auth" }
    public static var routePatterns: [String] { ["/login", "/signup"] }

    public func destination(for route: Route) -> (any Destination)? {
        switch route.path {
        case "/login": return LoginDestination.login
        case "/signup": return LoginDestination.signUp
        default: return nil
        }
    }

    public func route(for destination: any Destination) -> Route? {
        guard let loginDest = destination as? LoginDestination else { return nil }
        switch loginDest {
        case .login: return Route(path: "/login")
        case .signUp: return Route(path: "/signup")
        case .forgotPassword: return Route(path: "/forgot-password")
        }
    }
}
```

### 3. Register Your Router at App Startup

```swift
// RWLDesignSystemApp.swift
init() {
    let coordinator = NavigationCoordinator()
    coordinator.register(router: LoginFeatureRouter())
    coordinator.register(router: ProductFeatureRouter())
    // ... register other features
}
```

### 4. Use in ViewModels (Platform-Agnostic)

```swift
class LoginViewModel {
    let coordinator: NavigationCoordinator

    func onLoginSuccess() {
        // Just tell the coordinator where to go
        // Platform navigator handles the actual navigation
        coordinator.navigate(to: LoginDestination.home)
    }

    func onForgotPassword() {
        // Modal presentation (determined by destination's presentationStyle)
        coordinator.navigate(to: LoginDestination.forgotPassword)
    }

    func navigateToSignUp() {
        coordinator.navigate(to: LoginDestination.signUp)
    }
}
```

### 5. Use in SwiftUI Views

```swift
struct LoginScreen: View {
    @EnvironmentObject var coordinator: NavigationCoordinator
    @EnvironmentObject var navigator: SwiftUINavigator
    @StateObject private var model: LoginViewModel

    var body: some View {
        NavigationStack(path: navigator.pathBinding(for: LoginDestination.self)) {
            VStack {
                // Your login UI

                DSButton(title: "Sign Up") {
                    coordinator.navigate(to: LoginDestination.signUp)
                }
            }
            .navigationDestination(for: LoginDestination.self) { destination in
                switch destination {
                case .login:
                    LoginScreen()
                case .signUp:
                    SignUpScreen()
                case .forgotPassword:
                    ForgotPasswordModal()
                }
            }
        }
    }
}
```

### 6. Cross-Feature Navigation

```swift
// From ProductViewModel, navigate to Login
func onAddToCartRequiresAuth() {
    // No need to know about LoginFeature's implementation
    // Just navigate to the destination
    coordinator.navigate(to: LoginDestination.login)
}

// From LoginViewModel, navigate to Products
func onLoginSuccess() {
    coordinator.navigate(to: ProductDestination.list)
}
```

### 7. Deep Linking

Deep links are handled automatically:

```swift
// App receives URL: myapp://product/123
// NavigationCoordinator automatically:
// 1. Parses URL -> Route(path: "/product/123")
// 2. Finds ProductFeatureRouter
// 3. Converts Route -> ProductDestination.detail(id: "123")
// 4. Navigates to destination

// In your app:
.onOpenURL { url in
    navigationCoordinator.handleDeepLink(url)
}
```

### 8. Generate URLs from Destinations

```swift
// Generate shareable URL
let destination = ProductDestination.detail(id: "123")
if let url = coordinator.url(for: destination, scheme: "myapp") {
    // url = "myapp://product/123"
    // Share or use for universal links
    shareURL(url)
}
```

## Presentation Styles

Destinations declare how they should be presented:

```swift
public enum PresentationStyle {
    case push           // NavigationStack push
    case modal          // Sheet presentation
    case fullScreen     // Full screen modal
    case replace        // Replace current screen
    case popToRoot      // Reset navigation
}
```

The **platform navigator** interprets these based on the UI structure.

## Adding New Features

1. Create destination enum conforming to `Destination`
2. Create router implementing `FeatureRouter`
3. Register router in app startup
4. Use `coordinator.navigate(to:)` in ViewModels

**No changes to core navigation code needed!**

## Platform-Specific Navigators

### SwiftUI Navigator

Currently implemented. Uses `NavigationStack` and bindings.

### UIKit Navigator (Future)

Would use `UINavigationController`:

```swift
class UIKitNavigator {
    let coordinator: NavigationCoordinator
    let navigationController: UINavigationController

    func execute(_ command: NavigationCommand) {
        switch command {
        case .navigate(let dest, let animated):
            let vc = viewControllerFactory.create(for: dest)
            navigationController.pushViewController(vc, animated: animated)
        // ... other commands
        }
    }
}
```

### macOS Navigator (Future)

Would use sidebar + detail pane navigation.

## Testing

Navigation logic is easy to test:

```swift
func testNavigation() {
    let coordinator = NavigationCoordinator()
    coordinator.navigate(to: LoginDestination.signUp)

    XCTAssertEqual(coordinator.path(for: LoginDestination.self).last, .signUp)
}

func testDeepLink() {
    let coordinator = NavigationCoordinator()
    coordinator.register(router: ProductFeatureRouter())

    let handled = coordinator.handleDeepLink(URL(string: "myapp://product/123")!)

    XCTAssertTrue(handled)
    XCTAssertEqual(coordinator.path(for: ProductDestination.self).last, .detail(id: "123"))
}
```

## Benefits

✅ **Modular**: Features are independent
✅ **Scalable**: Easy to add new features
✅ **Testable**: Pure Swift, no UI dependencies
✅ **Platform-agnostic**: Core works everywhere
✅ **Deep linking**: Built-in URL routing
✅ **Type-safe**: Compile-time destination checking
✅ **Centralized**: Single source of truth for navigation state
