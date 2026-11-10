//
//  ComponentModel.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 25/10/26.
//

import Foundation

// MARK: - ComponentModel

/// The class feature ViewModels subclass, taking the model itself as its type parameter:
///
/// ```swift
/// @Component
/// final class ProfileModel: ComponentModel<ProfileModel> { … }
/// ```
///
/// The model's nested `State`, `Action` and `Output` become the `BaseViewModel` types, through
/// `ComponentTypes`. `@Component` adds that conformance; without the macro, write
/// `extension ProfileModel: ComponentTypes {}` (and `typealias Output = EmptyOutput` and so on
/// for any it doesn't declare).
///
/// Currently identical to `BaseViewModel` otherwise; app-wide additions for feature models
/// belong here.
open class ComponentModel<Model: ComponentTypes>: BaseViewModel<Model.State, Model.Action, Model.Output> {
}

// MARK: - Connections through the base type

/// A view can hold its model as `ComponentModel<EditorModel>` instead of `EditorModel`, so it
/// sees state and actions but not the model's own members. These two keep the connections
/// reachable that way: `model.children.preview` and `model.connections.preview` work on either type.
extension ComponentModel where Model: HasConnections {
    /// The model's `Connections`, for `push`, `present` and `bindingModel`
    public var connections: Model.ConnectionsType {
        concreteModel.connections
    }

    /// Typed access to the children by connection name, as on the model itself
    public var children: ConnectedChildren<Model.ConnectionsType> {
        ConnectedChildren(connections: concreteModel.connections)
    }

    /// `self` as the subclass. A `ComponentModel<Model>` is always a `Model`, since every
    /// component passes itself as the type parameter.
    private var concreteModel: Model {
        guard let model = self as? Model else {
            preconditionFailure("\(type(of: self)) isn't a \(Model.self); a component must pass itself as ComponentModel's type parameter")
        }
        return model
    }
}

/// Names a model's `State`, `Action` and `Output`, so `ComponentModel` can take the model itself
/// as its only type parameter. `@Component` adds the conformance.
public protocol ComponentTypes {
    associatedtype State: ViewModelState
    associatedtype Action: ViewModelAction
    associatedtype Output: ViewModelOutput
}

import CasePaths

fileprivate class TestViewModel: ComponentModel<TestViewModel> {
    struct State: ViewModelState {
        var isLoading: Bool
        
        var error: (any Error)?
        
        var destination: Destination?
    }
    
    class Connections: ViewModelConnections<TestViewModel> {
        lazy var testDetail = Connection<TestDetailViewModel> {
            guard let parent = self.parent else { return }
            switch $0 {
                case .dummyOutput:
                break
            }
        }.connect(state: \.destination, case: \.detail, parent: parent)
    }
    
    @CasePathable
    enum Destination: ViewModelDestination {
        case detail(TestDetailViewModel.State)
    }
    
    enum Action: ViewModelAction {
        
    }
    
    enum Output: ViewModelOutput {
        
    }
}

fileprivate class TestDetailViewModel: ComponentModel<TestDetailViewModel> {
    struct State: ViewModelState {
        var isLoading: Bool
        
        var error: (any Error)?
        
        var destination: Destination?
    }
    
    enum Destination: ViewModelDestination {
        
    }
    
    enum Action: ViewModelAction {
        
    }
    
    enum Output: ViewModelOutput {
        case dummyOutput
    }
}

extension TestViewModel: ComponentTypes {}
extension TestDetailViewModel: ComponentTypes {}
