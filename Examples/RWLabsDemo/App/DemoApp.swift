//
//  DemoApp.swift
//  RWLabsDemo
//

import SwiftUI
import RWLabsArchitecture

@main
struct DemoApp: App {
    @StateObject private var appModel: AppModel

    init() {
        AppCoordinator.shared.onConfigure = {
            let container = DependencyContainer.shared
            container.registerSingleton(ErrorService.self, instance: DemoErrorService())
            container.registerSingleton(LoggerService.self, instance: ConsoleLogger())
            container.registerSingleton(ValidationService.self, instance: DefaultValidationService())
            container.registerSingleton(BookStore.self, instance: InMemoryBookStore())
            container.registerSingleton(SessionService.self, instance: DemoSessionService())
        }
        AppCoordinator.shared.configureIfNeeded()
        // Created after the ErrorService is registered
        _appModel = StateObject(wrappedValue: AppModel(initialState: .init()))
    }

    var body: some Scene {
        WindowGroup {
            AppView(model: appModel)
                .onOpenURL { appModel.send(.open($0)) }      // rwlabsdemo://library/book?id=2
        }
    }
}
