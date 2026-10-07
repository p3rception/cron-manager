# cron-manager

GUI to manage cron and launchd jobs

## Rules

- Always commit your changes when a task is done: one commit per logical change, with a short imperative subject line. Never push.

## Commands

- `./build.sh` builds dist/CronManager.app and launches it (`./build.sh build` skips launch)
- `./tests/run.sh` runs the crontab parser check

## Notes

- Command Line Tools only, no Xcode. Swift Testing does not load under CLT, so tests are plain `assert` executables built with swiftc.
- Backups of edited plists and the crontab go to ~/Library/Application Support/CronManager, never ~/Library/LaunchAgents (launchd would load them).
- Disabled cron jobs are stored as `#off <line>` in the crontab.
