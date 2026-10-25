//
//  BaseView.swift
//  RWLabsArchitecture
//
//  Protocol for ViewModel-driven SwiftUI views
//

import SwiftUI

// MARK: - BaseView Protocol

/// A SwiftUI view driven by a ViewModel.
///
/// Conformers provide `model` and `content`; the default `body` renders
/// `content` and calls `model.onAppear()` when the view appears.
///
/// Feature screens normally conform to `ComponentView` (which refines
/// `BaseView`) rather than to `BaseView` directly.
///
/// ```swift
/// struct SettingsView: ComponentView {
///     @ObservedObject var model: SettingsModel
///
///     var content: some View {
///         Form {
///             Toggle("Dark Mode", isOn: model.binding(\.isDarkMode))
///             Button("Sign Out") { model.send(.signOutTapped) }
///         }
///     }
/// }
/// ```
///
/// - Note: `onAppear()` runs every time the view appears (returning from a
///   push, switching tabs, dismissing a sheet), not just once, so keep it
///   safe to call repeatedly.
public protocol BaseView: View {
    /// The ViewModel type driving this view
    associatedtype Model: ViewModel

    /// The content view type
    associatedtype Content: View

    /// The ViewModel instance: `@ObservedObject` when a parent or connection
    /// owns it, `@StateObject` when this view owns it
    var model: Model { get }

    /// The view's UI; `body` wraps it with lifecycle handling
    @ViewBuilder var content: Content { get }
}

// MARK: - Default Body Implementation

public extension BaseView {
    /// Renders `content` and calls `model.onAppear()` when it appears
    var body: some View {
        content
            .onAppear {
                model.onAppear()
            }
    }
}

// MARK: - Tappable

/// Makes a `BaseView` tappable as a whole.
///
/// The default `body` gives the entire view a rectangular hit area
/// (including transparent regions) and calls `onTap()` when it's tapped.
public protocol Tappable {
    func onTap()
}

public extension BaseView where Self: Tappable {
    /// Renders `content`, calls `model.onAppear()`, and calls `onTap()` on tap
    var body: some View {
        content
            .contentShape(Rectangle())
            .onAppear {
                model.onAppear()
            }
            .onTapGesture {
                onTap()
            }
    }
}
