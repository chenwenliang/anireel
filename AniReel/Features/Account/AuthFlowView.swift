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
                ToolbarItem(placement: .principal) {
                    BrandMark(size: 26, gradient: true)
                }
            }
        }
    }
}

/// White, minimal auth page: optional register/login switch, title, honest subtitle, fields,
/// primary button. The gradient mark sits in the navigation bar.
private struct AuthScaffold<Content: View>: View {
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?
    var reason: LocalizedStringKey?
    /// Register and login show the 注册 | 登录 switch (D10); reset password does not.
    var segment: AuthScreen?
    var onSwitch: (AuthScreen) -> Void = { _ in }
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let segment {
                    AuthSegment(selected: segment, onSelect: onSwitch)
                        .padding(.top, 4)
                }
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

/// 注册 | 登录 segmented switch.
private struct AuthSegment: View {
    let selected: AuthScreen
    let onSelect: (AuthScreen) -> Void

    var body: some View {
        HStack(spacing: 0) {
            option(.register, title: "Sign Up")
            option(.login, title: "Log In")
        }
        .padding(3)
        .background(Theme.Palette.groupedBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy, value: selected)
    }

    private func option(_ screen: AuthScreen, title: LocalizedStringKey) -> some View {
        let isSelected = screen == selected
        return Button { onSelect(screen) } label: {
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isSelected ? Theme.Palette.ink : Theme.Palette.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Theme.Palette.surface)
                            .shadow(color: .black.opacity(0.08), radius: 3, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// email → reset → done; the middle step names what this backend actually does.
private struct ResetStepStrip: View {
    let stage: PasswordResetStage
    let kind: PasswordResetStage.ResetKind

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(PasswordResetStage.allCases, id: \.self) { step in
                let reached = stage.isReached(step)
                VStack(alignment: .leading, spacing: 5) {
                    Capsule()
                        .fill(reached ? AnyShapeStyle(Theme.Gradients.mark) : AnyShapeStyle(Theme.Palette.groupedBackground))
                        .frame(height: 4)
                    (Text(verbatim: "\(step.rawValue + 1) ") + title(for: step))
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(reached ? Theme.Palette.ink : Theme.Palette.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(stage.rawValue + 1) of \(PasswordResetStage.allCases.count)"))
    }

    private func title(for step: PasswordResetStage) -> Text {
        switch step {
        case .email: Text("Email")
        case .reset: kind == .inbox ? Text("Check inbox") : Text("Reset on this iPhone")
        case .done: Text("Done")
        }
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
        AuthScaffold(title: "Create Account", subtitle: "Free, and stored only on this iPhone.", reason: reason, segment: .register, onSwitch: switchTo) {
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
            VStack(spacing: 2) {
                Text("By creating an account you agree to the")
                HStack(spacing: 12) {
                    NavigationLink("Terms of Service") { LegalDocumentView(document: .terms) }
                    NavigationLink("Privacy Policy") { LegalDocumentView(document: .privacyPolicy) }
                }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Palette.ink)
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.secondaryInk)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
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
        AuthScaffold(title: "Welcome back.", subtitle: "Log in for unlimited recordings.", reason: reason, segment: .login, onSwitch: switchTo) {
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

    private var stage: PasswordResetStage {
        switch step {
        case .enterEmail: .email
        case .instructions: .reset
        case .done: .done
        }
    }

    private var route: PasswordResetRoute? {
        if case .instructions(let route) = step { route } else { nil }
    }

    private var passwordIssues: [CredentialIssue] {
        CredentialRules.passwordIssues(newPassword) + (newPassword == confirmation ? [] : [.confirmationMismatch])
    }

    var body: some View {
        AuthScaffold(title: "Reset Password") {
            ResetStepStrip(stage: stage, kind: PasswordResetStage.resetKind(for: route))
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
