/// Who may start a recording (docs/DECISIONS.md D6): guests get one saved clip for free,
/// signed-in accounts are unlimited. Only successfully saved guest clips are counted.
enum RecordingGate {
    static let freeGuestRecordings = 1

    enum Decision: Equatable {
        case allowed
        case requiresAccount
    }

    static func decide(account: AccountState, savedGuestRecordings: Int) -> Decision {
        switch account {
        case .signedIn: .allowed
        case .guest: savedGuestRecordings < freeGuestRecordings ? .allowed : .requiresAccount
        }
    }
}

/// Persistent count of clips saved while signed out. Lives in the Keychain next to accounts,
/// so it survives relaunches and reinstalls and needs no UserDefaults privacy declaration.
struct GuestUsageCounter: Sendable {
    let store: any SecureStore

    var savedRecordings: Int {
        guard let data = try? store.data(for: .savedGuestRecordings),
              let text = String(data: data, encoding: .utf8)
        else { return 0 }
        return Int(text) ?? 0
    }

    /// Returns the new count. A failed write leaves the old count, which errs toward the user.
    @discardableResult
    func recordSavedClip() -> Int {
        let next = savedRecordings + 1
        do {
            try store.set(Data(String(next).utf8), for: .savedGuestRecordings)
            return next
        } catch {
            return savedRecordings
        }
    }
}
