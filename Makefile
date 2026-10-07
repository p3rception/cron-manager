# `make` builds Cron Manager, installs it in /Applications and opens it.
APP := /Applications/CronManager.app

install:
	./build.sh build
	pkill -x CronManager || true
	rm -rf $(APP)
	cp -R dist/CronManager.app $(APP)
	open $(APP)

# Keeps backups in ~/Library/Application Support/CronManager.
uninstall:
	pkill -x CronManager || true
	rm -rf $(APP)

test:
	./tests/run.sh

clean:
	rm -rf .build dist

.PHONY: install uninstall test clean
