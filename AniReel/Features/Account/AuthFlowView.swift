import SwiftUI

enum AuthScreen: Hashable, Identifiable {
    case register
    case login
    case forgotPassword

    var id: Self { self }
}

/// Register / log in / forgot password in one sheet. Talks only to `AccountStore`, so it is
/// unchanged when the backend behind `AuthService` changes.
struct AuthFlowView: View {
    /// Shown above the register and login forms, e.g. why the recording gate opened this.
    var reason: LocalizedStringKey?
    let onSignedIn: () -> Void
    @State private var screen: AuthScreen
    @Environment(\.dismiss) private var dismiss

    init(start: AuthScreen, reason: LocalizedStringKey? = nil, onSignedIn: @escaping () -> Void) {
        self.reason = reason
        self.onSignedIn = onSignedIn
        _screen = State(initialValue: start)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case .register: RegisterForm(reason: reason, onSignedIn: onSignedIn) { screen = $0 }
                case .login: LoginForm(reason: reason, onSignedIn: onSignedIn) { screen = $0 }
                case .forgotPassword: ForgotPasswordForm { screen = $0 }
                }
            }
            .background(Theme.Palette.surface)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Palette.secondaryInk)
                }
            }
        }
    }
}

/// White, minimal auth page: gradient A mark, title, honest subtitle, fields, primary button.
private struct AuthScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var reason: LocalizedStringKey?
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BrandMark(size: 48, gradient: true)
                    .padding(.top, 8)
                Text(title)
                    .font(Theme.Typography.display)
                    .foregroundStyle(Theme.Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.secondaryInk)
                }
                if let reason {
                    Label(reason, systemImage: "gift")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                }
                content()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Rounded filled field container shared by text and secure fields.
private struct FieldBox<Field: View>: View {
    @ViewBuilder let field: () -> Field

    var body: some View {
        field()
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
            .background(Theme.Palette.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

private struct LinkButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.Palette.blue)
            .frame(maxWidth: .infinity)
    }
}

private struct RegisterForm: View {
    let reason: LocalizedStringKey?
    let onSignedIn: () -> Void
    let switchTo: (AuthScreen) -> Void
    @Environment(AccountStore.self) private var account
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var hasSubmitted = false
    @State private var isWorking = false
    @State private var error: AuthError?

    private var issues: [CredentialIssue] {
        CredentialRules.registrationIssues(email: email, password: password, confirmation: confirmation)
    }

    var body: some View {
        AuthScaffold(title: "Create Account", subtitle: "Free, and stored only on this iPhone.", reason: reason) {
            EmailField(email: $email)
            FieldIssues(issues: hasSubmitted ? issues.filter { $0 == .emailInvalid } : [])
            FieldBox { SecureField("Password", text: $password).textContentType(.newPassword) }
            FieldBox { SecureField("Confirm password", text: $confirmation).textContentType(.newPassword) }
            FieldIssues(issues: hasSubmitted ? issues.filter { $0 != .emailInvalid } : [])
            Text("At least 8 characters, with a letter and a number.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.secondaryInk)
            ServiceError(error: error)
            SubmitButton(title: "Create Account", isWorking: isWorking, action: submit)
            LinkButton(title: "Already have an account? Log in") { switchTo(.login) }
        }
    }

    private func submit() {
        hasSubmitted = true
        error = nil
        guard issues.isEmpty else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await account.register(email: email, password: password)
                onSignedIn()
            } catch {
                self.error = error as? AuthError ?? .storageFailure
            }
        }
    }
}

private struct LoginForm: View {
    let reason: LocalizedStringKey?
    let onSignedIn: () -> Void
    let switchTo: (AuthScreen) -> Void
    @Environment(AccountStore.self) private var account
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: AuthError?

    var body: some View {
        AuthScaffold(title: "Log In", subtitle: "Welcome back.", reason: reason) {
            EmailField(email: $email)
            FieldBox { SecureField("Password", text: $password).textContentType(.password) }
            HStack {
                Spacer()
                Button("Forgot password?") { switchTo(.forgotPassword) }
                    .font(.subheadline)
                    .foregroundStyle(Theme.Palette.secondaryInk)
            }
            ServiceError(error: error)
            SubmitButton(title: "Log In", isWorking: isWorking, action: submit)
                .disabled(email.isEmpty || password.isEmpty)
            LinkButton(title: "New here? Create an account") { switchTo(.register) }
        }
    }

    private func submit() {
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await account.signIn(email: email, password: password)
                onSignedIn()
            } catch {
                self.error = error as? AuthError ?? .storageFailure
            }
        }
    }
}

private struct ForgotPasswordForm: View {
    private enum Step: Equatable {
        case enterEmail
        case instructions(PasswordResetRoute)
        case done
    }

    let switchTo: (AuthScreen) -> Void
    @Environment(AccountStore.self) private var account
    @State private var step = Step.enterEmail
    @State private var email = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var hasSubmitted = false
    @State private var isWorking = false
    @State private var error: AuthError?

    private var passwordIssues: [CredentialIssue] {
        CredentialRules.passwordIssues(newPassword) + (newPassword == confirmation ? [] : [.confirmationMismatch])
    }

    var body: some View {
        AuthScaffold(title: "Reset Password") {
            switch step {
            case .enterEmail:
                Text("Enter the email you registered with.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                EmailField(email: $email)
                ServiceError(error: error)
                SubmitButton(title: "Continue", isWorking: isWorking, action: requestReset)
                    .disabled(email.isEmpty)
                LinkButton(title: "Back to log in") { switchTo(.login) }
            case .instructions(.emailSent(let address)):
                Notice(systemImage: "envelope.badge", title: "Check your email") {
                    Text("If an account exists for \(address), we've sent a link to reset your password.")
                }
                LinkButton(title: "Back to log in") { switchTo(.login) }
            case .instructions(.onDevice(let address)):
                Notice(systemImage: "iphone", title: "Reset on this iPhone") {
                    Text("Accounts in this version are stored only on this iPhone, and AniReel never sends email. You can set a new password for \(address) here.")
                }
                FieldBox { SecureField("New password", text: $newPassword).textContentType(.newPassword) }
                FieldBox { SecureField("Confirm password", text: $confirmation).textContentType(.newPassword) }
                FieldIssues(issues: hasSubmitted ? passwordIssues : [])
                Text("At least 8 characters, with a letter and a number.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.secondaryInk)
                ServiceError(error: error)
                SubmitButton(title: "Save New Password", isWorking: isWorking) { resetOnDevice(address) }
            case .done:
                Notice(systemImage: "checkmark.circle.fill", title: "Password updated") {
                    Text("Log in with your new password.")
                }
                SubmitButton(title: "Back to log in", isWorking: false) { switchTo(.login) }
            }
        }
    }

    private func requestReset() {
        error = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                step = .instructions(try await account.requestPasswordReset(email: email))
            } catch {
                self.error = error as? AuthError ?? .storageFailure
            }
        }
    }

    private func resetOnDevice(_ address: String) {
        hasSubmitted = true
        error = nil
        guard passwordIssues.isEmpty else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await account.resetPasswordOnDevice(email: address, newPassword: newPassword)
                step = .done
            } catch {
                self.error = error as? AuthError ?? .storageFailure
            }
        }
    }
}

private struct EmailField: View {
    @Binding var email: String

    var body: some View {
        FieldBox {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }
}

private struct SubmitButton: View {
    let title: LocalizedStringKey
    let isWorking: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isWorking { ProgressView().tint(.white) }
                Text(title)
            }
        }
        .buttonStyle(.gradient)
        .disabled(isWorking)
        .padding(.top, 4)
    }
}

private struct FieldIssues: View {
    let issues: [CredentialIssue]

    var body: some View {
        ForEach(issues, id: \.self) { issue in
            Label(issue.message, systemImage: "exclamationmark.circle")
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }
}

private struct ServiceError: View {
    let error: AuthError?

    var body: some View {
        if let error {
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Typography.caption)
                .foregroundStyle(.red)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
    }
}

private struct Notice<Message: View>: View {
    let systemImage: String
    let title: LocalizedStringKey
    @ViewBuilder let message: () -> Message

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.ink)
            message()
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Palette.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.groupedBackground, in: RoundedRectangle(cornerRadius: Theme.Radius.medium, style: .continuous))
    }
}

extension CredentialIssue {
    var message: LocalizedStringKey {
        switch self {
        case .emailInvalid: "Enter a valid email address."
        case .passwordTooShort: "Password must be at least 8 characters."
        case .passwordNeedsLetterAndDigit: "Password needs at least one letter and one number."
        case .confirmationMismatch: "Passwords don't match."
        }
    }
}

extension AuthError {
    var message: LocalizedStringKey {
        switch self {
        case .invalidEmail: "Enter a valid email address."
        case .weakPassword: "Choose a stronger password."
        case .emailInUse: "An account with this email already exists. Log in instead."
        case .invalidCredentials: "Email or password is incorrect."
        case .accountNotFound: "No account with this email on this iPhone."
        case .unsupported: "This isn't available right now."
        case .storageFailure: "Something went wrong saving your account. Please try again."
        }
    }
}
