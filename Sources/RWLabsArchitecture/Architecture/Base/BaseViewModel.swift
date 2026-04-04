//
//  BaseViewModel.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 12/01/26.
//

import Combine
import SwiftUI

public protocol OutputableComponent {
    associatedtype Output: ViewModelOutput
    var outputs: AnyPublisher<Output, Never> { get }
    var outputSubject: PassthroughSubject<Output, Never> { get }
    var outputHandler: ((Output) -> Void)? { get set }
    var cancellables: Set<AnyCancellable> { get set }
    func sendOutput(_ output: Output)
}

extension OutputableComponent where Self: AnyObject {
    
    public var outputs: AnyPublisher<Output, Never> {
        outputSubject.eraseToAnyPublisher()
    }
    
    /// Send an output (side effect)
    public func sendOutput(_ output: Output) {
        outputSubject.send(output)
    }
}
// MARK: - Base ViewModel Implementation
/// Base class providing common ViewModel functionality
@MainActor
open class BaseViewModel<State: ViewModelState, Action: ViewModelAction, Output: ViewModelOutput, Destination: RouteDestination>: @MainActor @preconcurrency ViewModel, @MainActor OutputableComponent, @MainActor NavigationCoordinatable, @preconcurrency Equatable, @preconcurrency Hashable, @MainActor StateComponent {
    public typealias D = Destination
    
    
    public let id: UUID = UUID()

    @Published public var state: State

    public let outputSubject = PassthroughSubject<Output, Never>()

    public var outputs: AnyPublisher<Output, Never> {
        outputSubject.eraseToAnyPublisher()
    }
    
    public typealias C = BaseConnections<BaseViewModel>
    
    public var navigationCoordinator: NavigationCoordinator = .init()
    
    public var cancellables = Set<AnyCancellable>()
    
    public var outputHandler: ((Output) -> Void)?
    
    required public init(initialState: State) {
        self.state = initialState
    }

    /// Override this method to handle actions
    open func send(_ action: Action) {
        fatalError("Must override send(_:) in subclass")
    }

    /// Send an output (side effect)
    public func sendOutput(_ output: Output) {
        outputSubject.send(output)
    }

    /// Update state on main thread
    public func updateState(_ update: (inout State) -> Void) {
        update(&state)
    }

    /// Handle errors
    public func handleError(_ error: Error) {
        state.error = error
    }

    /// Start loading
    public func startLoading() {
        updateLoading(to: true)
    }

    /// Stop loading
    public func stopLoading() {
        updateLoading(to: false)
    }

    public func updateLoading(to loading: Bool) {
        updateState {
            $0.isLoading = loading
        }
    }
    /// Store cancellable
    public func store(_ cancellable: AnyCancellable) {
        cancellables.insert(cancellable)
    }
    
    open func onAppear() {
        fatalError("Must override onAppear() in subclass")
    }
        
    @discardableResult
    public func onOutput(_ handler: @escaping ((Output) -> Void)) -> Self {
        store(
            outputs.sink(receiveValue: handler)
        )
        return self
    }
    
    public static func == (lhs: BaseViewModel<State, Action, Output, Destination>, rhs: BaseViewModel<State, Action, Output, Destination>) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.id.description)
    }
    
    @MainActor
    public func binding<Value>(_ keyPath: WritableKeyPath<State, Value>, file: StaticString = #filePath, line: UInt = #line) -> Binding<Value> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { value in
                guard self.setBindingValue(keyPath, value, file: file, line: line) else { return }
            }
        )
    }
    
    @MainActor
    private func setBindingValue<Value>(_ keyPath: WritableKeyPath<State, Value>, _ value: Value, file: StaticString, line: UInt) -> Bool {
        let start = Date()
        let oldState = self.state
        let oldValue = self.state[keyPath: keyPath]
        // don't continue if change doesn't lead to state change
        guard !areMaybeEqual(oldValue, value) else { return false }
        
        self.state[keyPath: keyPath] = value
        return true
    }
    
    func areMaybeEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let lhs = lhs as? any Equatable {
            if areEqual(lhs, rhs) {
                return true
            }
        }
        return false
    }
    
    func areEqual<A: Equatable>(_ lhs: A, _ rhs: Any) -> Bool {
        lhs == (rhs as? A)
    }
}

// MARK: - Empty Implementations
public struct EmptyState: ViewModelState {
    public typealias Destination = EmptyDestination

    public var isLoading: Bool = false
    public var error: Error? = nil
    public var destination: EmptyDestination? = nil

    public init() {}
}

public struct EmptyDestination: @preconcurrency RouteDestination {
    public static let featureId: String = "empty"
    
    public static var initialDestination: EmptyDestination { EmptyDestination() }
    
    public var presentationStyle: PresentationStyle = .popToRoot
    
    public init() {}
    
    public var id: String { "UUID().uuidString" }
}

public struct EmptyAction: ViewModelAction {
    public init() {}
}

public struct EmptyOutput: ViewModelOutput {
    public init() {}
}

// MARK: - Common State Properties
public extension ViewModelState {
    var hasError: Bool {
        error != nil
    }

    mutating func clearError() {
        error = nil
    }
}
