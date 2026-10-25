//
//  ViewModelProtocol.swift
//  RWLabsArchitecture
//
//  Core protocols for the State/Action/Output pattern
//

import Combine

// MARK: - ViewModelState

/// Everything a screen shows, in one struct.
///
/// Every state carries loading, error and navigation; add the screen's own data alongside:
///
/// ```swift
/// struct ProfileState: ViewModelState {
///     var profile: Profile?
///     var isLoading = false
///     var error: Error?
///     var destination: ProfileDestination?   // or EmptyDestination? if it never navigates
/// }
/// ```
///
/// States don't need to be `Equatable` or `Hashable`. A destination enum that
/// carries a state as its payload is hashed by its `id` instead.
public protocol ViewModelState {
    /// The destination enum for this screen
    associatedtype Destination: ViewModelDestination

    /// Whether async work is in progress
    var isLoading: Bool { get set }

    /// The current error, if any
    var error: Error? { get set }

    /// Where the screen is navigating to, if anywhere
    var destination: Destination? { get set }
}

// MARK: - ViewModelAction

/// What the view asks the model to do: user intent or events, usually an enum
/// (`case loginTapped`, `case emailChanged(String)`), handled in `send(_:)`.
public protocol ViewModelAction {}

// MARK: - ViewModelOutput

/// One-time events a model emits for its parent, usually an enum.
///
/// Use **state** for anything the view displays (data, loading, errors,
/// selections, form values, navigation destinations). Use an **output** for
/// things that happen once and aren't displayed: telling the parent something
/// finished (`.saved`, `.loggedOut`), analytics, haptics, copying to the clipboard.
/// Parents usually receive a child's outputs through the child's connection.
public protocol ViewModelOutput {}

// MARK: - ViewModel

/// The interface every ViewModel provides. Feature ViewModels get it by
/// subclassing `ComponentModel` rather than implementing it directly.
public protocol ViewModel: StateComponent, Identifiable, Equatable, Hashable where State: ViewModelState {
    
    associatedtype Action: ViewModelAction
    associatedtype Output: ViewModelOutput

    /// The model's state; views and connections observe it
    var state: State { get set }

    /// Handles an action from the view
    func send(_ action: Action)

    /// Events for the parent
    var outputs: AnyPublisher<Output, Never> { get }

    /// Called each time the model's view appears
    func onAppear()

    /// Subscribes `handler` to `outputs` for the model's lifetime
    @discardableResult
    func onOutput(_ handler: @escaping ((Output) -> Void)) -> Self

    init(initialState: State)
}

// MARK: - StateComponent

/// An observable object with a `state` struct.
///
/// Its properties can be read and written directly on the object, so
/// `model.email` is `model.state.email`, and `model.isValid` works for a
/// read-only computed property on the state.
@dynamicMemberLookup
public protocol StateComponent: ObservableObject {
    associatedtype State

    /// The current state
    var state: State { get set }

    /// Applies `update` to the state as one change
    func updateState(_ update: (inout State) -> Void)
}

public extension StateComponent {
    /// Applies `update` to a copy of `state` and assigns it back, so observers see one change
    func updateState(_ update: (inout State) -> Void) {
        var newState = state
        update(&newState)
        state = newState
    }

    /// Reads a state property: `model.isValid` for `model.state.isValid`
    subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        state[keyPath: keyPath]
    }

    /// Reads or writes a state property: `model.email = "a@b.c"` for `model.state.email = "a@b.c"`
    subscript<Value>(dynamicMember keyPath: WritableKeyPath<State, Value>) -> Value {
        get { state[keyPath: keyPath] }
        set { state[keyPath: keyPath] = newValue }
    }
}
