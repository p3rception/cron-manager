#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -o "$out/check" CronManager/Crontab.swift CronManager/Shell.swift tests/main.swift
"$out/check"
