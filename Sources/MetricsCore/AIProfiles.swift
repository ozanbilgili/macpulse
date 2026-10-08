import Foundation
import CryptoKit

extension AIUsage {
    public struct AccountProfile: Sendable, Equatable {
        public let email: String
        public let subscriptionAnchor: Date?

        public init(email: String, subscriptionAnchor: Date?) {
            self.email = email
            self.subscriptionAnchor = subscriptionAnchor
        }
    }

    public static func parseProfile(_ data: Data) -> AccountProfile? {
        guard data.count <= 256 << 10,
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let account = object["account"] as? [String: Any],
              let raw = account["email"] as? String else { return nil }
        let email = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard email.count <= 320, parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
              !email.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        let organization = object["organization"] as? [String: Any]
        return AccountProfile(email: email, subscriptionAnchor: parseDate(organization?["subscription_created_at"]))
    }

    struct ProfileResponse: Sendable {
        var profile: AccountProfile?
        var retrySeconds: TimeInterval = 300
    }

    /// Memory only. A changed credential discards the former identity immediately;
    /// neither email, token nor profile response is written to a cache file.
    actor ProfileCache {
        private struct Entry {
            let identity: SHA256.Digest
            var profile: AccountProfile?
            var fetchedAt: Date = .distantPast
            var retryAt: Date = .distantPast
            var pending: Task<ProfileResponse, Never>?
        }
        private var entries: [String: Entry] = [:]

        func resolve(source: String, credential: String, now: Date, allowsFetch: Bool,
                     fetch: @escaping @Sendable () async -> ProfileResponse) async -> AccountProfile? {
            let identity = SHA256.hash(data: Data(credential.utf8))
            if entries[source]?.identity != identity {
                entries[source]?.pending?.cancel()
                entries[source] = Entry(identity: identity)
            }
            guard var entry = entries[source] else { return nil }
            guard allowsFetch else { return entry.profile }
            if let profile = entry.profile, now.timeIntervalSince(entry.fetchedAt) < 3600 { return profile }
            guard now >= entry.retryAt else { return entry.profile }
            let job = entry.pending ?? Task { await fetch() }
            entry.pending = job
            entries[source] = entry
            let response = await job.value
            guard var current = entries[source], current.identity == identity else { return nil }
            current.pending = nil
            if let profile = response.profile {
                current.profile = profile
                current.fetchedAt = now
                current.retryAt = .distantPast
            } else {
                current.retryAt = now.addingTimeInterval(max(300, response.retrySeconds))
            }
            entries[source] = current
            return current.profile
        }
    }

    private static let profiles = ProfileCache()

    static func accountProfile(_ account: Account, credentials: Credentials?, fetch: Bool, now: Date) async -> AccountProfile? {
        guard account.provider == .claude, let credentials else { return nil }
        return await profiles.resolve(source: account.service, credential: credentials.token, now: now,
                                      allowsFetch: fetch && credentials.isValid(at: now)) {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/profile")!, timeoutInterval: 8)
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
            request.setValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await Cfg.session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return ProfileResponse() }
                if http.statusCode == 200, !Task.isCancelled { return ProfileResponse(profile: parseProfile(data)) }
                let retry = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init) ?? 300
                return ProfileResponse(retrySeconds: retry.isFinite ? retry : 300)
            } catch { return ProfileResponse() }
        }
    }
}
