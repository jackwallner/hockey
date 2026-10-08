import Foundation

/// Returns true when a fetch ended only because its Swift task was superseded.
/// URLSession reports task cancellation as `URLError.cancelled`.
func isTaskCancellation(_ error: Error) -> Bool {
    if error is CancellationError { return true }
    if let urlError = error as? URLError, urlError.code == .cancelled { return true }
    return false
}

protocol StatcastProviding: Sendable {
    func fetchPlayers() async throws -> [Player]
    func fetchHistoricalPlayers() async throws -> [Player]
    func fetchCurrentPlayers() async throws -> [Player]
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog]
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog]
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm]
    func fetchDataCoverage(season: Int) async throws -> DataCoverage?
    func fetchDataFreshness(season: Int) async throws -> DataFreshness?
    func fetchGames(season: Int) async throws -> [Game]
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog]
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String>
    func fetchGameDetail(gameId: String) async throws -> GameDetail?
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile]
    func fetchTeamRatings(season: Int) async throws -> [TeamRating]
    func fetchGameProjections(season: Int) async throws -> [GameProjection]
}

extension StatcastProviding {
    /// Older test and preview providers do not need to know about the optional
    /// status endpoint. A missing implementation is treated as unavailable.
    func fetchDataFreshness(season: Int) async throws -> DataFreshness? { nil }
    func fetchGames(season: Int) async throws -> [Game] { [] }
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] { [] }
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> { [] }
    func fetchGameDetail(gameId: String) async throws -> GameDetail? { nil }
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] { [] }
    func fetchTeamRatings(season: Int) async throws -> [TeamRating] { [] }
    func fetchGameProjections(season: Int) async throws -> [GameProjection] { [] }
}

struct StatcastAPI: StatcastProviding {
    private let baseURL: URL
    private let apiKey: String

    init(baseURL: URL, apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }

    func fetchPlayers() async throws -> [Player] {
        let historical = try await fetchHistoricalPlayers()
        let current = try await fetchCurrentPlayers()
        return historical + current
    }

    /// Everything older than the live season, plus the career rollup.
    ///
    /// The rollup is stored under `season = 0`, which is *below* `earliest`, so
    /// a plain `season.gte.2000` range quietly excluded it and All Time came
    /// back empty. Hence the `or`: the sentinel row or the real historical
    /// range. It still sorts into the historical cache partition, since 0 is
    /// less than the current season.
    func fetchHistoricalPlayers() async throws -> [Player] {
        try await fetchPlayers(queryItems: [
            URLQueryItem(
                name: "or",
                value: "(season.eq.\(StatScoutSeason.allTime),"
                    + "and(season.gte.\(StatScoutSeason.earliest),"
                    + "season.lt.\(StatScoutSeason.current)))"
            ),
        ])
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        try await fetchPlayers(queryItems: [
            URLQueryItem(name: "season", value: "eq.\(StatScoutSeason.current)"),
        ])
    }

    /// One player's games, filtered to a single season *and phase*.
    ///
    /// The phase filter is not cosmetic. Playoff games are the newest rows a
    /// season has, so without it a date-descending "last five games" for a club
    /// that reached January was mostly playoff football no matter which phase the
    /// user had selected - and a Playoffs board, which has at most four games to
    /// work with, quietly topped itself up with December.
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        let endpoint = baseURL
            .appending(path: "rest/v1/player_game_logs")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "player_id", value: "eq.\(playerId)"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
                URLQueryItem(name: "order", value: "game_date.desc"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }

        let rows = try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data)
        return rows.compactMap(\.value)
    }

    /// A whole roster's games since `sinceDate`, filtered to one phase. Same
    /// reasoning as `fetchGameLogs`.
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/New_York")
        let sinceString = formatter.string(from: sinceDate)

        var all: [PlayerGameLog] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_game_logs")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "team", value: "eq.\(team)"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
                    URLQueryItem(name: "game_date", value: "gte.\(sinceString)"),
                    URLQueryItem(name: "order", value: "game_date.desc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data)
            let page = rows.compactMap(\.value)
            all.append(contentsOf: page)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// The whole league's rolling window for one window length, in one paged
    /// fetch. The board ranks by delta, so it needs every qualifying player at
    /// once; there is no useful partial sort.
    ///
    /// Cache-bypassing for the same reason the game-log fetches are: the
    /// nightly rewrites these rows in place, and a stale window is worse than a
    /// slow one. The element decoder is lossy so a single malformed row can't
    /// empty the board.
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        var all: [RecentForm] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let endpoint = baseURL
                .appending(path: "rest/v1/player_recent_form")
                .appending(queryItems: [
                    URLQueryItem(name: "select", value: "*"),
                    URLQueryItem(name: "season", value: "eq.\(season)"),
                    URLQueryItem(name: "season_type", value: "eq.\(seasonPhase.rawValue)"),
                    URLQueryItem(name: "window_weeks", value: "eq.\(windowWeeks)"),
                    URLQueryItem(name: "order", value: "player_id.asc"),
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset)),
                ])
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<RecentForm>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }

    /// One row, read for its coverage columns only.
    ///
    /// Ordered by `end_week` before `as_of` because the week is the answer the
    /// UI wants and a playoff row carries a higher week than any regular-season
    /// one, so the newest row is also the furthest through the season. `as_of`
    /// breaks the tie for the seasons ingested before the week columns existed,
    /// where `end_week` is null throughout.
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? {
        let endpoint = baseURL
            .appending(path: "rest/v1/player_recent_form")
            .appending(queryItems: [
                URLQueryItem(name: "select", value: "as_of,end_week,season_type"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "as_of", value: "not.is.null"),
                URLQueryItem(
                    name: "order",
                    value: "end_week.desc.nullslast,as_of.desc"
                ),
                URLQueryItem(name: "limit", value: "1"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }

        struct Row: Decodable {
            let as_of: String?
            let end_week: Int?
            let season_type: String?
        }
        guard let row = try JSONDecoder().decode([Row].self, from: data).first,
              let raw = row.as_of else { return nil }

        // `as_of` is a Postgres `date`: "YYYY-MM-DD", not ISO8601. Same parse
        // RecentForm does, anchored to Eastern so a west-coast Sunday night
        // game doesn't roll the label onto Monday.
        let bits = raw.split(separator: "-").compactMap { Int($0) }
        guard bits.count == 3 else { return nil }
        var parts = DateComponents()
        parts.year = bits[0]
        parts.month = bits[1]
        parts.day = bits[2]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        guard let date = calendar.date(from: parts) else { return nil }

        return DataCoverage(
            asOf: date,
            week: row.end_week,
            phase: row.season_type.flatMap(SeasonPhase.init(rawValue:)) ?? .regular
        )
    }

    /// Reads the active, validated publisher revision. The backend exposes one
    /// current row through `data_refresh_status`; a missing table is harmless so
    /// app versions can roll out before the status migration reaches production.
    func fetchDataFreshness(season: Int) async throws -> DataFreshness? {
        let endpoint = baseURL
            .appending(path: "rest/v1/data_refresh_status")
            .appending(queryItems: [
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "published_at.desc.nullslast,last_checked_at.desc"),
                URLQueryItem(name: "limit", value: "1"),
            ])
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        // A status endpoint is optional during rollout. Do not turn its absence
        // into a player-data error or block the last known-good dataset.
        if httpResponse.statusCode == 404 { return nil }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder.statScout.decode([DataFreshness].self, from: data).first
    }

    /// The whole season's schedule in one request, about 285 rows.
    func fetchGames(season: Int) async throws -> [Game] {
        let data = try await get("games", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "kickoff_at.asc,game_id.asc"),
            URLQueryItem(name: "limit", value: "400"),
        ])
        return try JSONDecoder.statScout.decode([Lenient<Game>].self, from: data).compactMap(\.value)
    }

    /// Every player's line from one game, for its box score.
    func fetchGameLogs(gameId: String) async throws -> [PlayerGameLog] {
        let data = try await get("player_game_logs", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "game_id", value: "eq.\(gameId)"),
            URLQueryItem(name: "limit", value: "200"),
        ])
        return try JSONDecoder.statScout.decode([Lenient<PlayerGameLog>].self, from: data).compactMap(\.value)
    }

    /// Which games have player stats published. Every game has a passer, so
    /// quarterback rows alone answer it at a fraction of the payload.
    func fetchGameIdsWithStats(season: Int) async throws -> Set<String> {
        struct Row: Decodable { let game_id: String? }
        let data = try await get("player_game_logs", [
            URLQueryItem(name: "select", value: "game_id"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "player_type", value: "eq.qb"),
            URLQueryItem(name: "limit", value: "2000"),
        ])
        return Set(try JSONDecoder().decode([Row].self, from: data).compactMap(\.game_id))
    }

    /// The play-by-play breakdown for one game, or nil before it is built.
    func fetchGameDetail(gameId: String) async throws -> GameDetail? {
        let data = try await get("game_details", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "game_id", value: "eq.\(gameId)"),
            URLQueryItem(name: "limit", value: "1"),
        ])
        return try JSONDecoder.statScout.decode([GameDetail].self, from: data).first
    }

    /// Bio, contract, snaps and injury for every player the live season ships,
    /// about 1,100 rows. Optional context: a missing table (a build newer than
    /// the backend) reads as no profiles, never as a player-data error.
    func fetchPlayerProfiles(season: Int) async throws -> [PlayerProfile] {
        var all: [PlayerProfile] = []
        let pageSize = 1000
        var offset = 0
        while true {
            guard let data = try await getOptional("player_profiles", [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "season", value: "eq.\(season)"),
                URLQueryItem(name: "order", value: "player_id.asc"),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ]) else { return [] }
            let rows = try JSONDecoder.statScout.decode([Lenient<PlayerProfile>].self, from: data)
            all.append(contentsOf: rows.compactMap(\.value))
            if rows.count < pageSize { return all }
            offset += pageSize
        }
    }

    func fetchTeamRatings(season: Int) async throws -> [TeamRating] {
        guard let data = try await getOptional("team_ratings", [
            URLQueryItem(name: "select", value: "*"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "order", value: "rank.asc"),
        ]) else { return [] }
        return try JSONDecoder.statScout.decode([Lenient<TeamRating>].self, from: data).compactMap(\.value)
    }

    func fetchGameProjections(season: Int) async throws -> [GameProjection] {
        guard let data = try await getOptional("game_projections", [
            URLQueryItem(name: "select", value: "game_id,home_margin,home_win_prob"),
            URLQueryItem(name: "season", value: "eq.\(season)"),
            URLQueryItem(name: "limit", value: "400"),
        ]) else { return [] }
        return try JSONDecoder.statScout.decode([Lenient<GameProjection>].self, from: data).compactMap(\.value)
    }

    /// `get`, except a missing table (404) is nil rather than an error.
    private func getOptional(_ table: String, _ queryItems: [URLQueryItem]) async throws -> Data? {
        let endpoint = baseURL
            .appending(path: "rest/v1/\(table)")
            .appending(queryItems: queryItems)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        if httpResponse.statusCode == 404 { return nil }
        guard 200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func get(_ table: String, _ queryItems: [URLQueryItem]) async throws -> Data {
        let endpoint = baseURL
            .appending(path: "rest/v1/\(table)")
            .appending(queryItems: queryItems)
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func fetchPlayers(queryItems filters: [URLQueryItem]) async throws -> [Player] {
        var all: [Player] = []
        let pageSize = 1000
        var offset = 0
        while true {
            let queryItems = [
                URLQueryItem(name: "select", value: "*"),
                // Stable key so offset paging can't skip/duplicate rows when
                // updated_at changes mid-fetch.
                URLQueryItem(
                    name: "order",
                    value: "season.asc,season_type.asc,id.asc"
                ),
                URLQueryItem(name: "limit", value: String(pageSize)),
                URLQueryItem(name: "offset", value: String(offset)),
            ] + filters
            let endpoint = baseURL
                .appending(path: "rest/v1/player_snapshots")
                .appending(queryItems: queryItems)
            // Bypass URLCache so the shared headshot cache can't serve a stale page.
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue(apiKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode || httpResponse.statusCode == 206 else {
                throw URLError(.badServerResponse)
            }

            let rows = try JSONDecoder.statScout.decode([Lenient<Player>].self, from: data)
            let page = rows.compactMap(\.value)
            // A non-empty page that decodes to zero players means the schema
            // changed under us - surface it instead of silently going blank.
            if !rows.isEmpty && page.isEmpty {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: [], debugDescription: "All player rows failed to decode")
                )
            }
            all.append(contentsOf: page)
            if rows.count < pageSize { break }
            offset += pageSize
        }
        return all
    }
}

/// Decodes an element if possible, otherwise yields nil instead of throwing,
/// so one malformed row cannot fail the entire page.
private struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}

struct OfflineStatcastAPI: StatcastProviding {
    func fetchPlayers() async throws -> [Player] { [] }
    func fetchHistoricalPlayers() async throws -> [Player] { [] }
    func fetchCurrentPlayers() async throws -> [Player] { [] }
    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] { [] }
    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] { [] }
    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] { [] }
    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}

#if DEBUG
struct PreviewStatcastAPI: StatcastProviding {
    func fetchPlayers() async throws -> [Player] {
        SampleData.players
    }

    func fetchHistoricalPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) < StatScoutSeason.current }
    }

    func fetchCurrentPlayers() async throws -> [Player] {
        SampleData.players.filter { ($0.season ?? 0) >= StatScoutSeason.current }
    }

    func fetchGameLogs(
        playerId: Int,
        season: Int,
        seasonPhase: SeasonPhase
    ) async throws -> [PlayerGameLog] {
        []
    }

    func fetchTeamGameLogs(
        team: String,
        season: Int,
        seasonPhase: SeasonPhase,
        sinceDate: Date
    ) async throws -> [PlayerGameLog] {
        []
    }

    func fetchRecentForm(
        season: Int,
        seasonPhase: SeasonPhase,
        windowWeeks: Int
    ) async throws -> [RecentForm] {
        []
    }

    func fetchDataCoverage(season: Int) async throws -> DataCoverage? { nil }
}
#endif

extension JSONDecoder {
    static var statScout: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                return date
            }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: dateString) {
                return date
            }

            // Postgres/PostgREST emits variable-length fractional seconds
            // (e.g. "…40.95411+00:00"). ISO8601DateFormatter's
            // .withFractionalSeconds only accepts exactly 3 fractional digits
            // on some iOS versions, and the plain formatter rejects any
            // fractional part at all - so a 5-digit fraction fails BOTH above
            // and every row's required updated_at drops, surfacing as a bogus
            // "Data format changed" error. Strip the fraction and retry.
            if let dotRange = dateString.range(of: #"\.\d+"#, options: .regularExpression) {
                var stripped = dateString
                stripped.removeSubrange(dotRange)
                if let date = fallback.date(from: stripped) {
                    return date
                }
            }

            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(dateString)")
        }
        return decoder
    }
}
