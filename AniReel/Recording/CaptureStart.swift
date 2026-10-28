/// What a tap on the record button does when idle. The gate is checked before any countdown,
/// so a guest is never made to wait three seconds only to be asked to sign up.
enum CaptureStart: Equatable {
    case startNow
    case countdown(seconds: Int)
    case requireAccount

    static let selfTimerSeconds = 3

    static func plan(decision: RecordingGate.Decision, selfTimer: Bool) -> CaptureStart {
        switch decision {
        case .requiresAccount: .requireAccount
        case .allowed: selfTimer ? .countdown(seconds: selfTimerSeconds) : .startNow
        }
    }
}
