//
//  ViewModelItemState.swift
//  ThirtyPlusPanel
//
//  Created by Raunak Joneja on 12/01/26.
//

import Combine

public protocol ViewModelItemState: ViewModelState, Identifiable, Equatable, Hashable {
    associatedtype Item: Codable&Identifiable
    var item: Item { get set }
}

public extension ViewModelItemState {
    var id: Item.ID { item.id }
}

public extension ViewModelItemState {
    func hash(into hasher: inout Hasher) {
        
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
