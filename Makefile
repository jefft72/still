.PHONY: build test test-install lint format check app install run clean

build:
	swift build

test:
	swift test

test-install:
	./scripts/test-install.sh

lint:
	swift format lint --strict --recursive Sources Tests scripts/GenerateIcon.swift Package.swift
	@for script in scripts/*.sh; do bash -n "$$script" || exit; done

format:
	swift format format --in-place --recursive Sources Tests scripts/GenerateIcon.swift Package.swift

check: lint test build

app:
	./scripts/build-app.sh

install: app
	./scripts/install.sh

run: app
	open dist/Still.app

clean:
	swift package clean
	rm -rf dist
