import Foundation

/// A schedule the editor can show without cron syntax. Converts to and from
/// a cron expression and launchd's StartInterval / StartCalendarInterval keys.
/// Anything it cannot represent is `.custom` and is written back unchanged.
struct Schedule: Equatable {
    enum Kind: CaseIterable {
        case interval, hourly, daily, weekly, monthly, atLogin, custom
    }
    enum Unit: String, CaseIterable { case minutes, hours }

    var kind = Kind.daily
    var every = 15
    var unit = Unit.minutes
    var hour = 9
    var minute = 0
    /// 0 is Sunday, as in both cron and launchd.
    var weekdays: Set<Int> = [1, 2, 3, 4, 5]
    var day = 1
    /// The cron expression, or for launchd a description of the kept keys.
    var custom = ""

    /// Cron restarts a `*/N` count every hour (or day), so only divisors give
    /// evenly spaced runs. launchd uses the same choices to keep one editor.
    static let choices: [Unit: [Int]] = [.minutes: [1, 2, 3, 5, 10, 15, 20, 30], .hours: [1, 2, 3, 4, 6, 8, 12]]

    // MARK: cron

    init() {}

    init(cron expression: String) {
        switch expression {
        case "@hourly": kind = .hourly; minute = 0; return
        case "@daily", "@midnight": kind = .daily; hour = 0; minute = 0; return
        case "@weekly": kind = .weekly; weekdays = [0]; hour = 0; minute = 0; return
        case "@monthly": kind = .monthly; day = 1; hour = 0; minute = 0; return
        case "@reboot": kind = .atLogin; return
        default: break
        }
        kind = .custom
        custom = expression
        let f = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard f.count == 5, f[3] == "*" else { return }
        let (m, h, dom, dow) = (Int(f[0]), Int(f[1]), f[2], f[4])

        if f[1...] == ["*", "*", "*", "*"] {
            if f[0] == "*" { set(.interval, every: 1, .minutes) }
            else if let n = step(f[0]), Self.choices[.minutes]!.contains(n) { set(.interval, every: n, .minutes) }
            else if let m, (0..<60).contains(m) { kind = .hourly; minute = m }
        } else if f[0] == "0", dom == "*", dow == "*", let n = step(f[1]), Self.choices[.hours]!.contains(n) {
            set(.interval, every: n, .hours)
        } else if let m, let h, (0..<60).contains(m), (0..<24).contains(h) {
            if dom == "*", dow == "*" { kind = .daily }
            else if dom == "*", let days = Self.parseDays(dow) { kind = .weekly; weekdays = days }
            else if dow == "*", let d = Int(dom), (1...31).contains(d) { kind = .monthly; day = d }
            else { return }
            hour = h
            minute = m
        }
    }

    var cronExpression: String {
        switch kind {
        case .interval:
            if unit == .minutes { return every == 1 ? "* * * * *" : "*/\(every) * * * *" }
            return every == 1 ? "0 * * * *" : "0 */\(every) * * *"
        case .hourly: return "\(minute) * * * *"
        case .daily: return "\(minute) \(hour) * * *"
        case .weekly: return "\(minute) \(hour) * * \(weekdays.sorted().map(String.init).joined(separator: ","))"
        case .monthly: return "\(minute) \(hour) \(day) * *"
        case .atLogin: return "@reboot"
        case .custom: return custom.trimmingCharacters(in: .whitespaces)
        }
    }

    // MARK: launchd

    init(plist p: [String: Any]) {
        kind = .custom
        let calendar = p["StartCalendarInterval"]
        let dicts = calendar as? [[String: Int]] ?? (calendar as? [String: Int]).map { [$0] }
        let other = ["KeepAlive", "WatchPaths", "QueueDirectories", "StartOnMount"].contains { p[$0] != nil }

        if let seconds = p["StartInterval"] as? Int, calendar == nil {
            if seconds % 3600 == 0, Self.choices[.hours]!.contains(seconds / 3600) { set(.interval, every: seconds / 3600, .hours) }
            else if seconds % 60 == 0, Self.choices[.minutes]!.contains(seconds / 60) { set(.interval, every: seconds / 60, .minutes) }
        } else if let dicts, !dicts.isEmpty, p["StartInterval"] == nil {
            let keys = Set(dicts[0].keys)
            // A missing Minute means every minute of that hour, so it stays custom.
            guard dicts.allSatisfy({ Set($0.keys) == keys && $0["Hour"] == dicts[0]["Hour"] && $0["Minute"] == dicts[0]["Minute"] }),
                  let m = dicts[0]["Minute"] else { return }
            minute = m
            hour = dicts[0]["Hour"] ?? 0
            switch keys {
            case ["Minute"] where dicts.count == 1: kind = .hourly
            case ["Minute", "Hour"] where dicts.count == 1: kind = .daily
            case ["Minute", "Hour", "Weekday"]: kind = .weekly; weekdays = Set(dicts.compactMap { $0["Weekday"].map { $0 % 7 } })
            case ["Minute", "Hour", "Day"] where dicts.count == 1: kind = .monthly; day = dicts[0]["Day"]!
            default: break
            }
        } else if calendar == nil, p["StartInterval"] == nil, !other, p["RunAtLoad"] as? Bool == true {
            kind = .atLogin
        }
    }

    /// Replaces the schedule keys. `.custom` leaves them as they are.
    func apply(to p: inout [String: Any]) {
        guard kind != .custom else { return }
        p["StartInterval"] = nil
        p["StartCalendarInterval"] = nil
        switch kind {
        case .interval: p["StartInterval"] = every * (unit == .minutes ? 60 : 3600)
        case .hourly: p["StartCalendarInterval"] = ["Minute": minute]
        case .daily: p["StartCalendarInterval"] = ["Hour": hour, "Minute": minute]
        case .weekly: p["StartCalendarInterval"] = weekdays.sorted().map { ["Weekday": $0, "Hour": hour, "Minute": minute] }
        case .monthly: p["StartCalendarInterval"] = ["Day": day, "Hour": hour, "Minute": minute]
        case .atLogin: p["RunAtLoad"] = true
        case .custom: break
        }
    }

    // MARK: text

    /// `login` names the .atLogin case: "at login" for launchd, "at startup" for cron.
    func summary(login: String) -> String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .interval: return every == 1 ? "every \(unit == .minutes ? "minute" : "hour")" : "every \(every) \(unit.rawValue)"
        case .hourly: return String(format: "every hour at :%02d", minute)
        case .daily: return "every day at \(time)"
        case .weekly: return "\(Self.describe(weekdays)) at \(time)"
        case .monthly: return "on day \(day) of every month at \(time)" + (day > 28 ? ", skipped in shorter months" : "")
        case .atLogin: return login
        case .custom: return custom
        }
    }

    static func describe(_ days: Set<Int>) -> String {
        let names = Calendar.current.weekdaySymbols
        switch days {
        case []: return "never"
        case [1, 2, 3, 4, 5]: return "weekdays"
        case [0, 6]: return "weekends"
        case Set(0..<7): return "every day"
        default: return days.sorted().map { names[$0] }.joined(separator: ", ")
        }
    }

    // MARK: helpers

    private mutating func set(_ kind: Kind, every: Int, _ unit: Unit) {
        self.kind = kind
        self.every = every
        self.unit = unit
    }

    /// N from "*/N".
    private func step(_ field: String) -> Int? {
        field.hasPrefix("*/") ? Int(field.dropFirst(2)) : nil
    }

    /// Day-of-week lists such as "1-5" or "1,3,5" (7 is Sunday too).
    static func parseDays(_ field: String) -> Set<Int>? {
        var days: Set<Int> = []
        for part in field.split(separator: ",") {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            guard ends.count == part.split(separator: "-").count, (1...2).contains(ends.count),
                  ends.allSatisfy({ (0...7).contains($0) }), ends[0] <= ends.last! else { return nil }
            days.formUnion((ends[0]...ends.last!).map { $0 % 7 })
        }
        return days.isEmpty ? nil : days
    }
}
