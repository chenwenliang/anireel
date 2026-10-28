import Foundation

enum CredentialIssue: Equatable, Sendable {
    case emailInvalid
    case passwordTooShort
    case passwordNeedsLetterAndDigit
    case confirmationMismatch
}

/// Client-side form rules, shared by the screens and the local service.
enum CredentialRules {
    static let minimumPasswordLength = 8

    static func normalizedEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Deliberately loose: no whitespace, one `@`, a non-empty local part, a dotted domain.
    static func isValidEmail(_ email: String) -> Bool {
        let normalized = normalizedEmail(email)
        guard !normalized.contains(where: \.isWhitespace) else { return false }
        let parts = normalized.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let labels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return labels.count >= 2 && labels.allSatisfy { !$0.isEmpty }
    }

    static func passwordIssues(_ password: String) -> [CredentialIssue] {
        var issues: [CredentialIssue] = []
        if password.count < minimumPasswordLength { issues.append(.passwordTooShort) }
        if !(password.contains(where: \.isLetter) && password.contains(where: \.isNumber)) {
            issues.append(.passwordNeedsLetterAndDigit)
        }
        return issues
    }

    static func registrationIssues(email: String, password: String, confirmation: String) -> [CredentialIssue] {
        var issues: [CredentialIssue] = isValidEmail(email) ? [] : [.emailInvalid]
        issues += passwordIssues(password)
        if password != confirmation { issues.append(.confirmationMismatch) }
        return issues
    }
}
