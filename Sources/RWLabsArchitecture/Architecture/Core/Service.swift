//
//  Service.swift
//  RWLabsArchitecture
//
//  Lifecycle protocol for long-lived app services
//

import Foundation

// MARK: - Service

/// A long-lived dependency with an optional start/stop lifecycle.
///
/// Singletons registered in `DependencyContainer` that conform to `Service` are
/// started by `AppCoordinator.configure()` and stopped by `teardown()`. Both
/// methods default to doing nothing.
public protocol Service {
    /// Called once when the app's services start
    func start()

    /// Called once when the app's services stop
    func stop()
}

public extension Service {
    func start() {}
    func stop() {}
}

// MARK: - ErrorService

/// App-provided error handler that `BaseViewModel.handleError(_:)` forwards to.
///
/// Every app must register one in `DependencyContainer.shared` (usually in
/// `AppCoordinator.shared.onConfigure`) before creating any ViewModel; the
/// library deliberately provides no default.
public protocol ErrorService: Service {
    func handleError(_ error: Error)
}
