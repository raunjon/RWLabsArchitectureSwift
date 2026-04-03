//
//  BaseView.swift
//  RWLabsArchitecture
//
//  Protocol for ViewModel-driven SwiftUI views with content separation
//  Provides automatic lifecycle handling and clean architecture patterns
//

import SwiftUI

// MARK: - BaseView Protocol

/// Protocol for SwiftUI views that follow the ViewModel pattern
///
/// `BaseView` provides a foundation for building views that:
/// - Are driven by a ViewModel with State/Action/Output pattern
/// - Separate content rendering from navigation/lifecycle logic
/// - Automatically handle view lifecycle (onAppear)
///
/// # Architecture Pattern
///
/// ```
/// BaseView
///     ├─ viewModel: VM (state management)
///     ├─ content: Content (UI rendering)
///     └─ body (lifecycle + content)
/// ```
///
/// The pattern enforces separation between:
/// - **Content**: Pure UI rendering logic
/// - **Body**: Navigation wrapper, lifecycle, and chrome
/// - **ViewModel**: Business logic and state
///
/// # Usage
///
/// ## Simple View
/// ```swift
/// struct ProductListView: BaseView {
///     typealias VM = ProductListViewModel
///
///     @StateObject var viewModel: VM
///
///     var content: some View {
///         List(viewModel.products, id: \.id) { product in
///             ProductRow(product: product)
///                 .onTapGesture {
///                     viewModel.send(.productTapped(product))
///                 }
///         }
///         .navigationTitle("Products")
///     }
/// }
/// ```
///
/// ## With Loading State
/// ```swift
/// struct UserProfileView: BaseView {
///     @StateObject var viewModel: UserProfileViewModel
///
///     var content: some View {
///         ZStack {
///             if viewModel.isLoading {
///                 ProgressView()
///             } else if let user = viewModel.user {
///                 ProfileContentView(user: user)
///             } else {
///                 EmptyStateView()
///             }
///         }
///     }
/// }
/// ```
///
/// ## With Toolbar
/// ```swift
/// struct SettingsView: BaseView {
///     @StateObject var viewModel: SettingsViewModel
///
///     var content: some View {
///         Form {
///             Section("Appearance") {
///                 Toggle("Dark Mode", isOn: $viewModel.isDarkMode)
///             }
///
///             Section("Account") {
///                 Button("Sign Out") {
///                     viewModel.send(.signOutTapped)
///                 }
///             }
///         }
///         .navigationTitle("Settings")
///         .toolbar {
///             ToolbarItem(placement: .navigationBarTrailing) {
///                 Button("Done") {
///                     viewModel.send(.doneTapped)
///                 }
///             }
///         }
///     }
/// }
/// ```
///
/// # Lifecycle Handling
///
/// The default `body` implementation automatically calls `viewModel.onAppear()`:
/// ```swift
/// public extension BaseView {
///     var body: some View {
///         content
///             .onAppear {
///                 viewModel.onAppear()  // Automatic
///             }
///     }
/// }
/// ```
///
/// This ensures consistent lifecycle handling across all views without boilerplate.
///
/// # Benefits
///
/// 1. **Separation of Concerns**: Content is separate from lifecycle/navigation
/// 2. **Automatic Lifecycle**: onAppear() called automatically
/// 3. **Testability**: Content can be tested independently
/// 4. **Consistency**: Enforces standard patterns across codebase
/// 5. **Composability**: Works with Navigatable for full ComponentView
///
/// # Default Body Implementation
///
/// BaseView provides a default body that:
/// - Renders the `content` property
/// - Calls `viewModel.onAppear()` when view appears
/// - Can be overridden for custom behavior (e.g., when using with Navigatable)
///
/// # Associated Types
///
/// - **VM**: The ViewModel type (must conform to `ViewModel` protocol)
/// - **Content**: The SwiftUI view type for content rendering
///
/// # Requirements
///
/// Conforming types must provide:
/// - `var viewModel: VM` - The ViewModel instance
/// - `var content: Content` - The content view
///
/// # When to Use
///
/// - **ViewModel-Driven Views**: Any view managed by a ViewModel
/// - **Consistent Lifecycle**: Views needing automatic onAppear handling
/// - **Content Separation**: Complex views benefiting from clean separation
/// - **Navigation Ready**: Views that may later add navigation (via Navigatable)
///
/// # When NOT to Use
///
/// - **Stateless Components**: Use plain `View` or `StatelessComponentView`
/// - **Simple Views**: Overhead not worth it for trivial views
/// - **Non-ViewModel Views**: Views not following the ViewModel pattern
///
/// # Combining with Navigatable
///
/// BaseView is designed to compose with Navigatable:
/// ```swift
/// public typealias ComponentView = BaseView & Navigatable
/// ```
///
/// When combined, Navigatable's body takes precedence and wraps the
/// content in a NavigationStack with routing capabilities.
public protocol BaseView: View {
    /// The ViewModel type managing this view's state
    associatedtype VM: ViewModel

    /// The content view type
    associatedtype Content: View

    /// The ViewModel instance
    ///
    /// Typically a `@StateObject` or `@ObservedObject` property:
    /// ```swift
    /// @StateObject var viewModel: ProductListViewModel
    /// ```
    var viewModel: VM { get set }

    /// The content to display
    ///
    /// Should contain only UI rendering logic, no navigation or lifecycle:
    /// ```swift
    /// var content: some View {
    ///     List(viewModel.items) { item in
    ///         ItemRow(item: item)
    ///     }
    /// }
    /// ```
    var content: Content { get }
}

// MARK: - Default Body Implementation

public extension BaseView {
    /// Default body implementation with automatic lifecycle handling
    ///
    /// This implementation:
    /// - Renders the `content` view
    /// - Automatically calls `viewModel.onAppear()` when view appears
    ///
    /// # Override
    ///
    /// This implementation is automatically overridden when BaseView is
    /// combined with Navigatable (via ComponentView typealias).
    ///
    /// # Example Flow
    ///
    /// ```
    /// View appears
    ///     ↓
    /// body is called
    ///     ↓
    /// content is rendered
    ///     ↓
    /// .onAppear fires
    ///     ↓
    /// viewModel.onAppear() called
    ///     ↓
    /// ViewModel loads data, updates state
    ///     ↓
    /// View re-renders with new state
    /// ```
    var body: some View {
        content
            .onAppear {
                viewModel.onAppear()
            }
    }
}

// MARK: - Architecture Notes

/*
 # Design Rationale

 ## Content Separation

 By requiring a separate `content` property, BaseView enforces a clean
 separation between:

 1. **Content Rendering** (content property)
    - Pure UI layout and styling
    - Data display
    - User interaction handlers
    - Toolbar, navigation title, etc.

 2. **Navigation Chrome** (body property)
    - NavigationStack wrapper
    - Routing logic
    - Modal/alert presentation
    - Lifecycle hooks

 This separation:
 - Makes views easier to test (test content independently)
 - Improves code organization
 - Enables reusability
 - Clarifies responsibilities

 ## Automatic Lifecycle

 The default body implementation ensures `viewModel.onAppear()` is always
 called without developers needing to remember to add it. This:
 - Reduces boilerplate
 - Prevents bugs from missing lifecycle calls
 - Provides consistent behavior
 - Centralizes lifecycle logic in ViewModels

 ## Protocol Composition

 BaseView is designed to compose with Navigatable:

 ```swift
 BaseView + Navigatable = ComponentView

 BaseView provides:
 - ViewModel integration
 - Content separation
 - Lifecycle handling

 Navigatable adds:
 - NavigationStack
 - Routing
 - Modal/alert support

 Combined = Full-featured component
 ```

 This composition pattern allows views to opt into navigation features
 only when needed, keeping simple views lightweight.

 ## Example Hierarchy

 ```
 Plain View (no ViewModel)
     ↓
 BaseView (adds ViewModel + lifecycle)
     ↓
 ComponentView (BaseView & Navigatable, adds navigation)
 ```

 Each level adds capabilities without forcing unnecessary complexity.
 */
