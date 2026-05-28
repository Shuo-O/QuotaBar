import Foundation

struct ProviderUsage {
    let percent: Double?
    let resetText: String?
    let source: String

    static let missing = ProviderUsage(percent: nil, resetText: nil, source: "未发现数据")

    var shortLabel: String {
        guard let percent else { return "--%" }
        return "\(Int(percent.rounded()))%"
    }

    func menuLine(prefix: String) -> String {
        var parts = ["\(prefix): \(shortLabel)"]
        if let resetText {
            parts.append("重置 \(resetText)")
        }
        parts.append(source)
        return parts.joined(separator: " · ")
    }
}

struct UsageSnapshot {
    let claude: ProviderUsage
    let codex: ProviderUsage

    static let empty = UsageSnapshot(claude: .missing, codex: .missing)

    var bestPercent: Double? {
        [claude.percent, codex.percent].compactMap { $0 }.max()
    }

    var shortLabel: String {
        if claude.percent != nil, codex.percent != nil {
            return "C \(claude.shortLabel) / X \(codex.shortLabel)"
        }
        if claude.percent != nil {
            return "Claude \(claude.shortLabel)"
        }
        if codex.percent != nil {
            return "Codex \(codex.shortLabel)"
        }
        return "--%"
    }

    var menuTitle: String {
        "当前用量：\(shortLabel)"
    }

    var tooltip: String {
        "\(claude.menuLine(prefix: "Claude"))\n\(codex.menuLine(prefix: "Codex"))"
    }
}
