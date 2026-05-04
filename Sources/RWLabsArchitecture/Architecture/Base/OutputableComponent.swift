//
//  OutputableComponent.swift
//  RWLabsArchitecture
//
//  Created by Raunak Joneja on 11/04/26.
//

import Combine

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
