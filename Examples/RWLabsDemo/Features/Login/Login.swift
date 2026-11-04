//
//  Login.swift
//  RWLabsDemo
//
//  Validation, async work with loading and errors, and an output to the parent
//

import SwiftUI
import RWLabsArchitecture

@Component
final class LoginModel: ComponentModel<LoginModel> {
    struct State {
        var email = "reader@example.com"
        var password = ""
        var emailError: String?
        var passwordError: String?
    }

    enum Action { case signInTapped }
    enum Output { case signedIn(User) }

    @Injected var validator: ValidationService
    @Injected var session: SessionService

    override func send(_ action: Action) {
        switch action {
        case .signInTapped:
            state.clearError()
            guard validate() else { return }
            perform { [session, email = state.email, password = state.password] in
                try await session.signIn(email: email, password: password)
            } then: { [weak self] user in
                self?.sendOutput(.signedIn(user))
            }
        }
    }

    private func validate() -> Bool {
        let email = validator.validate(state.email, rules: [.required, .email])
        let password = validator.validate(state.password, rules: [.required, .minLength(4)])
        updateState {
            $0.emailError = email.errors.first
            $0.passwordError = password.errors.first
        }
        return email.isValid && password.isValid
    }
}

struct LoginView: @MainActor ComponentView {
    @ObservedObject var model: LoginModel

    var content: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: model.binding(\.email))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    if let error = model.emailError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                    SecureField("Password", text: model.binding(\.password))
                    if let error = model.passwordError {
                        Text(error).foregroundStyle(.red).font(.footnote)
                    }
                } footer: {
                    Text("Any password of 4+ characters signs in, except \"wrong\".")
                }

                if let error = model.error {
                    Section {
                        Text(error.localizedDescription).foregroundStyle(.red)
                    }
                }

                Section {
                    button(.signInTapped) {
                        HStack {
                            Text("Sign In")
                            Spacer()
                            if model.isLoading { ProgressView() }
                        }
                    }
                    .disabled(model.isLoading)
                }
            }
            .navigationTitle("Shelf")
        }
    }
}
