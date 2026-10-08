import Foundation

protocol PlayerCaching: Sendable {
    func loadPlayers() throws -> [Player]
    func savePlayers(_ players: [Player]) throws
}

struct DiskPlayerCache: PlayerCaching {
    let fileURL: URL
    private let maxAge: TimeInterval?

    /// Pass `nil` for maxAge to disable expiration (permanent cache).
    init(fileManager: FileManager = .default, maxAge: TimeInterval? = 48 * 60 * 60) {
        let directory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileURL = directory.appending(path: "players-cache.json")
        self.maxAge = maxAge
    }

    init(fileURL: URL, maxAge: TimeInterval? = 48 * 60 * 60) {
        self.fileURL = fileURL
        self.maxAge = maxAge
    }

    func loadPlayers() throws -> [Player] {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let maxAge = maxAge,
           let modified = attributes[.modificationDate] as? Date,
           Date().timeIntervalSince(modified) > maxAge {
            throw URLError(.resourceUnavailable)
        }
        return try loadPlayersIgnoringAge()
    }

    func loadPlayersIgnoringAge() throws -> [Player] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.statScout.decode([Player].self, from: data)
    }

    func savePlayers(_ players: [Player]) throws {
        let data = try JSONEncoder.statScout.encode(players)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Binary-plist-backed cache for the heavyweight historical dataset.
/// Plist decode is ~2-3× faster than JSON on the same payload, and the file is ~30% smaller.
struct PlistPlayerCache: PlayerCaching {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadPlayers() throws -> [Player] {
        let data = try Data(contentsOf: fileURL)
        return try PropertyListDecoder.statScout.decode([Player].self, from: data)
    }

    func savePlayers(_ players: [Player]) throws {
        let data = try PropertyListEncoder.statScout.encode(players)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: [.atomic])
    }
}

/// Proof that the current-season snapshot on disk came from the server, written
/// beside it whenever this build saves one.
///
/// Builds through 1.2.1 wrote server responses and a bundled four-team opening
/// week export to the same `players-current.json`, with nothing in the file to
/// tell them apart - and the opening-week validator accepts both, by design, so
/// it can never be the thing that separates them. Without a marker the only
/// honest reading of that file is "unknown origin".
struct CurrentSnapshotProvenance: Codable {
    /// Bump when what the snapshot file means changes.
    static let currentSchema = 1
    var schema: Int = currentSchema
    var savedAt: Date
}

/// Two-tier cache: permanent for historical data, expiring for current season.
struct TwoTierPlayerCache: PlayerCaching {
    private let historical: PlistPlayerCache
    private let legacyHistorical: DiskPlayerCache
    private let current: DiskPlayerCache
    private let currentProvenanceURL: URL
    private let bundle: Bundle
    private let historicalBundleResourceName: String

    init(
        fileManager: FileManager = .default,
        directory: URL? = nil,
        bundle: Bundle = .main,
        historicalBundleResourceName: String = "players-historical"
    ) {
        let directory = directory
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        self.historical = PlistPlayerCache(fileURL: directory.appending(path: "players-historical.plist"))
        self.legacyHistorical = DiskPlayerCache(fileURL: directory.appending(path: "players-historical.json"), maxAge: nil)
        self.current = DiskPlayerCache(fileURL: directory.appending(path: "players-current.json"), maxAge: nil)
        self.currentProvenanceURL = directory.appending(path: "players-current-provenance.json")
        self.bundle = bundle
        self.historicalBundleResourceName = historicalBundleResourceName
    }

    func loadPlayers() throws -> [Player] {
        let historicalPlayers = loadHistoricalPlayers()
        let currentPlayers = (try? loadCurrentPlayers()) ?? []
        return historicalPlayers + currentPlayers
    }

    /// The last snapshot this device accepted from the server, whatever its age.
    ///
    /// Only server data is ever returned. Builds used to fall back to a bundled
    /// current-season snapshot once this file passed 48 hours, and re-save it as
    /// fresh, so a fan returning in Week 6 saw the four-team Week 1 export as the
    /// live leaderboard. An old saved snapshot is still the user's newest real
    /// data, and the freshness caption restored beside it says how old it is.
    func loadCurrentPlayers() throws -> [Player] {
        // An unprovenanced file predates the marker, so it is either a real
        // server snapshot saved by 1.2.x or the bundled four-team opening-week
        // export that 1.2 wrote to this same path after a failed refresh. It
        // cannot be both, and nothing in it says which - so it is discarded
        // once, on the first launch after upgrading, rather than kept and
        // presented as the live league. The cost is one refresh; the next save
        // writes the marker and this never happens again. See
        // `CurrentSnapshotProvenance`.
        guard hasServerProvenance else {
            discardCurrentSnapshot()
            return []
        }
        guard let cached = try? current.loadPlayersIgnoringAge(),
              PlayerSnapshotValidator.isCompleteCurrent(cached) else {
            return []
        }
        return cached
    }

    private var hasServerProvenance: Bool {
        guard let data = try? Data(contentsOf: currentProvenanceURL),
              let marker = try? JSONDecoder.statScout.decode(CurrentSnapshotProvenance.self, from: data)
        else { return false }
        return marker.schema == CurrentSnapshotProvenance.currentSchema
    }

    private func discardCurrentSnapshot() {
        try? FileManager.default.removeItem(at: current.fileURL)
        try? FileManager.default.removeItem(at: currentProvenanceURL)
    }

    private func writeCurrentProvenance() {
        guard let data = try? JSONEncoder.statScout.encode(CurrentSnapshotProvenance(savedAt: Date())) else { return }
        try? FileManager.default.createDirectory(
            at: currentProvenanceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: currentProvenanceURL, options: [.atomic])
    }

    /// The historical tier, never including the live season.
    ///
    /// The bundled archive is regenerated *ahead* of a season rollover, so a
    /// shipped build can carry the season that is still live when it installs.
    /// Those rows are a frozen mid-season snapshot, and `loadHistoricalIfNeeded`
    /// merges history over whatever is already loaded, so left in they would
    /// overwrite the live feed with stale numbers the moment someone opened a
    /// past season. Filtered on read rather than stripped from the archive: the
    /// rows are wanted, just not yet, and they become the newest historical
    /// season by themselves once the calendar rolls over. The career rollup
    /// sits under season 0 and so is always kept.
    func loadHistoricalPlayers() -> [Player] {
        loadHistoricalCandidates().filter { ($0.season ?? 0) < StatScoutSeason.current }
    }

    private func loadHistoricalCandidates() -> [Player] {
        let bundled = loadBundledPlayers(named: historicalBundleResourceName)
        let bundledIsComplete = bundled.map(PlayerSnapshotValidator.isCompleteHistorical) ?? false

        // 1. Permanent disk cache, unless the bundled archive has broader coverage.
        if let cached = try? historical.loadPlayers(), !cached.isEmpty {
            if PlayerSnapshotValidator.isCompleteHistorical(cached) || !bundledIsComplete {
                return cached
            }
        }
        // 2. Bundled binary plist (shipped with the app).
        if let bundled, bundledIsComplete {
            try? historical.savePlayers(bundled)
            try? FileManager.default.removeItem(at: legacyHistorical.fileURL)
            return bundled
        }
        // 3. Legacy on-disk JSON cache from older builds - migrate forward.
        if let players = try? legacyHistorical.loadPlayers(), !players.isEmpty {
            try? historical.savePlayers(players)
            try? FileManager.default.removeItem(at: legacyHistorical.fileURL)
            return players
        }
        // 4. Bundled JSON fallback (in case the plist asset is ever missing).
        if let players = loadBundledPlayers(named: historicalBundleResourceName, extension: "json"), !players.isEmpty {
            try? historical.savePlayers(players)
            return players
        }
        return []
    }

    private func loadBundledPlayers(named name: String, extension fileExtension: String = "plist") -> [Player]? {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        if fileExtension == "plist" {
            return try? PropertyListDecoder.statScout.decode([Player].self, from: data)
        }
        return try? JSONDecoder.statScout.decode([Player].self, from: data)
    }

    func savePlayers(_ players: [Player]) throws {
        let historicalPlayers = players.filter { ($0.season ?? 0) < StatScoutSeason.current }
        let currentPlayers = players.filter { ($0.season ?? 0) >= StatScoutSeason.current }
        if !historicalPlayers.isEmpty {
            try historical.savePlayers(historicalPlayers)
        }
        if !currentPlayers.isEmpty, PlayerSnapshotValidator.isCompleteCurrent(currentPlayers) {
            try current.savePlayers(currentPlayers)
            // Only after the rows are safely down, so a failed write never
            // leaves a marker vouching for a file that isn't there.
            writeCurrentProvenance()
        }
    }
}

enum PlayerSnapshotValidator {
    private static let minimumTeamCount = 30
    private static let requiredTypes: Set<String> = ["qb", "rb", "wr", "te", "def"]

    static func isCompleteHistorical(_ players: [Player]) -> Bool {
        let expectedSeasons = Set(StatScoutSeason.earliest..<StatScoutSeason.current)
        let grouped = Dictionary(grouping: players.filter {
            guard let season = $0.season else { return false }
            return expectedSeasons.contains(season)
                && $0.seasonPhase == .regular
        }, by: { $0.season! })

        guard Set(grouped.keys) == expectedSeasons else { return false }
        return grouped.values.allSatisfy { seasonPlayers in
            let teams = Set(seasonPlayers.map { normalizedTeamAbbreviation($0.team) })
            let types = Set(seasonPlayers.compactMap(\.playerType).map { $0.lowercased() })
            return teams.count >= minimumTeamCount
                && requiredTypes.isSubset(of: types)
                && seasonPlayers.allSatisfy { !$0.metrics.isEmpty }
        }
    }

    static func isCompleteCurrent(_ players: [Player]) -> Bool {
        let current = players.filter {
            $0.season == StatScoutSeason.current
                && $0.seasonPhase == .regular
        }
        let teams = Set(current.map { normalizedTeamAbbreviation($0.team) })
        let types = Set(current.compactMap(\.playerType).map { $0.lowercased() })
        let metricLabels = Set(current.flatMap(\.metrics).map(\.label))
        let requiredMetrics: Set<String> = ["EPA/Play", "EPA/Rush", "EPA/Tgt"]
        // The first published game has two teams. A 30-team requirement kept
        // valid opening-week data out of the cache until most of the NFL played.
        // The publisher checks game coverage and regression before promotion.
        return teams.count >= 2
            && current.count >= 20
            && requiredTypes.isSubset(of: types)
            && requiredMetrics.isSubset(of: metricLabels)
    }
}

extension JSONEncoder {
    static var statScout: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension PropertyListEncoder {
    static var statScout: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }
}

extension PropertyListDecoder {
    /// Conversion script stores dates as native plist Date values, so default decoding works.
    static var statScout: PropertyListDecoder { PropertyListDecoder() }
}
