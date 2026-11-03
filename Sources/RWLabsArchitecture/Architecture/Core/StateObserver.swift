//
//  StateObserver.swift
//  RWLabsArchitecture
//
//  Reports each upcoming change to a model's state, using Observation
//

import Observation

// MARK: - StateObserver

/// Calls `handler` each time `model.state` is about to change, until it's cancelled or the
/// model is freed. Connections use it to keep a parent and child in sync.
///
/// Built on `withObservationTracking`, which reports one change and then stops. Each report
/// registers again straight away, before the new value is stored, so a run of changes in the
/// same turn is reported change by change. The handler runs *before* the value changes, so
/// read the new value on a later turn.
@MainActor
final class StateObserver {
    private var isCancelled = false

    init<Model: ViewModel>(_ model: Model, handler: @escaping @MainActor @Sendable () -> Void) {
        observe(model, handler: handler)
    }

    /// Stops reporting changes
    func cancel() {
        isCancelled = true
    }

    private func observe<Model: ViewModel>(_ model: Model, handler: @escaping @MainActor @Sendable () -> Void) {
        let weakModel = WeakReference(model)
        withObservationTracking {
            _ = model.state
        } onChange: { [weak self] in
            // State is main-actor isolated, so changes (and this callback) happen on the main actor
            MainActor.assumeIsolated {
                guard let self, !self.isCancelled, let model = weakModel.value else { return }
                self.observe(model, handler: handler)
                handler()
            }
        }
    }
}

/// Carries a model into `withObservationTracking`'s `@Sendable` callback; read only on the main actor
private final class WeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}
