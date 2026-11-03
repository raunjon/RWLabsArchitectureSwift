//
//  MainTab.swift
//  RWLabsDemo
//
//  A tab bar: every tab's state lives here, connected directly, so tabs keep their
//  navigation while the user switches
//

import SwiftUI
import RWLabsArchitecture

@Component
final class MainTabModel: ComponentModel<MainTabModel> {
    enum Tab: Hashable { case library, settings }

    struct State {
        var selectedTab: Tab = .library
        var library = LibraryModel.State()
        var settings: SettingsModel.State

        init(user: User) {
            settings = .init(user: user)
        }
    }

    enum Output { case signedOut }

    final class Connections: ConnectionsBase {
        lazy var library: LibraryModel = Connection<LibraryModel>()
            .connect(from: parent!, to: \.library)

        lazy var settings: SettingsModel = Connection<SettingsModel> { [weak parent] output in
            switch output {
            case .signedOut: parent?.sendOutput(.signedOut)       // bubbles up to AppModel
            }
        }
        .connect(from: parent!, to: \.settings)
    }
}

/// The tab bar isn't driven by `destination`, so it picks the tab for a link itself
extension MainTabModel: DeepLinkStepHandler {
    func openDeepLinkStep(_ step: DeepLinkStep) -> (any ViewModel)? {
        switch step.name {
        case "library":  state.selectedTab = .library;  return connections.library
        case "settings": state.selectedTab = .settings; return connections.settings
        default:         return nil
        }
    }
}

struct MainTabView: @MainActor ComponentView {
    @ObservedObject var model: MainTabModel

    var content: some View {
        TabView(selection: model.binding(\.selectedTab)) {
            NavigationStack { LibraryView(model: model.connections.library) }
                .tabItem { Label("Library", systemImage: "books.vertical") }
                .tag(MainTabModel.Tab.library)

            NavigationStack { SettingsView(model: model.connections.settings) }
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(MainTabModel.Tab.settings)
        }
    }
}
