//
//  AppCoordinator.swift
//  RWLabsArchitecture
//
//  App startup: runs the app's setup and starts its services
//

import Foundation

// MARK: - AppCoordinator

/// Runs app setup once at launch and owns the service lifecycle.
///
/// The library registers nothing itself; the app registers every dependency in
/// `onConfigure`, including the required `ErrorService`.
///
/// ```swift
/// @main
/// struct MyApp: App {
///     init() {
///         AppCoordinator.shared.onConfigure = {
///             let container = DependencyContainer.shared
///             container.registerSingleton(ErrorService.self, instance: AppErrorService())
///             container.registerSingleton(LoggerService.self, instance: ConsoleLogger())
///         }
///         AppCoordinator.shared.configureIfNeeded()
///     }
///     …
/// }
/// ```
@MainActor
public final class AppCoordinator: ObservableObject {
    /// The shared coordinator
    public static let shared = AppCoordinator()

    /// `true` once `configure()` has run, until `teardown()`
    @Published public private(set) var isConfigured = false

    /// The app's setup: register dependencies here
    public var onConfigure: (() -> Void)?

    private init() {}

    /// Runs `configure()` unless it has already run
    public func configureIfNeeded() {
        guard !isConfigured else { return }
        configure()
    }

    /// Runs `onConfigure`, checks that an `ErrorService` is registered, then
    /// starts every registered service (see `DependencyContainer.startServices()`).
    public func configure() {
        onConfigure?()

        precondition(
            DependencyContainer.shared.isRegistered(ErrorService.self),
            "No ErrorService registered. Register one in AppCoordinator.shared.onConfigure before creating any ViewModel."
        )

        DependencyContainer.shared.startServices()
        isConfigured = true
    }

    /// Stops every started service, in reverse registration order
    public func teardown() {
        DependencyContainer.shared.stopServices()
        isConfigured = false
    }
}
