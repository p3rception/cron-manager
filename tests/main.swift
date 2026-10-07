// Parser checks, run with ./tests/run.sh. Swift Testing does not load under
// Command Line Tools alone (lib_TestingInterop.dylib is missing), so this is
// a plain executable.
import Foundation

// Next run
let cal = Calendar.current
let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 7, hour: 10, minute: 7))!  // a Wednesday
func at(_ d: Date?) -> DateComponents { cal.dateComponents([.year, .month, .day, .hour, .minute], from: d!) }
let job = CronJob(id: 0, line: "0 0,12 * * *   /bin/echo  'a  b'")!
assert(job.schedule == "0 0,12 * * *")
assert(job.command == "/bin/echo  'a  b'")
assert(job.enabled)
assert(job.line == "0 0,12 * * * /bin/echo  'a  b'")

let off = CronJob(id: 1, line: "#off @daily echo hi")!
assert(!off.enabled && off.schedule == "@daily" && off.line == "#off @daily echo hi")

assert(CronJob(id: 2, line: "# a comment") == nil)
assert(CronJob(id: 3, line: "PATH=/usr/bin:/bin") == nil)
assert(CronJob(id: 4, line: "MAILTO=a b c d e f") == nil)
assert(CronJob(id: 5, line: "") == nil)
assert(CronJob(id: 6, line: "0 0 * *") == nil)
assert(!CronJob(id: 7, schedule: "0 0 * *", command: "x").hasValidShape)

// Schedule: cron round trips and launchd keys
for expr in ["*/15 * * * *", "* * * * *", "5 * * * *", "0 */2 * * *", "30 9 * * *", "0 9 * * 1,2,3,4,5", "0 18 1 * *", "@reboot"] {
    let s = Schedule(cron: expr)
    assert(s.kind != .custom, expr)
    assert(s.cronExpression == expr, "\(expr) -> \(s.cronExpression)")
}
assert(Schedule(cron: "0 9 * * 1-5").weekdays == [1, 2, 3, 4, 5])
assert(Schedule(cron: "0 9 * * 7").weekdays == [0])
let twice = Schedule(cron: "0 0,12 * * *")
assert(twice.kind == .daily && twice.times.map(\.text) == ["00:00", "12:00"] && twice.cronExpression == "0 0,12 * * *")
assert(twice.summary(login: "") == "every day at 00:00 and 12:00")
assert(at(twice.nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 7, hour: 12, minute: 0))
assert(Schedule(cron: "0 9-11 * * 1-5").times.count == 3)
assert(Schedule(cron: "0,20,40 * * * *").kind == .interval && Schedule(cron: "0,20,40 * * * *").every == 20)
assert(Schedule(cron: "0,30 9 * * *").kind == .custom)
var mixed = twice
mixed.times = [.init(hour: 9, minute: 0), .init(hour: 17, minute: 30)]
assert(mixed.cronProblem != nil && twice.cronProblem == nil)
var twicePlist: [String: Any] = [:]
mixed.apply(to: &twicePlist)
assert((twicePlist["StartCalendarInterval"] as? [[String: Int]])?.count == 2)
assert(Schedule(plist: twicePlist).times == mixed.times)
var weeklyTwice = Schedule(cron: "0 9,17 * * 1,3")
var wtPlist: [String: Any] = [:]
weeklyTwice.apply(to: &wtPlist)
assert((wtPlist["StartCalendarInterval"] as? [[String: Int]])?.count == 4)
let wtBack = Schedule(plist: wtPlist)
assert(wtBack.kind == .weekly && wtBack.weekdays == [1, 3] && wtBack.times.count == 2)
weeklyTwice.times = [.init(hour: 17, minute: 0), .init(hour: 9, minute: 0), .init(hour: 9, minute: 0)]
assert(weeklyTwice.cronExpression == "0 9,17 * * 1,3")
assert(Schedule(cron: "*/7 * * * *").kind == .custom)
assert(Schedule(cron: "75 * * * *").kind == .custom)
assert(Schedule(cron: "@daily").cronExpression == "0 0 * * *")
assert(Schedule(cron: "0 9 * * 1-5").summary(login: "") == "weekdays at 09:00")

var weekly = Schedule(cron: "0 9 * * 1,3")
var plist: [String: Any] = ["Label": "x", "KeepAlive": true]
weekly.apply(to: &plist)
assert(plist["KeepAlive"] as? Bool == true)
let back = Schedule(plist: plist.filter { $0.key != "KeepAlive" })
assert(back.kind == .weekly && back.weekdays == [1, 3] && back.times == [.init(hour: 9, minute: 0)])
assert(Schedule(plist: ["StartInterval": 3600]).kind == .interval)
assert(Schedule(plist: ["StartInterval": 3600]).unit == .hours)
assert(Schedule(plist: ["StartInterval": 45]).kind == .custom)
assert(Schedule(plist: ["StartCalendarInterval": ["Hour": 2]]).kind == .custom)
assert(Schedule(plist: ["StartCalendarInterval": ["Day": 1, "Hour": 18, "Minute": 0]]).kind == .monthly)
assert(Schedule(plist: ["RunAtLoad": true]).kind == .atLogin)
assert(Schedule(plist: ["RunAtLoad": true, "KeepAlive": true]).kind == .custom)
var custom = Schedule(plist: ["KeepAlive": true])
var kept: [String: Any] = ["StartInterval": 99]
custom.apply(to: &kept)
assert(kept["StartInterval"] as? Int == 99)

// Command lines and argument lists
assert(shellQuote("/a b/c") == "'/a b/c'")
assert(shellQuote("it's") == #"'it'\''s'"#)
assert(commandLine(["/bin/zsh", "-c", "echo hi > /tmp/x"]) == "echo hi > /tmp/x")
assert(commandLine(["/Applications/A B.app/x", "--flag"]) == "'/Applications/A B.app/x' --flag")
let kp = ["/Applications/KeePassXC.app/Contents/MacOS/KeePassXC"]
assert(argumentList(commandLine(kp), original: kp) == kp)
assert(argumentList("/usr/bin/true --x", original: nil) == ["/usr/bin/true", "--x"])
assert(argumentList("echo hi | wc", original: nil) == ["/bin/zsh", "-c", "echo hi | wc"])
assert(argumentList("~/bin/x", original: nil) == ["/bin/zsh", "-c", "~/bin/x"])
assert(argumentList("echo 2", original: ["/bin/bash", "-c", "echo 1"]) == ["/bin/bash", "-c", "echo 2"])
assert(slugify("Καθημερινό backup!") == "kathemerino-backup", slugify("Καθημερινό backup!"))
assert(slugify("  Daily  Backup ") == "daily-backup")

assert(at(Schedule(cron: "*/15 * * * *").nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 7, hour: 10, minute: 15))
assert(at(Schedule(cron: "0 */6 * * *").nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 7, hour: 12, minute: 0))
assert(at(Schedule(cron: "30 9 * * *").nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 8, hour: 9, minute: 30))
assert(at(Schedule(cron: "0 9 * * 1,5").nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 9, hour: 9, minute: 0))
assert(at(Schedule(cron: "0 8 31 * *").nextRun(after: wed, clockAligned: true)) == DateComponents(year: 2026, month: 10, day: 31, hour: 8, minute: 0))
assert(Schedule(plist: ["StartInterval": 900]).nextRun(after: wed, clockAligned: false) == nil)
assert(Schedule(cron: "@reboot").nextRun(clockAligned: true) == nil)

// Exit codes and program checks
assert(exitMeaning(78) == "configuration error")
assert(exitMeaning(0) == "success")
assert(exitMeaning(-9) == "killed")
assert(exitMeaning(137) == "killed")
assert(programProblems(["/no/such/tool"]).map(\.title) == ["Program not found"])
assert(programProblems(["/opt/homebrew/opt/nope/bin/nope"]).first!.hint.contains("brew install nope"))
assert(programProblems(["/bin/bash", "/no/such.sh"]).map(\.title) == ["Script not found"])
assert(programProblems(["/bin/zsh", "-c", "/no/such.sh --x"]).map(\.title) == ["Program not found"])
assert(programProblems(["/bin/zsh", "-c", "echo hi"]).isEmpty)
assert(programProblems(["/etc/hosts"]).map(\.title) == ["Program is not executable"])
assert(CronJob(id: 0, line: "0 0 * * * /no/such.sh")!.problems.count == 1)
assert(CronJob(id: 0, line: "#off 0 0 * * * /no/such.sh")!.problems.isEmpty)

// Cron log redirects
let logged = CronJob(id: 0, line: "0 0 * * * /a/b.sh --x >> '/Users/per/Library/Logs/my log.log' 2>&1")!
assert(logged.baseCommand == "/a/b.sh --x" && logged.logPath == "/Users/per/Library/Logs/my log.log")
assert(CronJob.command(logged.baseCommand, log: logged.logPath) == "/a/b.sh --x >> '/Users/per/Library/Logs/my log.log' 2>&1")
assert(CronJob(id: 0, line: "0 0 * * * /a/b.sh >>/tmp/x.log 2>&1")!.logPath == "/tmp/x.log")
assert(CronJob(id: 0, line: "0 0 * * * /a/b.sh > /tmp/x.log")!.logPath == nil)
assert(CronJob.command("/a/b.sh", log: nil) == "/a/b.sh")

// Convert cron to LaunchAgent, and copies
let paperless = CronJob(id: 0, line: "0 0,12 * * * /Users/per/Docker/paperless-ngx/paperless-updater.sh >> /tmp/p.log 2>&1")!
let converted = Agent(converting: paperless)!
assert(converted.label == "com.\(NSUserName()).paperless-updater")
assert(converted.arguments == ["/Users/per/Docker/paperless-ngx/paperless-updater.sh"])
assert(Schedule(plist: converted.plist).times.map(\.text) == ["00:00", "12:00"])
assert(converted.plist["StandardOutPath"] as? String == "/tmp/p.log")
assert(Agent(converting: CronJob(id: 0, line: "0 9 * * * cd /tmp && ls")!)!.arguments == ["/bin/sh", "-c", "cd /tmp && ls"])
assert(Agent(converting: CronJob(id: 0, line: "@reboot /usr/bin/true")!)!.plist["RunAtLoad"] as? Bool == true)
assert(Agent(converting: CronJob(id: 0, line: "*/7 * * * * /usr/bin/true")!) == nil)
let copied = converted.copy
assert(copied.label == converted.label + "-copy" && (copied.plist["StandardOutPath"] as? String)?.hasSuffix("paperless-updater-copy.log") == true)
print("ok")
