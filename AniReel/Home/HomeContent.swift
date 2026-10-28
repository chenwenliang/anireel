import Foundation

/// A bundled example of one style, shown while the user has no clips of their own and in the
/// 示例 tab (docs/PHASE7_BRIEF.md). Covers are procedural art from scripts/make_placeholder_art.py.
struct SampleWork: Equatable, Identifiable, Sendable {
    let style: StyleID
    let coverAssetName: String

    var id: String { style.rawValue }

    private static let coverNames: [StyleID: String] = [
        GhibliStylePack.id: "SampleCoverGhibli",
        ChibiStylePack.id: "SampleCoverChibi",
        NPRStylePack.id: "SampleCoverNPR",
    ]

    static func coverAssetName(for style: StyleID) -> String? { coverNames[style] }

    /// One sample per style that has a cover, in registry order.
    static func catalog(for styles: [StyleID]) -> [SampleWork] {
        styles.compactMap { style in coverNames[style].map { SampleWork(style: style, coverAssetName: $0) } }
    }
}

enum HomeFeedItem: Equatable, Identifiable {
    case clip(ClipRecord)
    case sample(SampleWork)

    var id: String {
        switch self {
        case .clip(let clip): "clip-\(clip.id.uuidString)"
        case .sample(let sample): "sample-\(sample.id)"
        }
    }
}

/// What the 作品 feed shows: the user's clips newest first, or — only when there are none —
/// the sample works. Samples and real clips are never mixed.
enum HomeFeed {
    static func items(clips: [ClipRecord], samples: [SampleWork]) -> [HomeFeedItem] {
        clips.isEmpty
            ? samples.map(HomeFeedItem.sample)
            : clips.sorted { $0.createdAt > $1.createdAt }.map(HomeFeedItem.clip)
    }
}

/// Which style the camera opens with: the one asked for, else the last used, else the first.
enum StyleChoice {
    static func resolve(requested: StyleID?, lastUsed: StyleID?, available: [StyleID]) -> StyleID? {
        if let requested, available.contains(requested) { return requested }
        if let lastUsed, available.contains(lastUsed) { return lastUsed }
        return available.first
    }
}

/// The quota chip on the home top bar and the profile header.
enum QuotaStatus: Equatable {
    case guestFree(left: Int)
    case guestUsedUp
    case signedIn(email: String)

    static func make(account: AccountState, freeGuestRecordingsLeft: Int) -> QuotaStatus {
        switch account {
        case .signedIn(let signedIn): .signedIn(email: signedIn.email)
        case .guest: freeGuestRecordingsLeft > 0 ? .guestFree(left: freeGuestRecordingsLeft) : .guestUsedUp
        }
    }
}

extension RecordingPhase {
    /// The live style may only change while idle: never mid-clip, nor while a result or alert is up.
    var allowsStyleChange: Bool { self == .ready }
}
