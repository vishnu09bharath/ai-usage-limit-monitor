import Foundation

/// Represents the usage limit for a single time window (hourly or weekly).
struct CodexLimitWindow: Equatable {
    /// The percentage of the limit that has been used (0-100).
    let usedPercent: Int

    /// The remaining percentage (0-100).
    var remainingPercent: Int {
        max(0, 100 - usedPercent)
    }

    /// The duration of the rolling window in minutes (e.g., 60 for hourly, 10080 for weekly).
    let windowMinutes: Int?

    /// Override label parsed from output (e.g., "5h limit").
    let labelOverride: String?

    /// When the limit resets.
    let resetsAt: Date?

    /// Human-readable time until reset.
    var timeUntilReset: String? {
        guard let resetsAt else { return nil }
        return CodexFormatting.formatTimeUntilReset(resetsAt)
    }

    /// Whether the limit is exhausted.
    var isExhausted: Bool {
        usedPercent >= 100
    }

    /// Display label for the window type.
    var windowLabel: String {
        if let labelOverride, !labelOverride.isEmpty {
            return labelOverride
        }
        guard let windowMinutes else { return "Limit" }
        if windowMinutes <= 60 {
            return "Hourly Limit"
        } else if windowMinutes <= 1440 {
            return "Daily Limit"
        } else {
            return "Weekly Limit"
        }
    }
}

/// A snapshot of Codex CLI usage at a point in time.
struct CodexSnapshot: Equatable {
    /// When this snapshot was captured.
    let timestamp: Date
    
    /// The user's email (extracted from the session).
    let email: String?
    
    /// The user's ChatGPT plan type (plus, pro, team, enterprise, etc.).
    let planType: String?
    
    /// The ChatGPT account ID (workspace).
    let accountId: String?
    
    /// Primary limit window (typically the smallest window like hourly/5h).
    let primaryLimit: CodexLimitWindow?
    
    /// Secondary limit window (typically the larger window like weekly).
    let secondaryLimit: CodexLimitWindow?
    
    /// Whether this snapshot contains any meaningful data.
    var hasData: Bool {
        primaryLimit != nil || secondaryLimit != nil
    }
    
    /// The most constrained limit (lowest remaining %).
    var mostConstrainedLimit: CodexLimitWindow? {
        switch (primaryLimit, secondaryLimit) {
        case let (p?, s?):
            return p.remainingPercent <= s.remainingPercent ? p : s
        case let (p?, nil):
            return p
        case let (nil, s?):
            return s
        case (nil, nil):
            return nil
        }
    }
    
    /// Tooltip text for the menu bar.
    var tooltipText: String {
        var lines = [String]()
        
        if let primary = primaryLimit {
            let reset = primary.timeUntilReset.map { " · \($0)" } ?? ""
            lines.append("\(primary.windowLabel): \(primary.remainingPercent)% left\(reset)")
        }

        if let secondary = secondaryLimit {
            let reset = secondary.timeUntilReset.map { " · \($0)" } ?? ""
            lines.append("\(secondary.windowLabel): \(secondary.remainingPercent)% left\(reset)")
        }

        if lines.isEmpty {
            return "Codex: No usage data"
        }

        return lines.joined(separator: "\n")
    }
}

/// Formatting utilities for Codex quota display.
enum CodexFormatting {
    /// Format a reset time as a human-readable duration.
    static func formatTimeUntilReset(_ resetTime: Date) -> String {
        let seconds = resetTime.timeIntervalSinceNow
        if seconds <= 0 {
            return "Ready"
        }
        
        let totalMinutes = Int(ceil(seconds / 60))
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        
        let hours = totalMinutes / 60
        let mins = totalMinutes % 60
        
        if hours < 24 {
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours > 0 ? "\(days)d \(remainingHours)h" : "\(days)d"
    }
    
    /// Parse a plan type string into a display label.
    static func planLabel(_ planType: String?) -> String? {
        guard let planType = planType?.lowercased() else { return nil }

        switch planType {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        case "free": return "Free"
        default: return planType.capitalized
        }
    }

    /// Shorten a ChatGPT account ID for display.
    static func shortAccountId(_ accountId: String?) -> String? {
        guard let accountId, !accountId.isEmpty else { return nil }
        if accountId.count <= 10 { return accountId }
        let prefix = accountId.prefix(6)
        let suffix = accountId.suffix(4)
        return "\(prefix)…\(suffix)"
    }
}

/// Parser for extracting usage data from Codex CLI /status output.
enum CodexOutputParser {
    /// Regex patterns for parsing /status output.
    /// Example output lines:
    ///   "Primary: 45% used (resets in 12m)"
    ///   "Secondary: 12% used (resets in 3d 4h)"
    ///   "Hourly: 32% of limit used"
    ///   "Weekly: 18% of limit used"
    
    /// Parse the raw /status output and extract a CodexSnapshot.
    static func parseStatusOutput(_ output: String, email: String? = nil, planType: String? = nil, accountId: String? = nil) -> CodexSnapshot {
        // Strip ANSI escape codes
        let cleaned = stripANSI(output)
        
        // Look for usage patterns with explicit windows (e.g., "5h", "weekly")
        let windowedLimits = parseWindowedLimits(from: cleaned)
        let sortedWindowed = windowedLimits.sorted { ($0.windowMinutes ?? Int.max) < ($1.windowMinutes ?? Int.max) }

        let primaryLimit = sortedWindowed.first ?? parseLimit(from: cleaned, patterns: [
            #"(?i)(?:primary|hourly)[:\s]+(\d+)%\s*(?:used|of)"#,
            #"(?i)(\d+)%\s*(?:of\s+)?(?:hourly|primary)"#
        ], windowMinutes: 60)

        let secondaryLimit: CodexLimitWindow? = {
            if sortedWindowed.count > 1 {
                return sortedWindowed.last
            }
            return parseLimit(from: cleaned, patterns: [
                #"(?i)(?:secondary|weekly)[:\s]+(\d+)%\s*(?:used|of)"#,
                #"(?i)(\d+)%\s*(?:of\s+)?(?:weekly|secondary)"#
            ], windowMinutes: 10080)
        }()
        
        let parsedAccount = parseAccountInfo(from: cleaned)
        let resolvedEmail = email ?? parsedAccount.email
        let resolvedPlan = planType ?? parsedAccount.planType

        return CodexSnapshot(
            timestamp: Date(),
            email: resolvedEmail,
            planType: resolvedPlan,
            accountId: accountId,
            primaryLimit: primaryLimit,
            secondaryLimit: secondaryLimit
        )
    }
    
    private static func parseAccountInfo(from text: String) -> (email: String?, planType: String?) {
        let pattern = #"Account:\s*([^\s]+)\s*\(([^\)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return (nil, nil)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              let emailRange = Range(match.range(at: 1), in: text),
              let planRange = Range(match.range(at: 2), in: text) else {
            return (nil, nil)
        }

        let email = String(text[emailRange])
        let planRaw = String(text[planRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let planType = planRaw.lowercased()
        return (email, planType)
    }

    /// Strip ANSI escape sequences from a string.
    static func stripANSI(_ input: String) -> String {
        // Match ANSI escape sequences: ESC [ ... final byte
        let pattern = #"\x1B\[[0-9;]*[A-Za-z]|\x1B\].*?\x07|\x1B[PX^_].*?\x1B\\"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return input
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.stringByReplacingMatches(in: input, options: [], range: range, withTemplate: "")
    }
    
    /// Parse limits with explicit time window labels (e.g., "5h", "weekly").
    private static func parseWindowedLimits(from text: String) -> [CodexLimitWindow] {
        let patterns = [
            #"(?i)(\d{1,3})%[^\n]*?(hourly|daily|weekly|\d+\s*h(?:ours?)?|\d+\s*d(?:ays?)?)"#,
            #"(?i)(hourly|daily|weekly|\d+\s*h(?:ours?)?|\d+\s*d(?:ays?)?)[^\n]*?(\d{1,3})%"#
        ]

        var results: [CodexLimitWindow] = []
        var seenWindows = Set<Int>()

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = regex.matches(in: text, options: [], range: range)

            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }

                guard let first = Range(match.range(at: 1), in: text).map({ String(text[$0]) }),
                      let second = Range(match.range(at: 2), in: text).map({ String(text[$0]) }) else { continue }

                let percentString: String
                let labelString: String

                if first.rangeOfCharacter(from: CharacterSet.letters) != nil {
                    labelString = first
                    percentString = second
                } else {
                    percentString = first
                    labelString = second
                }

                let percentValue = Int(percentString) ?? -1
                guard percentValue >= 0, percentValue <= 100 else { continue }

                guard let minutes = windowMinutes(from: labelString) else { continue }
                guard !seenWindows.contains(minutes) else { continue }

                let lineRange = (text as NSString).lineRange(for: NSRange(location: match.range.location, length: 0))
                let line = (text as NSString).substring(with: lineRange).lowercased()
                let isRemaining = line.contains("remaining") || line.contains("left")
                let usedPercent = isRemaining ? max(0, 100 - percentValue) : percentValue

                let labelOverride = formatLimitLabel(labelString)
                let resetsAt = parseResetTime(from: text, near: match.range.location)

                results.append(CodexLimitWindow(
                    usedPercent: usedPercent,
                    windowMinutes: minutes,
                    labelOverride: labelOverride,
                    resetsAt: resetsAt
                ))
                seenWindows.insert(minutes)
            }
        }

        return results
    }

    private static func formatLimitLabel(_ label: String) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Limit" }
        if trimmed.lowercased().contains("limit") {
            return trimmed
        }
        return "\(trimmed) limit"
    }

    private static func windowMinutes(from label: String) -> Int? {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("hourly") { return 60 }
        if normalized.contains("daily") { return 1440 }
        if normalized.contains("weekly") { return 10080 }

        let pattern = #"(\d+)\s*(h|hr|hrs|hour|hours|d|day|days)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: range),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: normalized),
              let unitRange = Range(match.range(at: 2), in: normalized),
              let value = Int(normalized[numberRange]) else {
            return nil
        }

        let unit = normalized[unitRange]
        if unit.starts(with: "h") {
            return value * 60
        }
        if unit.starts(with: "d") {
            return value * 1440
        }

        return nil
    }

    /// Parse a limit from the output using multiple regex patterns.
    private static func parseLimit(from text: String, patterns: [String], windowMinutes: Int) -> CodexLimitWindow? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }
            
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges > 1,
               let percentRange = Range(match.range(at: 1), in: text),
               let percent = Int(text[percentRange]) {
                
                // Try to find reset time
                let lineRange = (text as NSString).lineRange(for: NSRange(location: match.range.location, length: 0))
                let line = (text as NSString).substring(with: lineRange).lowercased()
                let isRemaining = line.contains("remaining") || line.contains("left")
                let usedPercent = isRemaining ? max(0, 100 - percent) : percent

                let resetsAt = parseResetTime(from: text, near: match.range.location)

                return CodexLimitWindow(
                    usedPercent: usedPercent,
                    windowMinutes: windowMinutes,
                    labelOverride: nil,
                    resetsAt: resetsAt
                )
            }
        }
        return nil
    }
    
    /// Parse a reset time from text like "resets in 12m", "resets 01:22", or "resets 02:44 on 5 Jan".
    private static func parseResetTime(from text: String, near location: Int) -> Date? {
        if let absolute = parseAbsoluteResetTime(from: text) {
            return absolute
        }

        let patterns = [
            #"resets?\s+in\s+(\d+)\s*m(?:in)?"#,
            #"resets?\s+in\s+(\d+)\s*h(?:our)?(?:\s+(\d+)\s*m(?:in)?)?"#,
            #"resets?\s+in\s+(\d+)\s*d(?:ay)?(?:\s+(\d+)\s*h(?:our)?)?"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                var totalSeconds: TimeInterval = 0

                if match.numberOfRanges > 1,
                   let range1 = Range(match.range(at: 1), in: text),
                   let value1 = Int(text[range1]) {

                    if pattern.contains("m(?:in)?") && !pattern.contains("h") {
                        totalSeconds = TimeInterval(value1 * 60)
                    } else if pattern.contains("h(?:our)?") {
                        totalSeconds = TimeInterval(value1 * 3600)
                        if match.numberOfRanges > 2,
                           let range2 = Range(match.range(at: 2), in: text),
                           let value2 = Int(text[range2]) {
                            totalSeconds += TimeInterval(value2 * 60)
                        }
                    } else if pattern.contains("d(?:ay)?") {
                        totalSeconds = TimeInterval(value1 * 86400)
                        if match.numberOfRanges > 2,
                           let range2 = Range(match.range(at: 2), in: text),
                           let value2 = Int(text[range2]) {
                            totalSeconds += TimeInterval(value2 * 3600)
                        }
                    }
                }

                if totalSeconds > 0 {
                    return Date().addingTimeInterval(totalSeconds)
                }
            }
        }

        return nil
    }

    private static func parseAbsoluteResetTime(from text: String) -> Date? {
        let pattern = #"resets\s+(\d{1,2}:\d{2})(?:\s+on\s+(\d{1,2}\s+[A-Za-z]{3}))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let timeRange = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let timeString = String(text[timeRange])
        let dateString: String? = {
            if match.numberOfRanges > 2,
               let dateRange = Range(match.range(at: 2), in: text) {
                return String(text[dateRange])
            }
            return nil
        }()

        let calendar = Calendar.current
        let now = Date()
        let timeParts = timeString.split(separator: ":")
        guard timeParts.count == 2,
              let hour = Int(timeParts[0]),
              let minute = Int(timeParts[1]) else {
            return nil
        }

        if let dateString {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM yyyy HH:mm"
            let year = calendar.component(.year, from: now)
            let composite = "\(dateString) \(year) \(timeString)"
            if let parsed = formatter.date(from: composite) {
                return parsed
            }
        }

        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0

        if let candidate = calendar.date(from: components) {
            if candidate >= now {
                return candidate
            }
            return calendar.date(byAdding: .day, value: 1, to: candidate)
        }

        return nil
    }
}
