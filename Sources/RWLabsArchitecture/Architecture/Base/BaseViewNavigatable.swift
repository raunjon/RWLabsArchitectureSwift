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
    @ViewBuilder let alertContent: () -> AlertContent
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
    
    public func customAlert<T:Identifiable, AlertContent: View>(
        item: Binding<T?>,
        @ViewBuilder destination: @escaping (T) -> AlertContent
    ) -> some View {
        self.modifier(CustomAlertModifier(isPresented: item.isPresent(), alertContent: {
            if let item = item.wrappedValue {
              destination(item)
            }
        } ))
    }
}
