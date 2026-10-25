//
//  CustomAlert.swift
//  RWLabsArchitecture
//
//  Custom alert overlay presented in its own window above the app
//

import SwiftUI
import UIKit

// MARK: - Public API

extension View {
    /// Presents `content` as a custom alert while `isPresented` is `true`.
    ///
    /// The alert is hosted in a separate window above everything else, over a
    /// dimmed background, with a scale-and-fade animation in and out.
    ///
    /// - Parameters:
    ///   - isPresented: Shows the alert while `true`; set to `false` when dismissed.
    ///   - dismissOnBackgroundTap: Whether tapping the dimmed background dismisses it.
    ///   - content: The alert's view.
    ///
    /// - Note: Because it runs in its own window, the alert doesn't inherit the
    ///   presenting view's environment (environment objects, custom environment
    ///   values, tint). Pass what it needs through its model.
    /// - Note: `@Environment(\.dismiss)` does nothing inside the alert. To close
    ///   it from inside, set the binding to `false` (or clear the item), usually
    ///   via the parent model.
    /// - Note: If the presenting view disappears (e.g. a tab switch), the alert
    ///   closes and the binding is reset.
    public func customAlert<AlertContent: View>(
        isPresented: Binding<Bool>,
        dismissOnBackgroundTap: Bool = true,
        @ViewBuilder content: @escaping () -> AlertContent
    ) -> some View {
        modifier(CustomAlertModifier(
            isPresented: isPresented,
            dismissOnBackgroundTap: dismissOnBackgroundTap,
            alertContent: content
        ))
    }

    /// Presents a custom alert for `item` while it's non-`nil`.
    ///
    /// Same behaviour as `customAlert(isPresented:)`; dismissing sets `item`
    /// to `nil`. The content is built when the alert appears, so it updates
    /// only through models it observes (the usual case for a child ViewModel).
    public func customAlert<T: Identifiable, AlertContent: View>(
        item: Binding<T?>,
        dismissOnBackgroundTap: Bool = true,
        @ViewBuilder destination: @escaping (T) -> AlertContent
    ) -> some View {
        modifier(CustomAlertModifier(
            isPresented: item.isPresent(),
            dismissOnBackgroundTap: dismissOnBackgroundTap,
            alertContent: {
                if let value = item.wrappedValue {
                    destination(value)
                }
            }
        ))
    }
}

// MARK: - Modifier

private struct CustomAlertModifier<AlertContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let dismissOnBackgroundTap: Bool
    @ViewBuilder let alertContent: () -> AlertContent
    @State private var overlay = WindowOverlay()

    func body(content: Content) -> some View {
        content
            // `initial: true` so an alert that's already set when the view appears is shown
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    overlay.show(
                        alertContent(),
                        dismissOnBackgroundTap: dismissOnBackgroundTap,
                        requestDismiss: { isPresented = false }
                    )
                } else {
                    overlay.hide()
                }
            }
            .onDisappear {
                guard isPresented else { return }
                overlay.hide(animated: false)
                isPresented = false
            }
    }
}

// MARK: - Window Overlay

/// Visibility shared between `WindowOverlay` and the hosted view, so both
/// dismissal paths (background tap, binding cleared in code) animate out the same way.
@MainActor
@Observable
private final class OverlayPresentation {
    var isVisible = false
}

/// Owns the overlay window for one `customAlert` modifier.
@MainActor
private final class WindowOverlay {
    private var window: UIWindow?
    private weak var previousKeyWindow: UIWindow?
    private let presentation = OverlayPresentation()
    /// Bumped on every show, so a hide animation finishing late can't tear down a newer alert
    private var generation = 0

    func show<Content: View>(_ content: Content, dismissOnBackgroundTap: Bool, requestDismiss: @escaping () -> Void) {
        guard let scene = Self.windowScene() else { return }
        generation += 1

        let window = self.window ?? Self.makeWindow(in: scene)
        self.window = window
        if scene.keyWindow !== window {
            previousKeyWindow = scene.keyWindow
        }

        presentation.isVisible = false
        let host = UIHostingController(rootView: WindowOverlayView(
            content: content,
            presentation: presentation,
            dismissOnBackgroundTap: dismissOnBackgroundTap,
            requestDismiss: requestDismiss
        ))
        host.view.backgroundColor = .clear
        host.view.accessibilityViewIsModal = true

        window.rootViewController = host
        window.makeKeyAndVisible()
    }

    func hide(animated: Bool = true) {
        guard let window, !window.isHidden else { return }
        guard animated else {
            tearDown()
            return
        }
        let hidingGeneration = generation
        withAnimation(.easeInOut(duration: 0.2)) {
            presentation.isVisible = false
        } completion: { [weak self] in
            guard let self, self.generation == hidingGeneration else { return }
            self.tearDown()
        }
    }

    private func tearDown() {
        window?.isHidden = true
        window?.rootViewController = nil
        previousKeyWindow?.makeKey()
        previousKeyWindow = nil
    }

    private static func makeWindow(in scene: UIWindowScene) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        return window
    }

    /// Prefers the active scene, but also accepts one still becoming active (e.g. during launch)
    private static func windowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
    }
}

// MARK: - Overlay View

private struct WindowOverlayView<Content: View>: View {
    let content: Content
    let presentation: OverlayPresentation
    let dismissOnBackgroundTap: Bool
    let requestDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(presentation.isVisible ? 0.4 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    if dismissOnBackgroundTap {
                        requestDismiss()
                    }
                }

            content
                .scaleEffect(presentation.isVisible ? 1.0 : 1.15)
                .opacity(presentation.isVisible ? 1.0 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                presentation.isVisible = true
            }
        }
    }
}
