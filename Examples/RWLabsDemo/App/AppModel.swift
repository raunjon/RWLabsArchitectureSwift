//
//  AppModel.swift
//  RWLabsDemo
//
//  The root flow: login, then the tab bar. Holds a deep link until the user has signed in.
//

import SwiftUI
import RWLabsArchitecture

@Component
final class AppModel: ComponentModel<AppModel> {
    struct State {
        var flow: Flow? = .login(.init())
        /// A link that arrived before sign-in, opened once the tab bar exists
        var pendingLink: Route?
    }

    @CasePathable
    enum Flow: ViewModelDestination {
        case login(LoginModel.State)
        case main(MainTabModel.State)
    }

    enum Action {
        case open(URL)
        case signedIn(User)
        case signedOut
    }

    final class Connections: ConnectionsBase {
        lazy var login = Connection<LoginModel> { [weak parent] output in
            switch output {
            case .signedIn(let user): parent?.send(.signedIn(user))
            }
        }
        .connect(state: \.flow, case: \.login, parent: parent)

        lazy var main = Connection<MainTabModel> { [weak parent] output in
            switch output {
            case .signedOut: parent?.send(.signedOut)
            }
        }
        .connect(state: \.flow, case: \.main, parent: parent)
    }

    override func send(_ action: Action) {
        switch action {
        case .open(let url):
            state.pendingLink = Route(url: url)
            openPendingLink()

        case .signedIn(let user):
            state.flow = .main(.init(user: user))
            openPendingLink()

        case .signedOut:
            state.flow = .login(.init())
        }
    }

    /// Opens the stored link if the tab bar is showing; otherwise it waits for sign-in
    private func openPendingLink() {
        guard let route = state.pendingLink, let main = connections.main.model else { return }
        state.pendingLink = nil
        main.openDeepLink(route)
    }
}

struct AppView: @MainActor ComponentView {
    @ObservedObject var model: AppModel

    var content: some View {
        switch model.flow {
        case .login:
            model.connections.login.model.map(LoginView.init)
        case .main:
            model.connections.main.model.map(MainTabView.init)
        case nil:
            ProgressView()
        }
    }
}
