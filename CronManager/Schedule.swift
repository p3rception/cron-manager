import Foundation

/// A schedule the editor can show without cron syntax. Converts to and from
/// a cron expression and launchd's StartInterval / StartCalendarInterval keys.
/// Anything it cannot represent is `.custom` and is written back unchanged.
struct Schedule: Equatable {
    enum Kind: CaseIterable {
        case interval, hourly, daily, weekly, monthly, atLogin, custom
    }
    enum Unit: String, CaseIterable { case minutes, hours }

    struct Time: Hashable, Comparable {
        var hour: Int
        var minute: Int
        static func < (a: Time, b: Time) -> Bool { (a.hour, a.minute) < (b.hour, b.minute) }
        var text: String { String(format: "%02d:%02d", hour, minute) }
    }

    var kind = Kind.daily
    var every = 15
    var unit = Unit.minutes
    /// The minute past the hour for `.hourly`.
    var minute = 0
    /// Run times for `.daily`, `.weekly` and `.monthly`, at least one. Kept
    /// in editing order; conversions use `runTimes`.
    var times = [Time(hour: 9, minute: 0)]
    private var runTimes: [Time] { Set(times).sorted() }
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
        let midnight = [Time(hour: 0, minute: 0)]
        switch expression {
        case "@hourly": kind = .hourly; minute = 0; return
        case "@daily", "@midnight": kind = .daily; times = midnight; return
        case "@weekly": kind = .weekly; weekdays = [0]; times = midnight; return
        case "@monthly": kind = .monthly; day = 1; times = midnight; return
        case "@reboot": kind = .atLogin; return
        default: break
        }
        kind = .custom
        custom = expression
        let f = expression.split(whereSeparator: \.isWhitespace).map(String.init)
        guard f.count == 5, f[3] == "*" else { return }
        let (dom, dow) = (f[2], f[4])

        if f[1...] == ["*", "*", "*", "*"] {
            if f[0] == "*" { set(.interval, every: 1, .minutes) }
            else if let n = step(f[0]) ?? evenStep(f[0]), Self.choices[.minutes]!.contains(n) { set(.interval, every: n, .minutes) }
            else if let m = Int(f[0]), (0..<60).contains(m) { kind = .hourly; minute = m }
        } else if f[0] == "0", dom == "*", dow == "*", let n = step(f[1]), Self.choices[.hours]!.contains(n) {
            set(.interval, every: n, .hours)
        } else if let m = Int(f[0]), (0..<60).contains(m), let hours = Self.parseList(f[1], 0...23) {
            // One minute with several hours is how cron runs at several times a day.
            if dom == "*", dow == "*" { kind = .daily }
            else if dom == "*", let days = Self.parseList(dow, 0...7) { kind = .weekly; weekdays = Set(days.map { $0 % 7 }) }
            else if dow == "*", let d = Int(dom), (1...31).contains(d) { kind = .monthly; day = d }
            else { return }
            times = hours.sorted().map { Time(hour: $0, minute: m) }
        }
    }

    /// Set when the schedule cannot be one cron line.
    var cronProblem: String? {
        guard [.daily, .weekly, .monthly].contains(kind), Set(times.map(\.minute)).count > 1 else { return nil }
        return "A cron job can only run at several times when they share the minutes, such as 09:00 and 17:00. Use the same minutes, or make separate jobs."
    }

    var cronExpression: String {
        let at = "\(runTimes[0].minute) \(runTimes.map { String($0.hour) }.joined(separator: ","))"
        switch kind {
        case .interval:
            if unit == .minutes { return every == 1 ? "* * * * *" : "*/\(every) * * * *" }
            return every == 1 ? "0 * * * *" : "0 */\(every) * * *"
        case .hourly: return "\(minute) * * * *"
        case .daily: return "\(at) * * *"
        case .weekly: return "\(at) * * \(weekdays.sorted().map(String.init).joined(separator: ","))"
        case .monthly: return "\(at) \(day) * *"
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
            guard dicts.allSatisfy({ Set($0.keys) == keys }), keys.contains("Minute") else { return }
            let found = Set(dicts.map { Time(hour: $0["Hour"] ?? 0, minute: $0["Minute"]!) })
            let days = Set(dicts.compactMap { $0["Weekday"].map { $0 % 7 } })
            let monthDays = Set(dicts.compactMap { $0["Day"] })
            switch keys {
            case ["Minute"] where dicts.count == 1: kind = .hourly; minute = found.first!.minute
            case ["Minute", "Hour"]: kind = .daily
            // Several days and times are written as every day with every time,
            // so only that full grid can be shown.
            case ["Minute", "Hour", "Weekday"] where dicts.count == days.count * found.count: kind = .weekly; weekdays = days
            case ["Minute", "Hour", "Day"] where monthDays.count == 1: kind = .monthly; day = monthDays.first!
            default: return
            }
            times = found.sorted()
        } else if calendar == nil, p["StartInterval"] == nil, !other, p["RunAtLoad"] as? Bool == true {
            kind = .atLogin
        }
    }

    /// Replaces the schedule keys. `.custom` leaves them as they are.
    func apply(to p: inout [String: Any]) {
        guard kind != .custom else { return }
        p["StartInterval"] = nil
        p["StartCalendarInterval"] = nil
        func entries(_ extra: [String: Int]) -> Any {
            let list = runTimes.map { extra.merging(["Hour": $0.hour, "Minute": $0.minute]) { a, _ in a } }
            return list.count == 1 ? list[0] : list
        }
        switch kind {
        case .interval: p["StartInterval"] = every * (unit == .minutes ? 60 : 3600)
        case .hourly: p["StartCalendarInterval"] = ["Minute": minute]
        case .daily: p["StartCalendarInterval"] = entries([:])
        case .weekly:
            p["StartCalendarInterval"] = weekdays.sorted().flatMap { day in
                runTimes.map { ["Weekday": day, "Hour": $0.hour, "Minute": $0.minute] }
            }
        case .monthly: p["StartCalendarInterval"] = entries(["Day": day])
        case .atLogin: p["RunAtLoad"] = true
        case .custom: break
        }
    }

    // MARK: next run

    /// The next time this schedule fires. nil for login, custom and launchd
    /// intervals, which count from when the job was loaded, not from the clock.
    func nextRun(after date: Date = .now, clockAligned: Bool) -> Date? {
        let calendar = Calendar.current
        func next(_ c: DateComponents, policy: Calendar.MatchingPolicy = .nextTime) -> Date? {
            calendar.nextDate(after: date, matching: c, matchingPolicy: policy)
        }
        switch kind {
        case .interval:
            guard clockAligned else { return nil }
            // cron's */N fires on minutes (or hours) divisible by N.
            let component: Calendar.Component = unit == .minutes ? .minute : .hour
            guard var t = calendar.dateInterval(of: component, for: date)?.end else { return nil }
            while calendar.component(component, from: t) % every != 0 {
                t = calendar.date(byAdding: component, value: 1, to: t) ?? t
            }
            return t
        case .hourly: return next(DateComponents(minute: minute))
        case .daily: return times.compactMap { next(DateComponents(hour: $0.hour, minute: $0.minute)) }.min()
        case .weekly:
            return weekdays.flatMap { day in
                times.compactMap { next(DateComponents(hour: $0.hour, minute: $0.minute, weekday: day + 1)) }
            }.min()
        // Strict, so day 31 skips shorter months like cron and launchd do.
        case .monthly:
            return times.compactMap { next(DateComponents(day: day, hour: $0.hour, minute: $0.minute), policy: .strict) }.min()
        case .atLogin, .custom: return nil
        }
    }

    // MARK: text

    /// `login` names the .atLogin case: "at login" for launchd, "at startup" for cron.
    func summary(login: String) -> String {
        let at = Self.join(runTimes.map(\.text))
        switch kind {
        case .interval: return every == 1 ? "every \(unit == .minutes ? "minute" : "hour")" : "every \(every) \(unit.rawValue)"
        case .hourly: return String(format: "every hour at :%02d", minute)
        case .daily: return "every day at \(at)"
        case .weekly: return "\(Self.describe(weekdays)) at \(at)"
        case .monthly: return "on day \(day) of every month at \(at)" + (day > 28 ? ", skipped in shorter months" : "")
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
        default: return join(days.sorted().map { names[$0] })
        }
    }

    /// "a, b and c"
    private static func join(_ items: [String]) -> String {
        items.count < 2 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
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

    /// N from an evenly spaced minute list starting at 0, such as "0,20,40".
    private func evenStep(_ field: String) -> Int? {
        guard let minutes = Self.parseList(field, 0...59)?.sorted(), minutes.count > 1, minutes[0] == 0 else { return nil }
        let n = minutes[1]
        return minutes == Array(stride(from: 0, to: 60, by: n)) ? n : nil
    }

    /// Lists and ranges such as "1-5" or "0,12".
    static func parseList(_ field: String, _ range: ClosedRange<Int>) -> Set<Int>? {
        var values: Set<Int> = []
        for part in field.split(separator: ",") {
            let ends = part.split(separator: "-").compactMap { Int($0) }
            guard ends.count == part.split(separator: "-").count, (1...2).contains(ends.count),
                  ends.allSatisfy(range.contains), ends[0] <= ends.last! else { return nil }
            values.formUnion(ends[0]...ends.last!)
        }
        return values.isEmpty ? nil : values
    }
}
