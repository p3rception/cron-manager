# Changelog

## Unreleased

- List user LaunchAgents and crontab jobs with load state, PID and last exit code
- Load, unload, run now, edit, create and delete LaunchAgents
- Enable, disable, run now, edit, create and delete cron jobs
- Show the tail of a LaunchAgent's stdout and stderr logs
- Pick schedules from a Repeat menu (interval, hourly, daily, weekly, monthly, at login) instead of cron syntax
- Run daily, weekly and monthly jobs at several times a day; existing cron jobs such as `0 0,12 * * *` open in the simple editor
- New LaunchAgents need only a name and a command; label and log path are filled in
- Show the app that owns each job, with Open and Show in Finder buttons, and flag jobs whose app is gone
- New LaunchAgents are loaded and selected after saving
- Logs update live, so Run Now output shows up
- Flag jobs that need attention (missing program, script or log folder, empty plist, failed last run) and filter the list to them
- Explain exit codes in plain words, such as 78 configuration error
- Show next run, last output and runs since loaded
- Search jobs by label, owner or command
- Set a LaunchAgent's working folder and environment variables, with a button that adds Homebrew to PATH
- Save a cron job's output to a log file and view it live
- Run Now for cron jobs shows the output live, with the exit status and a Stop button
- Duplicate a job from the new More menu
- Restore the previous version of a plist or the crontab; restoring again switches back
- Convert a cron job to a LaunchAgent; the cron line is disabled, not deleted
- View the raw plist or crontab, with a Copy button
- Install with `make` into /Applications so Spotlight finds the app
