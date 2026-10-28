import SwiftUI

/// Account actions in 我的: sign up / log in for guests; sign out and delete account
/// (password-confirmed, App Review 5.1.1(v)) when signed in. The state itself is in the header.
struct AccountSection: View {
    @Environment(AccountStore.self) private var account
    @State private var authScreen: AuthScreen?
    @State private var isConfirmingDelete = false
    @State private var deletePassword = ""
    @State private var deleteError: AuthError?

    var body: some View {
        Group {
            switch account.state {
            case .guest:
                Section {
                    Button { authScreen = .register } label: {
                        Label("Create Account", systemImage: "person.badge.plus")
                    }
                    .buttonStyle(.gradient)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    Button { authScreen = .login } label: {
                        Label("Log In", systemImage: "person.crop.circle")
                    }
                    .buttonStyle(.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                } header: {
                    Text("Account")
                } footer: {
                    Text("Your account is stored only on this iPhone.")
                }
            case .signedIn(let signedIn):
                Section {
                    LabeledContent("Signed in as", value: signedIn.email)
                    Button("Sign Out") { Task { await account.signOut() } }
                    Button("Delete Account", role: .destructive) { isConfirmingDelete = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Your account is stored only on this iPhone.")
                }
            }
        }
        .sheet(item: $authScreen) { screen in
            AuthFlowView(start: screen) { authScreen = nil }
        }
        .alert("Delete your account?", isPresented: $isConfirmingDelete) {
            SecureField("Password", text: $deletePassword)
            Button("Delete Account", role: .destructive) {
                let password = deletePassword
                deletePassword = ""
                Task {
                    do {
                        try await account.deleteAccount(password: password)
                    } catch {
                        deleteError = error as? AuthError ?? .storageFailure
                    }
                }
            }
            Button("Cancel", role: .cancel) { deletePassword = "" }
        } message: {
            Text("Enter your password to confirm. This removes your account from this iPhone. Your videos stay in Photos and My Clips.")
        }
        .alert(
            "Couldn't delete the account",
            isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }),
            presenting: deleteError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { error in
            Text(error.message)
        }
    }
}
