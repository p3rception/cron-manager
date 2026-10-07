// Parser check, run with ./tests/run.sh. Swift Testing does not load under
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
print("ok")
