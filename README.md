# xcode-cli

Token-efficient Xcode CLI designed for coding agents (pi-coding-agent, etc).

Only shows what matters: errors, warnings, and a one-line summary.

## Install

```bash
swift build -c release
cp .build/release/xcode-cli /usr/local/bin/
```

## Usage

```bash
# Auto-discovers workspace/project/scheme in current directory
xcode-cli build

# Explicit options
xcode-cli build --workspace MyApp.xcworkspace --scheme MyApp
xcode-cli build --project MyApp.xcodeproj --scheme MyApp -c Release
xcode-cli build --destination 'platform=iOS Simulator,name=iPhone 16'

# Full xcodebuild output
xcode-cli build --verbose
```

## Output examples

```
Building MyApp (Debug)...
✓ Build Succeeded [4.2s]
```

```
Building MyApp (Debug)...
✗ Build Failed (2 errors, 1 warning) [3.1s]

Errors:
  ContentView.swift:15:10: cannot convert value of type 'String' to specified type 'Int'
  Model.swift:23:5: cannot find 'undefinedVar' in scope

Warnings:
  Helper.swift:8:2: consider using a struct here
```
