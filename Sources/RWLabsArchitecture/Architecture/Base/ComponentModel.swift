//
//  ComponentModel.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 25/10/26.
//

import Foundation

// MARK: - ComponentModel

/// The class feature ViewModels subclass.
///
/// Currently identical to `BaseViewModel`; app-wide additions for feature
/// models belong here.
open class ComponentModel<State: ViewModelState, Action: ViewModelAction, Output: ViewModelOutput>: BaseViewModel<State, Action, Output> {
}

import CasePaths

fileprivate class TestViewModel: ComponentModel<TestViewModel.State, TestViewModel.Action, TestViewModel.Output> {
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

fileprivate class TestDetailViewModel: ComponentModel<TestDetailViewModel.State, TestDetailViewModel.Action, TestDetailViewModel.Output> {
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
