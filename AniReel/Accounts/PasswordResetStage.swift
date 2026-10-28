/// The forgot-password step strip (D10): email → reset → done. The middle step names what the
/// backend actually does: reset on this iPhone for the local service, check inbox for a remote one.
enum PasswordResetStage: Int, CaseIterable {
    case email
    case reset
    case done

    enum ResetKind: Equatable {
        case onDevice
        case inbox
    }

    /// Before the backend answers, the local V1 behaviour is shown.
    static func resetKind(for route: PasswordResetRoute?) -> ResetKind {
        if case .emailSent = route { .inbox } else { .onDevice }
    }

    /// Steps up to and including `self` are filled.
    func isReached(_ step: PasswordResetStage) -> Bool { step.rawValue <= rawValue }
}
