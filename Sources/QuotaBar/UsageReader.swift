import Foundation
import Security

@MainActor
final class UsageReader {
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser
    private let settings: SettingsStore

    private let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let isoFallback = ISO8601DateFormatter()

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func read() async -> UsageSnapshot {
        async let claude = readClaude()
        let codex = readCodex()
        return await UsageSnapshot(claude: claude, codex: codex)
    }

    // MARK: - Claude

    private func readClaude() async -> ProviderUsage {
        // 1. OAuth API – most accurate, direct from Anthropic
        if let result = await readClaudeFromAPI() { return result }

        // 2. Dedicated status files (compatible with aqua5230/usage)
        for url in [home.appendingPathComponent(".claude/usage-status.json"),
                    home.appendingPathComponent(".claude/tt-status.json")]
        where fm.fileExists(atPath: url.path) {
            if let v = readJSON(url).flatMap(extractUsage(from:)) {
                return ProviderUsage(percent: v.percent, resetText: v.resetText,
                                     source: url.lastPathComponent)
            }
        }

        // 3. Compute from project JSONL files
        return readClaudeFromJSONL()
    }

    // MARK: - Claude OAuth API

    private func readClaudeFromAPI() async -> ProviderUsage? {
        guard let cred = keychainClaudeToken() else { return nil }
        // Skip if token is expired (with 60s buffer)
        guard Date().timeIntervalSince1970 < cred.expiresAt - 60 else { return nil }

        guard let url = URL(string: "https://claude.ai/api/oauth/usage") else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fiveHour = json["five_hour"] as? [String: Any],
              let utilization = fiveHour["utilization"] as? Double
        else { return nil }

        let resetText = (fiveHour["resets_at"] as? String).flatMap { timeUntilReset($0) }
        return ProviderUsage(percent: utilization, resetText: resetText, source: "claude.ai")
    }

    private func keychainClaudeToken() -> (token: String, expiresAt: TimeInterval)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String,
              let expiresAtMs = oauth["expiresAt"] as? Double
        else { return nil }
        return (token, expiresAtMs / 1000)
    }

    private func timeUntilReset(_ isoStr: String) -> String? {
        guard let date = iso.date(from: isoStr) ?? isoFallback.date(from: isoStr) else { return nil }
        let diff = date.timeIntervalSinceNow
        guard diff > 0 else { return "即将重置" }
        let h = Int(diff / 3600)
        let m = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "还剩 \(h)h\(m)m" : "还剩 \(m)m"
    }

    // MARK: - Claude JSONL fallback

    private func readClaudeFromJSONL() -> ProviderUsage {
        let root = resolvedURL(settings.claudeProjectsPath, defaultRelative: ".claude/projects")
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(at: root,
                  includingPropertiesForKeys: [.contentModificationDateKey])
        else { return .missing }

        let windowStart = Date().addingTimeInterval(-5 * 3600)
        var totalTokens = 0
        var hasData = false

        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            guard mod >= windowStart.addingTimeInterval(-3600) else { continue }

            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tsStr = obj["timestamp"] as? String,
                      let ts = parseDate(tsStr), ts >= windowStart,
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any] else { continue }

                totalTokens += (usage["input_tokens"] as? Int ?? 0)
                    + (usage["output_tokens"] as? Int ?? 0)
                    + (usage["cache_creation_input_tokens"] as? Int ?? 0)
                hasData = true
            }
        }

        guard hasData else { return .missing }
        let limit = settings.claudeTokenLimit
        let percent = min(Double(totalTokens) / Double(limit) * 100, 100)
        let label = totalTokens >= 1_000 ? "\(totalTokens / 1_000)K tok" : "\(totalTokens) tok"
        return ProviderUsage(percent: percent, resetText: nil, source: "5h: \(label)")
    }

    // MARK: - Codex

    private func readCodex() -> ProviderUsage {
        let root = resolvedURL(settings.codexSessionsPath, defaultRelative: ".codex/sessions")
        guard let enumerator = fm.enumerator(at: root,
            includingPropertiesForKeys: [.contentModificationDateKey])
        else { return .missing }

        var latest: (url: URL, date: Date)?
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if latest == nil || date > latest!.date { latest = (url, date) }
        }

        guard let latest else { return .missing }
        guard let lines = try? String(contentsOf: latest.url, encoding: .utf8)
            .split(separator: "\n") else { return .missing }

        // Scan lines in reverse for the most recent token_count event
        for line in lines.reversed() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = obj["payload"] as? [String: Any],
                  payload["type"] as? String == "token_count",
                  let rl = payload["rate_limits"] as? [String: Any],
                  let primary = rl["primary"] as? [String: Any],
                  let usedPct = primary["used_percent"] as? Double
            else { continue }

            let resetText: String?
            if let resetsAt = primary["resets_at"] as? Double {
                resetText = timeUntilUnixReset(resetsAt)
            } else {
                resetText = nil
            }
            return ProviderUsage(percent: usedPct, resetText: resetText,
                                 source: shortFileName(latest.url))
        }
        return .missing
    }

    private func timeUntilUnixReset(_ timestamp: Double) -> String? {
        let diff = timestamp - Date().timeIntervalSince1970
        guard diff > 0 else { return "即将重置" }
        let h = Int(diff / 3600)
        let m = Int(diff.truncatingRemainder(dividingBy: 3600) / 60)
        return h > 0 ? "还剩 \(h)h\(m)m" : "还剩 \(m)m"
    }

    // MARK: - Helpers

    private func resolvedURL(_ custom: String?, defaultRelative: String) -> URL {
        if let raw = custom, !raw.isEmpty {
            let expanded = raw.hasPrefix("~") ? home.path + raw.dropFirst() : raw
            return URL(fileURLWithPath: expanded)
        }
        return home.appendingPathComponent(defaultRelative)
    }

    private func parseDate(_ str: String) -> Date? {
        iso.date(from: str) ?? isoFallback.date(from: str)
    }

    private func shortFileName(_ url: URL) -> String {
        let name = url.lastPathComponent
        guard name.count > 24 else { return name }
        return String(name.prefix(8)) + "…" + String(name.suffix(12))
    }

    private func readJSON(_ url: URL) -> Any? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private func extractUsage(from object: Any) -> (percent: Double, resetText: String?)? {
        let flat = flatten(object)
        let candidates = flat.compactMap { path, value -> (score: Int, value: Double)? in
            guard let n = numericValue(value), n >= 0, n <= 100 else { return nil }
            let key = path.lowercased()
            var score = 0
            if key.contains("percent") || key.contains("usage") || key.contains("used") { score += 3 }
            if key.contains("5h") || key.contains("session") || key.contains("primary") { score += 4 }
            if key.contains("rate") || key.contains("limit") || key.contains("quota") { score += 2 }
            if key.contains("weekly") || key.contains("7d") { score += 1 }
            return score > 0 ? (score, n) : nil
        }
        guard let best = candidates.sorted(by: { $0.score > $1.score }).first else { return nil }
        let reset = flat.compactMap { path, value -> String? in
            let key = path.lowercased()
            guard key.contains("reset") || key.contains("remaining") else { return nil }
            return stringValue(value)
        }.first
        return (best.value, reset)
    }

    private func flatten(_ object: Any, prefix: String = "") -> [(String, Any)] {
        if let dict = object as? [String: Any] {
            return dict.flatMap { k, v in flatten(v, prefix: prefix.isEmpty ? k : "\(prefix).\(k)") }
        }
        if let arr = object as? [Any] {
            return arr.enumerated().flatMap { i, v in flatten(v, prefix: "\(prefix)[\(i)]") }
        }
        return [(prefix, object)]
    }

    private func numericValue(_ value: Any) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String {
            return Double(s.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
        }
        return nil
    }

    private func stringValue(_ value: Any) -> String? {
        if let s = value as? String, !s.isEmpty { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }
}
