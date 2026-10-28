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

extension StyleChoice {
    /// The result screen's "next one in another style?" chips: every other style, in registry order.
    static func alternatives(to current: StyleID, available: [StyleID]) -> [StyleID] {
        available.filter { $0 != current }
    }
}

/// The feed's vertical reel strip (D10): one segment per page, windowed so long libraries
/// stay a short strip that slides with the current page.
struct ReelIndicator: Equatable {
    static let maxSegments = 7

    /// Indices of the pages shown as segments.
    let pages: Range<Int>
    let current: Int

    static func make(count: Int, current: Int, maxSegments: Int = ReelIndicator.maxSegments) -> ReelIndicator? {
        guard count > 1 else { return nil }
        let current = min(max(current, 0), count - 1)
        let visible = min(count, maxSegments)
        let start = min(max(current - visible / 2, 0), count - visible)
        return ReelIndicator(pages: start..<(start + visible), current: current)
    }
}

/// The three numbers on the profile card: clips, clips this week, recordings left.
struct ProfileStats: Equatable {
    enum Allowance: Equatable {
        case unlimited
        case remaining(Int)
    }

    let clips: Int
    let thisWeek: Int
    let allowance: Allowance

    static func make(clips: [ClipRecord], quota: QuotaStatus, now: Date = .now, calendar: Calendar = .current) -> ProfileStats {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let allowance: Allowance = switch quota {
        case .signedIn: .unlimited
        case .guestFree(let left): .remaining(left)
        case .guestUsedUp: .remaining(0)
        }
        return ProfileStats(
            clips: clips.count,
            thisWeek: week.map { week in clips.filter { week.contains($0.createdAt) }.count } ?? 0,
            allowance: allowance
        )
    }
}
