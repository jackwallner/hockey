import Foundation

extension StringProtocol {
    /// Case- and accent-blind search, so "stutzle" finds "Stützle" and
    /// "lafreniere" finds "Lafrenière".
    func searchMatches<T: StringProtocol>(_ query: T) -> Bool {
        range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
