//
//  BaseViewModel.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 12/01/26.
//

import Combine
import SwiftUI

// MARK: - BaseViewModel

/// The base class for ViewModels: holds `state`, emits `outputs`, and provides
/// loading, error, binding and async helpers.
///
/// Feature ViewModels subclass `ComponentModel`, which inherits from this.
@MainActor
open class BaseViewModel<State: ViewModelState, Action: ViewModelAction, Output: ViewModelOutput>: @MainActor ViewModel {
    public typealias Destination = State.Destination

    /// Identity; equality and hashing use only this
    public let id = UUID()

    /// The model's state; views and connections observe it
    @Published public var state: State

    /// App-provided error handler. Every app must register one before creating a ViewModel.
    @Injected var errorService: ErrorService

    /// Subject behind `outputs`; emit through `sendOutput(_:)`
    public let outputSubject = PassthroughSubject<Output, Never>()

    /// Events for the parent, usually consumed by a connection's output handler
    public var outputs: AnyPublisher<Output, Never> {
        outputSubject.eraseToAnyPublisher()
    }

    /// Subscriptions kept alive for the model's lifetime
    public var cancellables = Set<AnyCancellable>()

    /// Set by the case connection that created this model; used by `popToRoot()` and `close()`
    var parentLink: ParentLink?
    /// The links of the children this model's case connections currently hold
    var childLinks: [ParentLink] = []

    /// Current navigation destination; the same as reading or writing `state.destination`
    public var destination: Destination? {
        get { state.destination }
        set { state.destination = newValue }
    }

    /// Clears `destination`
    public func dismiss() {
        self.destination = nil
    }

    required public init(initialState: State) {
        self.state = initialState
    }

    /// Handles an action; subclasses must override
    open func send(_ action: Action) {
        fatalError("Must override send(_:) in subclass")
    }

    /// Emits `output` to the parent
    public func sendOutput(_ output: Output) {
        outputSubject.send(output)
    }

    /// Stores `error` in `state.error` and forwards it to the `ErrorService`
    open func handleError(_ error: Error) {
        state.error = error
        errorService.handleError(error)
    }

    /// Sets `state.isLoading` to `true`
    public func startLoading() {
        updateLoading(to: true)
    }

    /// Sets `state.isLoading` to `false`
    public func stopLoading() {
        updateLoading(to: false)
    }

    /// Sets `state.isLoading`
    public func updateLoading(to loading: Bool) {
        updateState {
            $0.isLoading = loading
        }
    }

    /// Keeps `cancellable` alive for the model's lifetime
    public func store(_ cancellable: AnyCancellable) {
        cancellables.insert(cancellable)
    }

    /// Called by the view's `body` each time it appears, so it may run many times
    open func onAppear() {
    }

    /// Subscribes `handler` to `outputs` for the model's lifetime
    @discardableResult
    public func onOutput(_ handler: @escaping ((Output) -> Void)) -> Self {
        store(
            outputs.sink(receiveValue: handler)
        )
        return self
    }

    public static func == (lhs: BaseViewModel<State, Action, Output>, rhs: BaseViewModel<State, Action, Output>) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Bindings

    /// A `Binding` into `state` at `keyPath`.
    /// Writes that don't change an `Equatable` value are skipped.
    public func binding<Value>(_ keyPath: WritableKeyPath<State, Value>, file: StaticString = #filePath, line: UInt = #line) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { newValue in
                if let current = self.state[keyPath: keyPath] as? any Equatable,
                   Self.isEqual(current, newValue) {
                    return
                }
                self.state[keyPath: keyPath] = newValue
            }
        )
    }

    private nonisolated static func isEqual<A: Equatable>(_ lhs: A, _ rhs: Any) -> Bool {
        lhs == (rhs as? A)
    }

    // MARK: - Async Work

    /// Runs `operation` in a `Task` on the main actor with `isLoading` on.
    ///
    /// The result is passed to `then`. A thrown error goes to `handleError(_:)`,
    /// except `CancellationError`, which is ignored. Returns the task so the
    /// caller can cancel it.
    ///
    /// ```swift
    /// perform { try await api.save(item) }
    /// perform { try await api.fetchItems() } then: { state.items = $0 }
    /// ```
    @discardableResult
    public final func perform<T>(
        _ operation: @escaping () async throws -> T,
        then: ((T) -> Void)? = nil
    ) -> Task<Void, Never> {
        startLoading()
        return Task {
            defer { stopLoading() }
            do {
                let result = try await operation()
                then?(result)
            } catch is CancellationError {
                // Cancelled on purpose; not an error to report
            } catch {
                handleError(error)
            }
        }
    }
}

// MARK: - Empty Types

/// State for a model with no data of its own
public struct EmptyState: ViewModelState {
    public typealias Destination = EmptyDestination

    public var isLoading: Bool = false
    public var error: Error? = nil
    public var destination: EmptyDestination? = nil

    public init() {}
}

/// Destination for a model that never navigates. It has no cases, so
/// `destination` can only ever be `nil`.
public enum EmptyDestination: ViewModelDestination {
    public var id: String { switch self {} }
}

/// Action type for a model that handles no actions
public enum EmptyAction: ViewModelAction {}

/// Output type for a model that never emits
public enum EmptyOutput: ViewModelOutput {}

// MARK: - Common State Properties

public extension ViewModelState {
    /// Whether `error` is set
    var hasError: Bool {
        error != nil
    }

    /// Clears `error`
    mutating func clearError() {
        error = nil
    }
}
