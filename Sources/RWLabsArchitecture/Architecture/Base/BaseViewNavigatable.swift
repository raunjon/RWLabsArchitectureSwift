//
//  BaseViewNavigatable.swift
//  RWLabsArchitecture
//
//  Navigation protocol for views with routing capabilities
//  Integrates NavigationStack with ViewModel-driven navigation
//

import SwiftUI

// MARK: - Navigatable Protocol

/// Protocol for views that support navigation routing
///
/// `Navigatable` adds navigation capabilities to views, providing:
/// - NavigationStack integration
/// - Push navigation via `.navigationDestination`
/// - Modal presentation via `.sheet`
/// - Alert presentation via `.alert`
/// - Automatic coordinator setup
///
/// # Architecture
///
/// ```
/// Navigatable
///     ├─ navigator: SwiftUINavigator<VM.D>
///     ├─ destinationView(for:) -> DestinationView
///     └─ body (NavigationStack wrapper)
/// ```
///
/// When combined with BaseView (via ComponentView), provides complete
/// navigation and state management solution.
///
/// # Usage
///
/// ## Basic Navigation View
/// ```swift
/// struct ProductListView: BaseView, Navigatable {
///     typealias VM = ProductListViewModel
///
///     @StateObject var viewModel: VM
///     let navigator: SwiftUINavigator<VM.D>
///
///     var content: some View {
///         List(viewModel.products, id: \.id) { product in
///             ProductRow(product: product)
///                 .onTapGesture {
///                     viewModel.navigate(to: .productDetail(product))
///                 }
///         }
///         .navigationTitle("Products")
///     }
///
///     func destinationView(for destination: VM.D) -> some View {
///         switch destination {
///         case .productDetail(let product):
///             ProductDetailView(
///                 viewModel: viewModel.connections.createProductDetail(product),
///                 navigator: navigator
///             )
///         }
///     }
/// }
/// ```
///
/// ## With Multiple Destination Types
/// ```swift
/// enum MainDestination: RouteDestination {
///     case profile
///     case settings
///     case productDetail(Product)
///     case cart
///
///     var presentationStyle: PresentationStyle {
///         switch self {
///         case .profile, .settings, .productDetail:
///             return .push
///         case .cart:
///             return .modal
///         }
///     }
/// }
///
/// struct MainView: BaseView, Navigatable {
///     @StateObject var viewModel: MainViewModel
///     let navigator: SwiftUINavigator<MainViewModel.D>
///
///     var content: some View {
///         VStack {
///             Button("View Profile") {
///                 viewModel.navigate(to: .profile)
///             }
///
///             Button("Open Settings") {
///                 viewModel.navigate(to: .settings)
///             }
///
///             Button("View Cart") {
///                 viewModel.navigate(to: .cart)
///             }
///         }
///     }
///
///     func destinationView(for destination: MainViewModel.D) -> some View {
///         switch destination {
///         case .profile:
///             ProfileView(
///                 viewModel: viewModel.connections.profileViewModel,
///                 navigator: navigator
///             )
///
///         case .settings:
///             SettingsView(
///                 viewModel: viewModel.connections.settingsViewModel,
///                 navigator: navigator
///             )
///
///         case .productDetail(let product):
///             ProductDetailView(
///                 viewModel: viewModel.connections.createProductDetail(product),
///                 navigator: navigator
///             )
///
///         case .cart:
///             CartView(
///                 viewModel: viewModel.connections.cartViewModel,
///                 navigator: navigator
///             )
///         }
///     }
/// }
/// ```
///
/// # Navigation Flow
///
/// ```
/// 1. User taps button
///     ↓
/// 2. View calls viewModel.navigate(to: destination)
///     ↓
/// 3. ViewModel updates NavigationCoordinator
///     ↓
/// 4. Navigator's path binding updates
///     ↓
/// 5. NavigationStack detects path change
///     ↓
/// 6. destinationView(for:) called
///     ↓
/// 7. New view pushed/presented
/// ```
///
/// # Presentation Styles
///
/// The presentation style is determined by the destination's `presentationStyle`:
/// - `.push` → NavigationStack push
/// - `.modal` / `.fullScreen` → Sheet presentation
/// - `.alert` / `.customAlert` → Alert presentation
///
/// # Automatic Coordinator Setup
///
/// The body implementation automatically:
/// 1. Calls `viewModel.onAppear()` on view appearance
/// 2. Sets the navigation coordinator via `viewModel.setCoordinator()`
///
/// This ensures the ViewModel has access to navigation capabilities.
///
/// # Requirements
///
/// Conforming types must:
/// - Provide `navigator: SwiftUINavigator<VM.D>`
/// - Implement `destinationView(for:)` to build destination views
/// - Have a ViewModel conforming to `NavigationCoordinatable`
///
/// # Integration with BaseView
///
/// When a type conforms to both BaseView and Navigatable:
/// ```swift
/// typealias ComponentView = BaseView & Navigatable
/// ```
///
/// The Navigatable body implementation takes precedence and wraps
/// the BaseView content in a NavigationStack.
///
/// # Benefits
///
/// 1. **Type-Safe Navigation**: Destinations are enum values, not strings
/// 2. **Centralized Routing**: All routing logic in `destinationView(for:)`
/// 3. **Consistent Patterns**: Same approach for all navigation types
/// 4. **Testable**: Easy to test navigation without UI
/// 5. **Coordinator Pattern**: Separates navigation from business logic
public protocol Navigatable {
    /// The ViewModel type (must support navigation coordination)
    associatedtype VM: ViewModel & NavigationCoordinatable

    /// The navigator managing navigation state for this view's destinations
    ///
    /// Typically passed down from parent view or flow coordinator:
    /// ```swift
    /// let navigator: SwiftUINavigator<ProductListDestination>
    /// ```
    var navigator: SwiftUINavigator { get }
}

public protocol Destinatationable: Navigatable {
    /// The destination view type returned by `destinationView(for:)`
    associatedtype DestinationView: View

    /// The ViewModel type (must support navigation coordination)
    associatedtype VM: ViewModel & NavigationCoordinatable

    /// Creates the view for a given destination
    ///
    /// Called by NavigationStack when navigating to a destination.
    /// Should create and configure the destination view with its ViewModel.
    ///
    /// - Parameter destination: The destination to navigate to
    /// - Returns: The view to display for this destination
    ///
    /// # Example
    /// ```swift
    /// func destinationView(for destination: VM.D) -> some View {
    ///     switch destination {
    ///     case .detail(let id):
    ///         DetailView(
    ///             viewModel: viewModel.connections.createDetail(id),
    ///             navigator: navigator
    ///         )
    ///     }
    /// }
    /// ```
    func destinationView(for destination: VM.State.Destination) -> DestinationView
}

// MARK: - Navigatable Body Implementation

public extension ComponentView{
    var title: String {
        ""
    }
}
public extension ComponentView where Self: Destinatationable   {
    var title: String {
        ""
    }
    var body: some View {
        content
            .onAppear {
                viewModel.onAppear()
                if self.title == "Entries" {
                    print("Entries")
                    print("Entries")
                    viewModel.setCoordinator(navigator.coordinator)
                    print(navigator.coordinator)
                    print(viewModel.navigationCoordinator)
                    print(self.navigator.coordinator.state == self.viewModel.navigationCoordinator.state)
                    print("navigationCoordinator")
                }
                else {
                    viewModel.setCoordinator(navigator.coordinator)
                    print(navigator.coordinator)
                    print(viewModel.navigationCoordinator)
                }
            }
            .onChange(of: viewModel) { oldValue, newValue in
                self.viewModel.setCoordinator(navigator.coordinator)
            }
            .navigationDestination(for: VM.State.Destination.self) { destination in
                destinationView(for: destination)
                    .environmentObject(navigator)
            }
            .sheet(isPresented: viewModel.isSheetPresented, content: {
                if let value = viewModel.modalDestination.wrappedValue {
                    destinationView(for: value)
                }
            })
            .customAlert(isPresented: viewModel.isCustomAlertPresented, content: {
                if let value = viewModel.customAlertDestination.wrappedValue {
                    destinationView(for: value)
                }
            })
             .alert(item: viewModel.alertDestination) { dest in
                 Alert(title: Text(viewModel.alertDestination.wrappedValue.debugDescription))
             }
             .environmentObject(navigator)
        
    }
}

public extension RoutableView {
    /// Body implementation providing NavigationStack with routing
    ///
    /// This implementation:
    /// 1. Wraps content in NavigationStack
    /// 2. Binds to navigator's path for navigation state
    /// 3. Calls `viewModel.onAppear()` and `viewModel.setCoordinator()`
    /// 4. Configures `.navigationDestination` for push navigation
    /// 5. Configures `.sheet` for modal presentation
    /// 6. Configures `.alert` for alert presentation
    ///
    /// # Navigation Bindings
    ///
    /// - **Path**: Bound to navigator's path for push navigation
    /// - **Modal**: Bound to viewModel's modalDestination for sheets
    /// - **Alert**: Bound to viewModel's alertDestination for alerts
    ///
    /// # Lifecycle
    ///
    /// On view appear:
    /// 1. `viewModel.onAppear()` - Initialize data, analytics, etc.
    /// 2. `viewModel.setCoordinator()` - Connect ViewModel to navigation
    ///
    /// # Example Flow
    ///
    /// ```
    /// View appears
    ///     ↓
    /// NavigationStack created with path binding
    ///     ↓
    /// content rendered
    ///     ↓
    /// .onAppear fires
    ///     ↓
    /// viewModel.onAppear() called
    /// viewModel.setCoordinator() called
    ///     ↓
    /// User taps → navigate(to:)
    ///     ↓
    /// Path updates
    ///     ↓
    /// .navigationDestination fires
    ///     ↓
    /// destinationView(for:) called
    ///     ↓
    /// New view pushed
    /// ```
    @MainActor
    var body: some View {
        NavigationStack(path: navigator.pathBinding(for: VM.State.Destination.self)) {
            content
                .onAppear {
                    viewModel.onAppear()
                    viewModel.setCoordinator(navigator.coordinator)
                }
                .navigationDestination(for: VM.State.Destination.self) { destination in
                destinationView(for: destination)
            }
            .sheet(isPresented: viewModel.isSheetPresented, content: {
                if let value = viewModel.modalDestination.wrappedValue {
                    destinationView(for: value)
                }
            })
            .customAlert(isPresented: viewModel.isCustomAlertPresented, content: {
                if let value = viewModel.customAlertDestination.wrappedValue {
                    destinationView(for: value)
                }
            })
             .alert(item: viewModel.alertDestination) { dest in
                 Alert(title: Text(viewModel.alertDestination.wrappedValue.debugDescription))
             }
             .environmentObject(navigator)
        }
    }
}

public extension BaseView where VM: NavigationCoordinatable {
//    public func dismiss() {
//        self.viewModel.destination = nil
//    }
}

extension View {
   
}

// MARK: - Architecture Notes

/*
 # Design Rationale

 ## Protocol Composition

 Navigatable is designed to compose with BaseView:

 ```swift
 BaseView alone:
 - ViewModel integration
 - Content separation
 - Lifecycle (onAppear)

 Navigatable alone:
 - Navigator integration
 - Destination routing
 (Can't work without BaseView - needs content)

 BaseView + Navigatable (ComponentView):
 - Full-featured component
 - ViewModel + Navigation
 - Complete lifecycle + routing
 ```

 ## Type-Safe Routing

 By requiring `destinationView(for:)` to switch on enum destinations,
 we ensure:
 - Compile-time checking of all routes
 - No typos or invalid string paths
 - Exhaustive handling of destinations
 - Clear documentation of navigation graph

 ## Navigator Passing

 The navigator is passed explicitly (not injected) to:
 - Make navigation dependencies visible
 - Enable testing with mock navigators
 - Allow multiple navigators in complex hierarchies
 - Clarify which view controls which routes

 ## Coordinator Integration

 The automatic `setCoordinator()` call connects the ViewModel to
 navigation capabilities, enabling:
 - viewModel.navigate(to:)
 - viewModel.dismiss()
 - viewModel.popToRoot()
 - Programmatic navigation from ViewModels

 ## Body Override

 When a view conforms to both BaseView and Navigatable, this body
 implementation takes precedence over BaseView's default body.

 This is intentional - navigation wrapping should be the outermost layer:
 ```
 NavigationStack
     └─ content
         └─ .onAppear { viewModel.onAppear() }
 ```

 Not:
 ```
 content
     └─ .onAppear { viewModel.onAppear() }
         └─ NavigationStack (wrong!)
 ```

 ## Presentation Styles

 The three presentation types (push, modal, alert) cover all
 common navigation patterns:

 - **Push** (.navigationDestination): Hierarchical navigation
 - **Modal** (.sheet): Temporary tasks, forms, detail views
 - **Alert** (.alert): Confirmations, errors, simple choices

 Each has its own SwiftUI modifier and binding.
 */


struct CustomAlert<Content: View>: View {

    @Binding var isPresented: Bool
    let content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if isPresented {
            ZStack {

                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        isPresented = false
                    }

                content()
            }
        }
    }
}


//struct CustomAlertModifier<AlertContent: View>: ViewModifier {
//
//    @Binding var isPresented: Bool
//    let alertContent: () -> AlertContent
//
//    func body(content: Content) -> some View {
//        ZStack {
//            content
//
//            if isPresented {
//                CustomAlert(isPresented: $isPresented) {
//                    alertContent()
//                }
//                .transition(.scale(scale: 0.9).combined(with: .opacity))
//                .animation(.spring(response: 0.25, dampingFraction: 0.9), value: isPresented)
//                .presentationBackground(.clear)
//            }
//        }
//    }
//}


// MARK: - Window Overlay Manager

@MainActor
class WindowOverlayManager: ObservableObject {
    private var overlayWindow: UIWindow?

    func show<Content: View>(content: Content, onDismiss: @escaping () -> Void) {
        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else { return }

        // Create overlay window if needed
        if overlayWindow == nil {
            let window = UIWindow(windowScene: windowScene)
            window.windowLevel = .alert + 1
            window.backgroundColor = .clear
            overlayWindow = window
        }

        // Create overlay view with dismiss action
        let overlayView = WindowOverlayView(
            content: content,
            onDismiss: onDismiss
        )

        // Host in UIHostingController
        let hostingController = UIHostingController(rootView: overlayView)
        hostingController.view.backgroundColor = .clear

        overlayWindow?.rootViewController = hostingController
        overlayWindow?.isHidden = false
    }

    func dismiss() {
        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
    }
}

// MARK: - Window Overlay View

struct WindowOverlayView<Content: View>: View {
    let content: Content
    let onDismiss: () -> Void
    @State private var isVisible = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(isVisible ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDismiss()
                    }
                }

            // Content with animation
            content
                .scaleEffect(isVisible ? 1.0 : 1.15)
                .opacity(isVisible ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75, blendDuration: 0)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Custom Alert Modifier

struct CustomAlertModifier<AlertContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let alertContent: () -> AlertContent
    @StateObject private var windowManager = WindowOverlayManager()

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, newValue in
                if newValue {
                    windowManager.show(
                        content: alertContent(),
                        onDismiss: {
                            isPresented = false
                        }
                    )
                } else {
                    windowManager.dismiss()
                }
            }
            .onDisappear {
                // Clean up window when view disappears
                if isPresented {
                    windowManager.dismiss()
                    isPresented = false
                }
            }
    }
}

// MARK: - View Extension

extension View {

    public func customAlert<AlertContent: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> AlertContent
    ) -> some View {
        self.modifier(CustomAlertModifier(isPresented: isPresented, alertContent: content))
    }
}
