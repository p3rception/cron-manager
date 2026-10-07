# Changelog

## Unreleased

- List user LaunchAgents and crontab jobs with load state, PID and last exit code
- Load, unload, run now, edit, create and delete LaunchAgents
- Enable, disable, run now, edit, create and delete cron jobs
- Show the tail of a LaunchAgent's stdout and stderr logs
- Pick schedules from a Repeat menu (interval, hourly, daily, weekly, monthly, at login) instead of cron syntax
- New LaunchAgents need only a name and a command; label and log path are filled in
- Install with `make` into /Applications so Spotlight finds the app
