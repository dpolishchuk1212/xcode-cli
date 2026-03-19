# pi-xcode

Xcode extension for the [pi coding agent](https://github.com/badlogic/pi-mono). Provides Xcode build and run tools directly inside pi.

## Install

```bash
# From git (recommended during development)
pi install git:github.com/nicklama/xcode-cli

# From npm (once published)
pi install npm:pi-xcode
```

## Quick test (without installing)

```bash
pi -e git:github.com/nicklama/xcode-cli
# or locally:
pi -e ./pi-xcode
```

## Tools

### xcode_build

Build an Xcode project or workspace. Auto-discovers project, workspace, and scheme when not specified. Returns parsed build errors/warnings in a compact format.

| Parameter       | Description                                                        |
|-----------------|--------------------------------------------------------------------|
| `project`       | Path to `.xcodeproj` (optional, auto-discovered)                   |
| `workspace`     | Path to `.xcworkspace` (optional, auto-discovered)                 |
| `scheme`        | Build scheme (optional, auto-discovered)                           |
| `configuration` | `Debug` or `Release` (default: `Debug`)                            |
| `destination`   | Build destination, e.g. `platform=iOS Simulator,name=iPhone 16`    |
| `filter`        | Output filter: `all`, `issues`, `errors` (default: `errors`)       |

## Development

```bash
cd pi-xcode

# Test the extension locally
pi -e ./src/index.ts
```

## License

MIT
