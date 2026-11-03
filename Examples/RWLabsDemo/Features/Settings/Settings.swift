//
//  Settings.swift
//  RWLabsDemo
//
//  Signing out from deep inside the app: an output that travels settings → tab bar → app
//

import SwiftUI
import RWLabsArchitecture

@Component
final class SettingsModel: ComponentModel<SettingsModel> {
    struct State {
        var user: User
        var isConfirmingSignOut = false

        init(user: User) {
            self.user = user
        }
    }

    enum Action { case signOutTapped, signOutConfirmed }
    enum Output { case signedOut }

    override func send(_ action: Action) {
        switch action {
        case .signOutTapped:    state.isConfirmingSignOut = true
        case .signOutConfirmed: sendOutput(.signedOut)
        }
    }
}

struct SettingsView: @MainActor ComponentView {
    @ObservedObject var model: SettingsModel

    var content: some View {
        Form {
            Section("Account") {
                LabeledContent("Signed in as", value: model.user.email)
            }

            Section {
                Link("Open \"Piranesi\"", destination: URL(string: "rwlabsdemo://library/book?id=2")!)
                Link("Open a missing book", destination: URL(string: "rwlabsdemo://library/book?id=99")!)
            } header: {
                Text("Deep links")
            } footer: {
                Text("Each link goes through the system and back into the app, like one tapped in Messages. It switches tab and pushes the book.")
            }

            Section {
                button(.signOutTapped) { Text("Sign Out").foregroundStyle(.red) }
            }
        }
        .navigationTitle("Settings")
        .confirmationDialog("Sign out?", isPresented: model.binding(\.isConfirmingSignOut), titleVisibility: .visible) {
            button(.signOutConfirmed) { Text("Sign Out") }
        }
    }
}
