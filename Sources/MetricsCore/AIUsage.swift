import Foundation
import CryptoKit

/// Usage app source adapter and matching pace/token math. Credentials are read-only;
/// only usage responses and local numeric token indexes may be written.
public enum AIUsage {
    private final class RedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    private static func boundedData(path: String, maxBytes: Int = 16 << 20) -> Data? {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber,
              size.intValue >= 0, size.intValue <= maxBytes else { return nil }
        return FileManager.default.contents(atPath: path)
    }


    // MARK: - Modeller

    public enum Provider: Sendable { case claude, codex }

    public struct Account: Sendable {
        public let n: Int
        public let dir: String
        public let config: String
        public let service: String
        public var provider: Provider = .claude

        /// Menü çubuğu ve rozet etiketi: Claude'da hesap numarası, Codex'te "C".
        public var badge: String { provider == .codex ? "C" : "\(n)" }
        /// `usage-<key>.json`: Claude `usage-1.json`, Codex `usage-codex.json`.
        public var cacheKey: String { provider == .codex ? "codex" : "\(n)" }

        public init(n: Int, dir: String, config: String, service: String, provider: Provider = .claude) { self.n = n; self.dir = dir; self.config = config; self.service = service; self.provider = provider }

    }

    public struct Window: Sendable {
        public var pct: Int
        public var resetsAt: Date?
        public var known = true

        /// Sıfırlanması geçen pencere yeni okuma gelene kadar bilinmeyendir.
        public func effective(at now: Date) -> Window {
            if let r = resetsAt, r <= now { return Window(pct: 0, resetsAt: nil, known: false) }
            return self
        }

        public init(pct: Int, resetsAt: Date?, known: Bool = true) { self.pct = pct; self.resetsAt = resetsAt; self.known = known }

    }

    public struct Usage: Sendable {
        public var five: Window
        public var week: Window
        public var fetchedAt: Date   // cache dosyasının mtime'ı
        /// Codex planında bu pencere hiç yok (ör. Pro Lite yalnız haftalık); satırı gösterme.
        public var hasFive = true
        public var hasWeek = true
        public func statusFive(now: Date) -> PaceStatus {
            let w = five.effective(at: now)
            return AIUsage.paceStatus(pct: w.pct, resetsAt: w.resetsAt, length: AIUsage.Cfg.fiveLength, now: now)
        }
        public func statusWeek(now: Date) -> PaceStatus {
            let w = week.effective(at: now)
            return AIUsage.paceStatus(pct: w.pct, resetsAt: w.resetsAt, length: AIUsage.Cfg.weekLength, now: now)
        }
        public func paceFive(now: Date) -> Pace? { if case .projected(let p, _) = statusFive(now: now) { return p }; return nil }
        public func paceWeek(now: Date) -> Pace? { if case .projected(let p, _) = statusWeek(now: now) { return p }; return nil }

        public func meterFive(now: Date) -> MeterState { AIUsage.meterState(pct: five.effective(at: now).pct, status: statusFive(now: now)) }
        public func meterWeek(now: Date) -> MeterState { AIUsage.meterState(pct: week.effective(at: now).pct, status: statusWeek(now: now)) }


        public init(five: Window, week: Window, fetchedAt: Date, hasFive: Bool = true, hasWeek: Bool = true) { self.five = five; self.week = week; self.fetchedAt = fetchedAt; self.hasFive = hasFive; self.hasWeek = hasWeek }

    }

    public struct AccountState: Sendable {
        public let account: Account
        public var email: String
        public var label: String
        public var plan: String
        public var loggedIn: Bool
        public var tokenExpired: Bool
        public var usage: Usage?
        public var blockedUntil: Date?
        public var subscriptionAnchor: Date?

        public var compactLabel: String {
            let parts = email.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "@", omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty, let initial = parts[1].first else { return label }
            return "\(parts[0])@\(String(initial).lowercased())"
        }

        public init(account: Account, email: String, label: String, plan: String, loggedIn: Bool, tokenExpired: Bool, usage: Usage?, blockedUntil: Date?, subscriptionAnchor: Date? = nil) { self.account = account; self.email = email; self.label = label; self.plan = plan; self.loggedIn = loggedIn; self.tokenExpired = tokenExpired; self.usage = usage; self.blockedUntil = blockedUntil; self.subscriptionAnchor = subscriptionAnchor }

    }

    /// Token yalnızca Authorization başlığına konur; hiçbir yere yazdırılmaz.
    public struct Credentials: CustomStringConvertible, Sendable {
        public let token: String
        public let expiresAt: Date?
        public let plan: String
        public var accountId: String?   // Codex: ChatGPT-Account-Id başlığı
        public var description: String { "Credentials(<redacted>)" }
        public func isValid(at now: Date) -> Bool {
            guard let e = expiresAt else { return false }
            return e.timeIntervalSince(now) > 30
        }

        public init(token: String, expiresAt: Date?, plan: String, accountId: String? = nil) { self.token = token; self.expiresAt = expiresAt; self.plan = plan; self.accountId = accountId }

    }

    public enum Level: Sendable { case red, yellow, orange, green }

    // MARK: - Sabitler

    public enum Cfg {
        public static let home = NSHomeDirectory()
        public static let cacheDir = home + "/.cache/claude-hesaplar"
        /// Kullanıcının verdiği hesap adları `{"1": "İş", ...}`; statusline.sh ve claude-pick de okur.
        public static let namesPath = home + "/.config/claude-hesaplar/names.json"
        public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
        public static let staleSeconds: TimeInterval = 300
        public static let retrySeconds: TimeInterval = 300
        static let session = URLSession(configuration: {
                let c = URLSessionConfiguration.ephemeral
                c.timeoutIntervalForRequest = 8; c.timeoutIntervalForResource = 12
                c.httpCookieAcceptPolicy = .never
                return c
            }(), delegate: RedirectPolicy(), delegateQueue: nil)
        public static let fiveLength: TimeInterval = 5 * 3600
        public static let weekLength: TimeInterval = 7 * 86400
        public static let baseService = "Claude Code-credentials"
        public static let codexUsageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
        public static let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 } ?? home + "/.codex"
        public static let openRouterCreditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
        /// Anahtarın keychain servisi (genel parola kaydı); ve `usage-<creditKey>.json` cache anahtarı.
        public static let openRouterService = "openrouter-jev-api-key"
        public static let creditKey = "openrouter"
    }

    // MARK: - Hesap keşfi

    public static func discoverAccounts() -> [Account] {
        var found = [Account(n: 1, dir: Cfg.home + "/.claude", config: Cfg.home + "/.claude.json",
                             service: Cfg.baseService)]
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Cfg.home)) ?? []
        for name in names {
            guard name.hasPrefix(".claude-hesap"),
                  let n = Int(name.dropFirst(".claude-hesap".count)), n >= 2,
                  name.dropFirst(".claude-hesap".count).allSatisfy({ $0.isASCII && $0.isNumber })
            else { continue }
            let path = Cfg.home + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let norm = path.precomposedStringWithCanonicalMapping
            let digest = SHA256.hash(data: Data(norm.utf8)).map { String(format: "%02x", $0) }.joined().prefix(8)
            found.append(Account(n: n, dir: path, config: path + "/.claude.json",
                                 service: "\(Cfg.baseService)-\(digest)"))
        }
        found.sort { $0.n < $1.n }
        // Codex (ChatGPT girişi) en sonda; auth.json yoksa kart da yok.
        let codexAuth = Cfg.codexHome + "/auth.json"
        if FileManager.default.fileExists(atPath: codexAuth) {
            found.append(Account(n: 0, dir: Cfg.codexHome, config: codexAuth, service: "", provider: .codex))
        }
        return found
    }

    public static func readEmail(_ configPath: String) -> String {
        guard let d = boundedData(path: configPath),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let oa = obj["oauthAccount"] as? [String: Any],
              let email = oa["emailAddress"] as? String else { return "" }
        return email
    }

    /// Ad dosyası yoksa/bozuksa boş; yalnız boş olmayan metin adlar.
    public static func loadNames(path: String = Cfg.namesPath) -> [Int: String] {
        guard let d = boundedData(path: path),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return [:] }
        var out: [Int: String] = [:]
        for (k, v) in obj {
            if let n = Int(k), let name = (v as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { out[n] = name }
        }
        return out
    }

    /// Boş ad kaydı siler (varsayılan "Hesap N" döner). En fazla 24 karakter.
    public static func saveName(_ n: Int, _ name: String, path: String = Cfg.namesPath) {
        var names = loadNames(path: path)
        let clean = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        names[n] = clean.isEmpty ? nil : clean
        let obj = Dictionary(uniqueKeysWithValues: names.map { (String($0.key), $0.value) })
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys, .prettyPrinted]) else { return }
        writeAtomic(data, to: path)
    }

    /// Kullanıcı adı ya da "Hesap N"; e-postanın alan adı (şirket adı) asla gösterilmez.
    public static func accountLabel(_ n: Int, names: [Int: String]) -> String { names[n] ?? String(localized: "Account \(String(n))") }

    // MARK: - Keychain (yalnızca security CLI, yalnızca okuma)

    /// Gizli değer yalnız çağırana döner; yazdırılmaz, loglanmaz. `account` nil ise hesap adına bakılmaz.
    private static func keychainSecret(service: String, account: String?) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password"] + (account.map { ["-a", $0] } ?? []) + ["-s", service, "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let timeout = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timeout.schedule(deadline: .now() + 8)
        timeout.setEventHandler { if p.isRunning { p.terminate() } }
        timeout.resume()
        defer { timeout.cancel() }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 && data.count <= 1 << 20 ? data : nil
    }

    public static func readCredentials(service: String) -> Credentials? {
        guard let data = keychainSecret(service: service, account: NSUserName()),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = obj["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        var exp: Date?
        if let ms = (oauth["expiresAt"] as? NSNumber)?.doubleValue { exp = Date(timeIntervalSince1970: ms / 1000) }
        return Credentials(token: token, expiresAt: exp, plan: planName(oauth))
    }

    /// Hesap türüne göre salt-okunur kimlik bilgisi.
    public static func readCredentials(_ a: Account) -> Credentials? {
        a.provider == .codex ? readCodexCredentials(path: a.config) : readCredentials(service: a.service)
    }

    // MARK: - Codex (~/.codex/auth.json, yalnızca okuma; token'ı Codex kendisi yeniler)

    /// JWT gövdesini çözer (imza doğrulanmaz; yalnız `exp`, plan ve e-posta okunur).
    public static func jwtClaims(_ jwt: String) -> [String: Any]? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        b64 += String(repeating: "=", count: (4 - b64.count % 4) % 4)
        guard let d = Data(base64Encoded: b64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func codexTokens(path: String) -> [String: Any]? {
        guard let d = boundedData(path: path),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return obj["tokens"] as? [String: Any]
    }

    public static func readCodexCredentials(path: String) -> Credentials? {
        guard let t = codexTokens(path: path),
              let token = t["access_token"] as? String, !token.isEmpty else { return nil }
        let claims = jwtClaims(token) ?? [:]
        let auth = claims["https://api.openai.com/auth"] as? [String: Any] ?? [:]
        let exp = (claims["exp"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
        let accountId = (t["account_id"] as? String) ?? (auth["chatgpt_account_id"] as? String)
        return Credentials(token: token, expiresAt: exp, plan: codexPlanName(auth["chatgpt_plan_type"] as? String ?? ""),
                           accountId: accountId)
    }

    /// `prolite` → `Pro Lite`, `plus` → `Plus`.
    public static func codexPlanName(_ raw: String) -> String {
        if raw.lowercased() == "prolite" { return "Pro Lite" }
        return raw.isEmpty ? "?" : raw.prefix(1).uppercased() + raw.dropFirst()
    }

    public static func readCodexEmail(_ path: String) -> String {
        guard let id = codexTokens(path: path)?["id_token"] as? String else { return "" }
        return (jwtClaims(id)?["email"] as? String) ?? ""
    }

    public static func planName(_ oauth: [String: Any]) -> String {
        let sub = (oauth["subscriptionType"] as? String) ?? ""
        let tier = (oauth["rateLimitTier"] as? String) ?? ""
        if sub.lowercased() == "max",
           let r = tier.range(of: #"\d+x$"#, options: .regularExpression) {
            return "Max " + tier[r]
        }
        return sub.isEmpty ? "?" : sub.prefix(1).uppercased() + sub.dropFirst()
    }

    // MARK: - Cache ve marker

    public static func cachePath(key: String) -> String { "\(Cfg.cacheDir)/usage-\(key).json" }
    public static func cachePath(_ a: Account) -> String { cachePath(key: a.cacheKey) }

    public static func parseDate(_ v: Any?) -> Date? {
        if let num = v as? NSNumber, !(v is Bool) {
            let d = num.doubleValue
            return Date(timeIntervalSince1970: d > 1e11 ? d / 1000 : d)
        }
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // 6 haneli kesir (mikrosaniye) gibi tuhaf biçimler için kesiri at.
        if let r = s.range(of: #"\.\d+"#, options: .regularExpression) {
            var t = s; t.removeSubrange(r)
            return f.date(from: t)
        }
        return nil
    }

    /// API null'u başlamamış pencere; eksik/bozuk alan bilinmeyen veridir.
    public static func parseWindow(_ v: Any?) -> Window {
        if v is NSNull { return Window(pct: 0, resetsAt: nil) }
        guard let o = v as? [String: Any], let util = (o["utilization"] as? NSNumber)?.doubleValue,
              util.isFinite, (0...100).contains(util) else { return Window(pct: 0, resetsAt: nil, known: false) }
        return Window(pct: Int(util.rounded()), resetsAt: parseDate(o["resets_at"]))
    }

    /// Dosya, `five_hour` veya `seven_day` anahtarı olan bir JSON objesiyse geçerli kullanım verisidir.
    public static func loadUsage(path: String) -> Usage? {
        guard let d = boundedData(path: path),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              obj["five_hour"] != nil || obj["seven_day"] != nil else { return nil }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
        return Usage(five: parseWindow(obj["five_hour"]), week: parseWindow(obj["seven_day"]), fetchedAt: mtime, hasFive: obj["five_hour"] != nil, hasWeek: obj["seven_day"] != nil)
    }

    /// Codex `wham/usage` yanıtı: `rate_limit.primary_window/secondary_window` → `used_percent`, `reset_at`,
    /// `limit_window_seconds`. Birincil/ikincil sırası plana göre değişir (Pro Lite'ta birincil haftalık),
    /// bu yüzden pencere süresine bakılır: 1 günden kısa → 5 saat, değilse haftalık. Olmayan pencere satırsız.
    public static func loadCodexUsage(path: String) -> Usage? {
        guard let d = boundedData(path: path),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let rl = obj["rate_limit"] as? [String: Any] else { return nil }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
        var u = Usage(five: Window(pct: 0, resetsAt: nil), week: Window(pct: 0, resetsAt: nil), fetchedAt: mtime,
                      hasFive: false, hasWeek: false)
        for key in ["primary_window", "secondary_window"] {
            guard let w = rl[key] as? [String: Any] else { continue }
            guard let used = (w["used_percent"] as? NSNumber)?.doubleValue, used.isFinite, (0...100).contains(used) else { continue }
            let win = Window(pct: Int(used.rounded()), resetsAt: parseDate(w["reset_at"]))
            let secs = (w["limit_window_seconds"] as? NSNumber)?.doubleValue ?? Cfg.weekLength
            if secs < 86400 { u.five = win; u.hasFive = true } else { u.week = win; u.hasWeek = true }
        }
        return u
    }

    public static func loadUsage(_ a: Account) -> Usage? {
        a.provider == .codex ? loadCodexUsage(path: cachePath(a)) : loadUsage(path: cachePath(a))
    }

    public static func markerBlockedUntil(_ a: Account, now: Date = Date()) -> Date? { markerBlockedUntil(key: a.cacheKey, now: now) }

    /// nil = istek atılabilir; aksi halde engelin bitiş zamanı.
    public static func markerBlockedUntil(key: String, now: Date = Date()) -> Date? {
        return markerBlockedUntil(path: cachePath(key: key) + ".attempt", now: now)
    }

    public static func markerBlockedUntil(path: String, now: Date = Date()) -> Date? {
        guard let d = boundedData(path: path) else { return nil }
        let text = (String(data: d, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let until: Date
        if text.isEmpty {
            let m = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
            until = m.addingTimeInterval(Cfg.retrySeconds)
        } else if let secs = Double(text), secs.isFinite {
            until = Date(timeIntervalSince1970: secs)
        } else {
            return nil
        }
        return until > now ? until : nil
    }

    public static func writeAtomic(_ data: Data, to path: String) {
        let tmp = path + ".tmp.\(getpid())"
        do {
            try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: tmp))
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp)
            if rename(tmp, path) != 0 { try? FileManager.default.removeItem(atPath: tmp) }
        } catch {
            try? FileManager.default.removeItem(atPath: tmp)
        }
    }

    public static func blockFetch(_ a: Account, seconds: TimeInterval) { blockFetch(key: a.cacheKey, seconds: seconds) }

    public static func blockFetch(key: String, seconds: TimeInterval) {
        let until = Int(Date().timeIntervalSince1970 + seconds)
        writeAtomic(Data(String(until).utf8), to: cachePath(key: key) + ".attempt")
    }

    // MARK: - Durum ve fetch

    public static func loadState(_ a: Account, creds: Credentials?, now: Date = Date(), names: [Int: String] = loadNames(), profile: AccountProfile? = nil) -> AccountState {
        let codex = a.provider == .codex
        return AccountState(account: a, email: codex ? readCodexEmail(a.config) : profile?.email ?? "",
                            label: codex ? "Codex" : accountLabel(a.n, names: names),
                            plan: creds?.plan ?? "?", loggedIn: creds != nil,
                            tokenExpired: creds.map { !$0.isValid(at: now) } ?? false,
                            usage: loadUsage(a), blockedUntil: markerBlockedUntil(a, now: now),
                            subscriptionAnchor: codex ? nil : profile?.subscriptionAnchor)
    }

    public static func shouldFetch(_ a: Account, creds: Credentials?, force: Bool, now: Date = Date()) -> Bool {
        canFetch(valid: creds?.isValid(at: now) ?? false, cacheDate: loadUsage(a)?.fetchedAt,
                 blockedUntil: markerBlockedUntil(a, now: now), force: force, now: now)
    }

    public static func canFetch(valid: Bool, cacheDate: Date?, blockedUntil: Date?, force: Bool, now: Date) -> Bool {
        guard valid, blockedUntil.map({ $0 <= now }) ?? true else { return false }
        return force || cacheDate.map({ now.timeIntervalSince($0) > Cfg.staleSeconds }) ?? true
    }

    public static func fetchUsage(_ a: Account, creds: Credentials) async {
        let codex = a.provider == .codex
        var req = URLRequest(url: codex ? Cfg.codexUsageURL : Cfg.usageURL, timeoutInterval: 8)
        req.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if codex {
            if let id = creds.accountId { req.setValue(id, forHTTPHeaderField: "ChatGPT-Account-Id") }
            req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        } else {
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            req.setValue("claude-code/2.1.34", forHTTPHeaderField: "User-Agent")
        }
        var wait = Cfg.retrySeconds
        do {
            let (data, resp) = try await Cfg.session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 200, data.count <= 512 << 10,
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   codex ? obj["rate_limit"] is [String: Any] : obj["five_hour"] != nil {
                    writeAtomic(data, to: cachePath(a))
                    return
                }
                if let ra = http.value(forHTTPHeaderField: "retry-after"), let s = Double(ra) { wait = max(s, wait) }
            }
        } catch {}
        blockFetch(a, seconds: wait)
    }

    /// Tüm hesaplar için (isteğe bağlı fetch +) diskten durum yükler.
    public static func refreshAll(fetch: Bool, force: Bool) async -> [AccountState] {
        let accounts = discoverAccounts()
        return await withTaskGroup(of: (Int, AccountState).self) { group in
            for (i, a) in accounts.enumerated() {
                group.addTask {
                    let creds = readCredentials(a)
                    let now = Date()
                    async let profile = accountProfile(a, credentials: creds, fetch: fetch, now: now)
                    if fetch, let c = creds, shouldFetch(a, creds: creds, force: force) {
                        await fetchUsage(a, creds: c)
                    }
                    return (i, loadState(a, creds: creds, profile: await profile))
                }
            }
            var out: [(Int, AccountState)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map { $0.1 }
        }
    }

    // MARK: - OpenRouter kredi bakiyesi (pencere yok; kalan dolar)

    public struct Credit: Sendable {
        public var total: Double       // satın alınan toplam kredi ($)
        public var used: Double        // harcanan ($)
        public var fetchedAt: Date     // cache dosyasının mtime'ı
        public var remaining: Double { max(0, total - used) }
        public var usedPct: Int { total > 0 ? min(100, max(0, Int((used / total * 100).rounded()))) : 100 }

        public init(total: Double, used: Double, fetchedAt: Date) { self.total = total; self.used = used; self.fetchedAt = fetchedAt }

    }

    public struct CreditState: Sendable {
        public var hasKey: Bool
        public var credit: Credit?
        public var blockedUntil: Date?
        /// Anahtar da cache de yoksa kart hiç çizilmez (OpenRouter kullanmayan kurulum).
        public var visible: Bool { hasKey || credit != nil }

        public init(hasKey: Bool, credit: Credit?, blockedUntil: Date?) { self.hasKey = hasKey; self.credit = credit; self.blockedUntil = blockedUntil }

    }

    /// Anahtar yalnız keychain'den okunur (salt-okunur); `Authorization` başlığı dışında hiçbir yere gitmez.
    public static func readOpenRouterKey() -> String? {
        guard let d = keychainSecret(service: Cfg.openRouterService, account: nil),
              let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    /// `/api/v1/credits` yanıtı: `{"data":{"total_credits":20,"total_usage":10.52}}`.
    public static func loadCredit(path: String = cachePath(key: Cfg.creditKey)) -> Credit? {
        guard let d = boundedData(path: path),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let data = obj["data"] as? [String: Any],
              let total = (data["total_credits"] as? NSNumber)?.doubleValue,
              let used = (data["total_usage"] as? NSNumber)?.doubleValue else { return nil }
        guard total.isFinite, used.isFinite, total >= 0, used >= 0 else { return nil }
        let mtime = ((try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date) ?? .distantPast
        return Credit(total: total, used: used, fetchedAt: mtime)
    }

    public static func loadCreditState(hasKey: Bool, now: Date = Date()) -> CreditState {
        CreditState(hasKey: hasKey, credit: loadCredit(), blockedUntil: markerBlockedUntil(key: Cfg.creditKey, now: now))
    }

    public static func shouldFetchCredit(force: Bool, now: Date = Date()) -> Bool {
        guard markerBlockedUntil(key: Cfg.creditKey, now: now) == nil else { return false }
        if force { return true }
        guard let c = loadCredit() else { return true }
        return now.timeIntervalSince(c.fetchedAt) > Cfg.staleSeconds
    }

    public static func fetchCredit(key: String) async {
        var req = URLRequest(url: Cfg.openRouterCreditsURL, timeoutInterval: 8)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var wait = Cfg.retrySeconds
        do {
            let (data, resp) = try await Cfg.session.data(for: req)
            if let http = resp as? HTTPURLResponse {
                if http.statusCode == 200, data.count <= 512 << 10,
                   let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                   let inner = obj["data"] as? [String: Any], inner["total_credits"] is NSNumber {
                    writeAtomic(data, to: cachePath(key: Cfg.creditKey))
                    return
                }
                if let ra = http.value(forHTTPHeaderField: "retry-after"), let s = Double(ra) { wait = max(s, wait) }
            }
        } catch {}
        blockFetch(key: Cfg.creditKey, seconds: wait)
    }

    public static func refreshCredit(fetch: Bool, force: Bool) async -> CreditState {
        let key = readOpenRouterKey()
        if fetch, let key, shouldFetchCredit(force: force) { await fetchCredit(key: key) }
        return loadCreditState(hasKey: key != nil)
    }

    /// `$9.47` / `$9,47`: dollar amount in the user's number format.
    public static func formatUSD(_ v: Double, locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.locale = locale
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        return f.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }


    // MARK: - Biçimlendirme

    public static func level(_ pct: Int) -> Level {
        pct >= 90 ? .red : pct >= 70 ? .yellow : pct >= 50 ? .orange : .green
    }

    /// En yakın dakikaya yuvarlar: API `18:59:59.57` verir, `21:59` değil `22:00` görünsün (OpenUsage ile aynı).
    public static func roundedToMinute(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 60).rounded() * 60)
    }

    /// Same day: clock time only (`14:00` / `2:00 PM`); otherwise the short weekday too.
    public static func formatReset(_ d: Date, now: Date = Date(), locale: Locale = .current) -> String {
        let d = roundedToMinute(d)
        if Calendar.current.isDate(d, inSameDayAs: now) { return clock(d, locale: locale) }
        return d.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated).hour().minute())
    }

    private static func clock(_ d: Date, locale: Locale) -> String {
        d.formatted(Date.FormatStyle(locale: locale).hour().minute())
    }

    public static func formatDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let days = s / 86400, hours = (s % 86400) / 3600, mins = (s % 3600) / 60
        if days >= 1 { return String(localized: "\(days)d \(hours)h") }
        if s >= 3600 { return String(localized: "\(hours)h \(mins)m") }
        return String(localized: "\(mins)m")
    }

    public static func formatCountdown(_ d: Date, now: Date = Date()) -> String { formatDuration(d.timeIntervalSince(now)) }

    public static func formatClock(_ d: Date, seconds: Bool = false, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale).hour().minute()
        return d.formatted(seconds ? style.second() : style)
    }


    // MARK: - Tempo projeksiyonu

    public enum Pace: Equatable, Sendable {
        case runsOut(at: Date, before: TimeInterval)
        case tight(Int)
        case ok(Int)
    }

    /// Bir pencerenin tempo durumu; arayüz her pencere için her zaman tek satır gösterir.
    public enum PaceStatus: Equatable, Sendable {
        case projected(Pace, Int)   // tahmin + sıfırlanırken varılacak yüzde (100'ü aşabilir)
        case early(until: Date)     // pencerenin %1'i dolmadı; tahmin bu andan sonra
        case full                   // limit dolu
        case idle                   // bu pencerede kullanım yok
    }

    /// Doğrusal tempoyla pencere sonunda varılacak yüzdeyi ve limitin dolacağı anı hesaplar.
    /// OpenUsage ile birebir aynı yöntem (`Support/Pace.swift`): geçen süre `now`'a göre, tahmin pencerenin
    /// %1'i (en az 60 sn) geçince başlar; sıfırlanırken >%90 sınırda, >%100 sıfırlanmadan dolar.
    public static func paceStatus(pct: Int, resetsAt: Date?, length: TimeInterval, now: Date) -> PaceStatus {
        if pct >= 100 { return .full }
        guard length.isFinite, length > 0, let reset = resetsAt, reset > now, pct > 0 else { return .idle }
        let start = reset.addingTimeInterval(-length)
        let minElapsed = max(60, length * 0.01)
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= minElapsed else { return .early(until: start.addingTimeInterval(minElapsed)) }
        let projected = Double(pct) / elapsed * length
        guard projected.isFinite, projected < Double(Int.max) else { return .idle }
        let value = Int(projected.rounded())
        if projected > 100 {
            let runOut = now.addingTimeInterval((100 - Double(pct)) / (projected / length))
            return .projected(.runsOut(at: runOut, before: reset.timeIntervalSince(runOut)), value)
        }
        return .projected(projected > 90 ? .tight(value) : .ok(value), value)
    }

    /// Yalnız hesaplanabilen tahmin; erken/dolu/boş pencerede nil.
    public static func projectPace(pct: Int, resetsAt: Date?, length: TimeInterval, now: Date) -> Pace? {
        if case .projected(let p, _) = paceStatus(pct: pct, resetsAt: resetsAt, length: length, now: now) { return p }
        return nil
    }


    /// Within the next 6 days `Fri 14:00`, otherwise `3 Oct 14:00` (locale order and clock).
    public static func formatMoment(_ d: Date, now: Date = Date(), locale: Locale = .current) -> String {
        if d.timeIntervalSince(now) < 6 * 86400 { return formatReset(d, now: now, locale: locale) }
        return dayMonthTime(roundedToMinute(d), locale: locale)
    }

    private static func dayMonthTime(_ d: Date, locale: Locale) -> String {
        d.formatted(Date.FormatStyle(locale: locale).day().month(.abbreviated)) + " " + clock(d, locale: locale)
    }

    // MARK: - OpenUsage tarzı gösterge (WidgetData.MeterState)

    public enum MeterSeverity: Equatable, Sendable { case normal, warning, critical }

    public enum MeterState: Equatable, Sendable {
        case spent                                      // %100: kırmızı, 🔥 Limit doldu
        case runningOut(eta: Date?, projected: Int)     // kırmızı, 🔥 Limit bugün 20:58 (eta nil → alev tek başına)
        case closeToLimit(spare: Int, projected: Int)   // sarı, ~%3 kalır
        case healthy(projected: Int)                    // mavi, Sıfırlanırken ~%64 kalır
        case level(MeterSeverity)                       // tahmin yok: mutlak bant, yazı yok

        public var severity: MeterSeverity {
            switch self {
            case .spent, .runningOut: return .critical
            case .closeToLimit: return .warning
            case .healthy: return .normal
            case .level(let s): return s
            }
        }
    }

    /// OpenUsage `meterState` önceliği: dolu → tempo kararı → mutlak bantlar. %5'in altındaki kullanımda
    /// "sınırda/dolacak" kararına güvenilmez (pencere başındaki %1-2 okumaları sahte alarm üretir).
    public static func meterState(pct: Int, status: PaceStatus) -> MeterState {
        switch status {
        case .full: return .spent
        case .projected(.ok, let v): return .healthy(projected: v)
        case .projected(.tight, let v):
            guard pct >= 5 else { return levelState(pct) }
            return 100 - v >= 1 ? .closeToLimit(spare: 100 - v, projected: v) : .runningOut(eta: nil, projected: v)
        case .projected(.runsOut(let at, _), let v):
            guard pct >= 5 else { return levelState(pct) }
            return .runningOut(eta: at, projected: v)
        case .early, .idle: return levelState(pct)
        }
    }

    /// Tempo tahmini yokken: %90 kırmızı, %80 sarı, altı mavi.
    public static func levelState(_ pct: Int) -> MeterState {
        pct >= 90 ? .level(.critical) : pct >= 80 ? .level(.warning) : .level(.normal)
    }

    /// Eşit tempo çentiği (0...1); OpenUsage gibi yalnız sarı/kırmızı tempo durumunda.
    public static func paceTick(_ m: MeterState, resetsAt: Date?, length: TimeInterval, now: Date) -> Double? {
        switch m {
        case .closeToLimit, .runningOut: break
        default: return nil
        }
        guard let reset = resetsAt, now < reset else { return nil }
        let elapsed = now.timeIntervalSince(reset.addingTimeInterval(-length))
        guard elapsed >= max(60, length * 0.01) else { return nil }
        return min(max(elapsed / length, 0), 1)
    }


    /// OpenUsage `whenLabel`: mutlak `bugün 20:58` / `yarın 00:20` / `6 Eki 11:00`, göreli `1 sa 28 dk`
    /// (dakika yukarı yuvarlanır). Geçmişte ya da göreli ≤5 dk → nil ("yakında").
    public static func formatWhen(_ d: Date, now: Date, relative: Bool, locale: Locale = .current) -> String? {
        let secs = d.timeIntervalSince(now)
        if relative { return secs <= 300 ? nil : formatDuration((secs / 60).rounded(.up) * 60) }
        guard secs > 0 else { return nil }
        let r = roundedToMinute(d)
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: r)).day ?? 0
        let hm = clock(r, locale: locale)
        if days <= 0 { return String(localized: "today \(hm)") }
        if days == 1 { return String(localized: "tomorrow \(hm)") }
        return dayMonthTime(r, locale: locale)
    }

    /// Etiket satırının sağı: `Limit bugün 20:58`, `Limit doldu`, `~%3 kalır`, `Sıfırlanırken ~%64 kalır`; nil = yazı yok.
    public static func meterNote(_ m: MeterState, now: Date, relative: Bool) -> String? {
        switch m {
        case .spent: return String(localized: "Limit reached")
        case .runningOut(let eta?, _):
            guard let w = formatWhen(eta, now: now, relative: relative) else { return String(localized: "Runs out soon") }
            return relative ? String(localized: "Runs out in \(w)") : String(localized: "Runs out \(w)")
        case .runningOut(nil, _): return nil
        case .closeToLimit(let spare, _): return String(localized: "~\(LocalizedFormat.percent(spare)) left")
        case .healthy(let v): return String(localized: "~\(LocalizedFormat.percent(max(0, 100 - v))) left at reset")
        case .level: return nil
        }
    }

    /// Üzerine gelince ipucu (OpenUsage `MeterState.tooltip`).
    public static func meterTooltip(_ m: MeterState) -> String? {
        switch m {
        case .spent: return String(localized: "Limit reached")
        case .healthy(let v): return String(localized: "~\(LocalizedFormat.percent(max(0, 100 - v))) left at reset")
        case .closeToLimit(_, let v): return String(localized: "~\(LocalizedFormat.percent(v)) used at reset")
        case .runningOut(_, let v):
            return v > 100 ? String(localized: "Limit exceeded by ~\(LocalizedFormat.percent(max(1, v - 100))) at reset")
                : String(localized: "~\(LocalizedFormat.percent(100)) used at reset")
        case .level: return nil
        }
    }

    /// Alt satırın sağı: `Sıfırlanma yarın 00:20` / `Sıfırlanmaya 4 sa 45 dk` / `Yakında sıfırlanır` / `Başlamadı`.
    /// `compact` replaces the reset word with `↻` for narrow columns.
    public static func resetLabel(_ w: Window, now: Date, relative: Bool, notStarted: Bool, compact: Bool = false) -> String? {
        if notStarted { return String(localized: "Not started") }
        guard let r = w.resetsAt else { return nil }
        guard let when = formatWhen(r, now: now, relative: relative) else { return String(localized: "Resets soon") }
        if compact { return "↻ \(when)" }
        return relative ? String(localized: "Resets in \(when)") : String(localized: "Resets \(when)")
    }

    /// Menü çubuğu ipucu eki: `· 5 saat limit bugün 20:58`; dolacak değilse nil.
    public static func meterTooltipSuffix(_ m: MeterState, name: String, now: Date) -> String? {
        guard case .runningOut(let eta, _) = m else { return nil }
        let when = eta.flatMap { formatWhen($0, now: now, relative: false) } ?? String(localized: "soon")
        return " · " + String(localized: "\(name) limit runs out \(when)")
    }



    // MARK: - Fatura dönemi token toplamı (yerel transcript'lerden; UI yok, ağ yok)
    //
    // Kaynak: `~/.claude/projects/**.jsonl` (hesaplar `projects`'i paylaşır). Her asistan mesajının `message.usage`'ı
    // bir kez sayılır (`message.id` + `requestId`; akışta aynı mesaj birden çok satır yazılır). Oturumun hesabı
    // `<hesap dizini>/session-env/<oturum>` klasöründen bulunur; hiçbir hesapta olmayan oturum "belirsiz" sayılır.
    // Dönem: `oauthAccount.subscriptionCreatedAt` gününden aylık (Stripe yıl dönümü; ay kısaysa ayın son günü).

    public struct TokenCounts: Equatable, Sendable {
        public var input = 0, output = 0, cacheWrite = 0, cacheRead = 0
        public var total: Int { input + output + cacheWrite + cacheRead }
        public static func + (a: TokenCounts, b: TokenCounts) -> TokenCounts {
            TokenCounts(input: a.input + b.input, output: a.output + b.output,
                        cacheWrite: a.cacheWrite + b.cacheWrite, cacheRead: a.cacheRead + b.cacheRead)
        }

        public init(input: Int = 0, output: Int = 0, cacheWrite: Int = 0, cacheRead: Int = 0) { self.input = input; self.output = output; self.cacheWrite = cacheWrite; self.cacheRead = cacheRead }

    }

    public struct BillingPeriod: Equatable, Sendable {
        public let start: Date
        public let end: Date

        public init(start: Date, end: Date) { self.start = start; self.end = end }

    }

    public struct PeriodTokens: Sendable {
        public let period: BillingPeriod
        public let counts: TokenCounts

        public init(period: BillingPeriod, counts: TokenCounts) { self.period = period; self.counts = counts }

    }

    public struct TokenReport: Sendable {
        public var byAccount: [Int: PeriodTokens] = [:]
        /// Hiçbir hesabın `session-env`'inde olmayan oturumlar; en geç başlayan dönemden bu yana.
        public var unattributed = TokenCounts()
        public var scannedAt = Date.distantPast

        public init() {}
        public init(scannedAt: Date) { self.scannedAt = scannedAt }

    }

    /// `subscriptionCreatedAt` (abonelik yıl dönümü); yoksa nil (giriş yok ya da ücretsiz hesap).
    public static func readSubscriptionAnchor(_ configPath: String) -> Date? {
        guard let d = boundedData(path: configPath),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
              let oa = obj["oauthAccount"] as? [String: Any] else { return nil }
        return parseDate(oa["subscriptionCreatedAt"])
    }

    private static let utcCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// `now`'ı içeren aylık dönem. Her sınır yıl dönümünden ay eklenerek bulunur (zincirleme değil):
    /// 31'inde başlayan abonelik Şubat'ta 28'inde, Mart'ta yine 31'inde yenilenir.
    public static func billingPeriod(anchor: Date, now: Date) -> BillingPeriod {
        let cal = utcCalendar
        var k = max(0, cal.dateComponents([.month], from: anchor, to: now).month ?? 0)
        func boundary(_ m: Int) -> Date { cal.date(byAdding: .month, value: m, to: anchor) ?? anchor }
        while k > 0 && boundary(k) > now { k -= 1 }
        while boundary(k + 1) <= now { k += 1 }
        return BillingPeriod(start: boundary(k), end: boundary(k + 1))
    }

    // MARK: Transcript okuma

    /// Bir transcript satırından (yalnız asistan mesajı) tekilleştirme anahtarı, saat kovası ve sayılar.
    public static func parseUsageLine(_ line: Substring) -> (key: String, hour: Int, counts: TokenCounts)? {
        guard line.contains("\"usage\""), line.contains("\"assistant\""),
              let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              obj["type"] as? String == "assistant",
              let msg = obj["message"] as? [String: Any],
              let usage = msg["usage"] as? [String: Any],
              let ts = obj["timestamp"] as? String, let hour = utcHourBucket(ts) else { return nil }
        func n(_ k: String) -> Int { (usage[k] as? NSNumber)?.intValue ?? 0 }
        let counts = TokenCounts(input: n("input_tokens"), output: n("output_tokens"),
                                 cacheWrite: n("cache_creation_input_tokens"), cacheRead: n("cache_read_input_tokens"))
        guard [counts.input, counts.output, counts.cacheWrite, counts.cacheRead].allSatisfy({ (0...1_000_000_000_000).contains($0) }), counts.total > 0 else { return nil }
        let id = (msg["id"] as? String) ?? ""
        let req = (obj["requestId"] as? String) ?? ""
        guard !id.isEmpty || !req.isEmpty else { return nil }
        return ("\(id):\(req)", hour, counts)
    }

    /// `2026-10-06T19:45:08.123Z` → o saatin UTC epoch'u (dakika/saniye atılır).
    public static func utcHourBucket(_ ts: String) -> Int? {
        let u = Array(ts.utf8)
        guard u.count >= 13, u[4] == 45, u[7] == 45, u[10] == 84 else { return nil }   // '-', '-', 'T'
        func num(_ a: Int, _ b: Int) -> Int32? {
            var v: Int32 = 0
            for i in a..<b { guard u[i] >= 48 && u[i] <= 57 else { return nil }; v = v * 10 + Int32(u[i] - 48) }
            return v
        }
        guard let y = num(0, 4), let mo = num(5, 7), let d = num(8, 10), let h = num(11, 13), (1970...9999).contains(y), (1...12).contains(mo), (1...31).contains(d), (0...23).contains(h) else { return nil }
        var t = tm()
        t.tm_year = y - 1900; t.tm_mon = mo - 1; t.tm_mday = d; t.tm_hour = h
        return Int(timegm(&t))
    }

    /// Bir dosyanın sayılmış hali: okunan bayt, son tekilleştirme anahtarları, saat kovaları.
    public struct FileTally: Codable, Sendable {
        public var size: Int
        public var mtime: Double
        public var offset: Int
        public var keys: [String]
        public var buckets: [Int: [Int]]   // saat → [girdi, çıktı, önbellek yazma, önbellek okuma]

    }

    /// Dosyayı kaldığı bayttan sona kadar 4 MB'lık parçalarla okur (yüz MB'lık transcript belleğe bir kerede
    /// alınmaz). Yalnız tam satırlar sayılır; yarım son satır sonraki taramaya kalır.
    public static func tallyFile(path: String, previous: FileTally?, size: Int, mtime: Double) -> FileTally {
        var tally = previous ?? FileTally(size: 0, mtime: 0, offset: 0, keys: [], buckets: [:])
        // Dosya küçüldüyse (yeniden yazıldıysa) baştan say.
        if tally.offset < 0 || size < tally.offset || !tally.buckets.values.allSatisfy({ $0.count == 4 && $0.allSatisfy { $0 >= 0 && $0 <= 1_000_000_000_000_000 } }) { tally = FileTally(size: 0, mtime: 0, offset: 0, keys: [], buckets: [:]) }
        guard let fh = FileHandle(forReadingAtPath: path) else { return tally }
        tally.size = size; tally.mtime = mtime
        defer { try? fh.close() }
        try? fh.seek(toOffset: UInt64(tally.offset))
        var seen = Set(tally.keys)
        var recent = tally.keys
        var carry = Data()
        while !Task.isCancelled, let chunk = try? fh.read(upToCount: 4 << 20), !chunk.isEmpty {
            carry.append(chunk)
            guard carry.count <= 16 << 20 else { break }
            guard let lastNewline = carry.lastIndex(of: 10) else { continue }
            let complete = carry[carry.startIndex...lastNewline]
            for raw in complete.split(separator: 10, omittingEmptySubsequences: true) {
                let line = Substring(String(decoding: raw, as: UTF8.self))
                guard let r = parseUsageLine(line), !seen.contains(r.key) else { continue }
                seen.insert(r.key)
                recent.append(r.key)
                let c = r.counts
                var b = tally.buckets[r.hour] ?? [0, 0, 0, 0]
                b[0] += c.input; b[1] += c.output; b[2] += c.cacheWrite; b[3] += c.cacheRead
                tally.buckets[r.hour] = b
            }
            tally.offset += complete.count
            carry = Data(carry[carry.index(after: lastNewline)...])
        }
        // A transcript can grow between inventory and EOF. Keep the consumed
        // prefix valid for the next incremental read instead of rescanning it.
        tally.size = max(size, tally.offset + carry.count)
        tally.keys = Array(recent.suffix(64))
        return tally
    }

    /// Ana transcript `<proje>/<oturum>.jsonl`, alt ajan `<proje>/<oturum>/subagents/*.jsonl`: ikisi de o oturumun.
    public static func sessionId(ofTranscript path: String) -> String {
        let parts = path.split(separator: "/")
        if let i = parts.lastIndex(of: "subagents"), i >= 1 { return String(parts[i - 1]) }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    // MARK: Hesap eşleme

    /// Oturum → [(session-env klasörünün doğuşu, hesap)], doğuşa göre sıralı. Aynı oturum başka hesapla
    /// sürdürüldüyse (resume) her saat kovası o saatte açılmış son hesaba yazılır.
    public static func sessionOwners(_ accounts: [Account]) -> [String: [(born: Double, n: Int)]] {
        var out: [String: [(born: Double, n: Int)]] = [:]
        for a in accounts where a.provider == .claude {
            let dir = a.dir + "/session-env"
            for name in (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? [] {
                let attrs = try? FileManager.default.attributesOfItem(atPath: dir + "/" + name)
                let born = ((attrs?[.creationDate] as? Date) ?? .distantPast).timeIntervalSince1970
                out[name, default: []].append((born, a.n))
            }
        }
        return out.mapValues { $0.sorted { $0.born < $1.born } }
    }

    public static func owner(of hour: Int, in owners: [(born: Double, n: Int)]) -> Int? {
        guard let first = owners.first else { return nil }
        return owners.last(where: { $0.born <= Double(hour + 3600) })?.n ?? first.n
    }

    // MARK: Tarama ve toplam

    public enum TokenIndex {
        public static let path = Cfg.home + "/Library/Application Support/MacPulse/ai-token-index.json"
        public static let projectsDir = Cfg.home + "/.claude/projects"

        static func load(from path: String = path) -> [String: FileTally] {
            guard let d = boundedData(path: path),
                  let v = try? JSONDecoder().decode([String: FileTally].self, from: d) else { return [:] }
            return v
        }

        static func save(_ index: [String: FileTally], to path: String = path) {
            guard let d = try? JSONEncoder().encode(index) else { return }
            writeAtomic(d, to: path)
        }
    }

    /// `since`'ten sonra değişmiş transcript'leri (ana + alt ajan) listeler.
    public static func transcriptFiles(under root: String, modifiedSince since: Date) -> [(path: String, size: Int, mtime: Double)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: keys) else { return [] }
        var out: [(String, Int, Double)] = []
        for case let url as URL in e where url.pathExtension == "jsonl" {
            if Task.isCancelled { break }
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true,
                  let m = v.contentModificationDate, m >= since else { continue }
            out.append((url.path, v.fileSize ?? 0, m.timeIntervalSince1970))
        }
        return out
    }

    /// Hesap başına fatura dönemi toplamı. Değişmeyen dosya yeniden okunmaz, büyüyen dosya kaldığı yerden okunur;
    /// dizin `tokens-index.json`'a yazılır (yalnız sayılar ve dosya yolları; mesaj içeriği yok).
    public static func scanTokens(accounts: [Account], now: Date = Date(), projectsDir: String = TokenIndex.projectsDir,
                    indexPath: String = TokenIndex.path, subscriptionAnchors: [Int: Date]? = nil) -> TokenReport {
        var periods: [Int: BillingPeriod] = [:]
        for a in accounts where a.provider == .claude {
            let anchor: Date?
            if let subscriptionAnchors { anchor = subscriptionAnchors[a.n] }
            else { anchor = readSubscriptionAnchor(a.config) }
            if let anchor { periods[a.n] = billingPeriod(anchor: anchor, now: now) }
        }
        var report = TokenReport(scannedAt: now)
        guard let earliest = periods.values.map(\.start).min() else { return report }
        let latest = periods.values.map(\.start).max() ?? earliest

        var index = TokenIndex.load(from: indexPath)
        var fresh: [String: FileTally] = [:]
        for f in transcriptFiles(under: projectsDir, modifiedSince: earliest) {
            if Task.isCancelled { return report }
            let prev = index[f.path]
            fresh[f.path] = (prev?.size == f.size && prev?.mtime == f.mtime) ? prev!
                : tallyFile(path: f.path, previous: prev, size: f.size, mtime: f.mtime)
        }
        index = fresh   // dönem dışına düşen ve silinen dosyalar dizinden çıkar
        guard !Task.isCancelled else { return report }
        TokenIndex.save(index, to: indexPath)

        let owners = sessionOwners(accounts)
        var sums: [Int: TokenCounts] = [:]
        for (path, tally) in index {
            let who = owners[sessionId(ofTranscript: path)] ?? []
            for (hour, b) in tally.buckets {
                guard b.count == 4, b.allSatisfy({ $0 >= 0 && $0 <= 1_000_000_000_000_000 }) else { continue }
                let c = TokenCounts(input: b[0], output: b[1], cacheWrite: b[2], cacheRead: b[3])
                let at = Date(timeIntervalSince1970: TimeInterval(hour))
                if let n = owner(of: hour, in: who) {
                    guard let p = periods[n], at >= hourFloor(p.start), at < p.end else { continue }
                    sums[n] = (sums[n] ?? TokenCounts()) + c
                } else if at >= hourFloor(latest) {
                    report.unattributed = report.unattributed + c
                }
            }
        }
        for (n, p) in periods { report.byAccount[n] = PeriodTokens(period: p, counts: sums[n] ?? TokenCounts()) }
        return report
    }

    /// Dönem başı saat kovasına hizalanır (kovalar saat başı).
    private static func hourFloor(_ d: Date) -> Date {
        Date(timeIntervalSince1970: (d.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    // MARK: Biçimlendirme

    /// `1.23B`, `345.6M`, `12.3K`, `850`; digits follow the user's number format.
    public static func formatTokens(_ n: Int, locale: Locale = .current) -> String {
        func f(_ v: Double) -> String {
            let digits = v >= 100 ? 0 : v >= 10 ? 1 : 2
            return v.formatted(.number.precision(.fractionLength(digits)).grouping(.never).locale(locale))
        }
        let v = Double(n)
        if v >= 1e9 { return String(localized: "\(f(v / 1e9))B") }
        if v >= 1e6 { return String(localized: "\(f(v / 1e6))M") }
        if v >= 1e4 { return String(localized: "\(f(v / 1e3))K") }
        return String(n)
    }

    /// `Sep 25 – Oct 25` / `25 Eyl – 25 Eki` (local day, no year).
    public static func formatPeriod(_ p: BillingPeriod, locale: Locale = .current) -> String {
        let style = Date.FormatStyle(locale: locale).day().month(.abbreviated)
        return "\(p.start.formatted(style)) – \(p.end.formatted(style))"
    }

    public static func tokenBreakdown(_ c: TokenCounts) -> String {
        String(localized: "Input \(formatTokens(c.input)) · Output \(formatTokens(c.output)) · Cache write \(formatTokens(c.cacheWrite)) · Cache read \(formatTokens(c.cacheRead))")
    }

}
