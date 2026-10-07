// Parser checks, run with ./tests/run.sh. Swift Testing does not load under
// Command Line Tools alone (lib_TestingInterop.dylib is missing), so this is
// a plain executable.
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
assert(Schedule(cron: "0 0,12 * * *").kind == .custom)
assert(Schedule(cron: "*/7 * * * *").kind == .custom)
assert(Schedule(cron: "75 * * * *").kind == .custom)
assert(Schedule(cron: "@daily").cronExpression == "0 0 * * *")
assert(Schedule(cron: "0 9 * * 1-5").summary(login: "") == "weekdays at 09:00")

var weekly = Schedule(cron: "0 9 * * 1,3")
var plist: [String: Any] = ["Label": "x", "KeepAlive": true]
weekly.apply(to: &plist)
assert(plist["KeepAlive"] as? Bool == true)
let back = Schedule(plist: plist.filter { $0.key != "KeepAlive" })
assert(back.kind == .weekly && back.weekdays == [1, 3] && back.hour == 9)
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
print("ok")
