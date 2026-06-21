# TokenBar

TokenBar is a macOS menu bar app for tracking coding-agent token usage.

It reads local usage logs from tools such as Codex and Claude Code, summarizes token activity in a compact glass-style popover, and can show the current usage number directly next to the menu bar icon.

## Features

- Menu bar usage summary with Today and All time totals.
- Token breakdown for input, cache read, output, and estimated AIU.
- Collapsible Models and Agents sections.
- Auto Detect data source mode for supported local coding agents.
- Manual data source selection for custom JSONL files or directories.
- Settings menu for appearance, launch at login, data source, usage number display, and About.
- macOS native About panel and app icon support.

## Data Sources

TokenBar supports two data source modes:

- Auto Detect: reads supported local agent logs, currently Codex sessions and Claude Code projects.
- Manual: lets you choose a JSONL file or directory yourself.

Auto Detect intentionally reads agent logs directly. If you use a proxy such as `codex-copilot-dx`, keep it as a manual data source only when you specifically want to inspect that proxy log; otherwise proxy logs can double-count traffic that is already present in agent logs.

## Build

Requirements:

- macOS 14 or newer
- Swift 5.9 or newer

Build from source:

```sh
swift build
```

Build, install to `/Applications/TokenBar.app`, and launch:

```sh
./script/build_and_run.sh --verify
```

The build script creates a normal `.app` bundle, copies resources, writes `Info.plist`, installs over `/Applications/TokenBar.app`, and increments the local bundle build number after a successful build.

## Development

The SwiftPM executable product is named `TokenBar`.

```sh
swift run TokenBar
```

Generated build output is kept out of git via `.gitignore`.

## License

TokenBar is licensed under the Apache License 2.0. See [LICENSE](LICENSE).
