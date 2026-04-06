<div align="center">

# Ai-land

**An AI CLI companion for macOS**

[简体中文](README.md) · **English**

[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-15.5%2B-000000?logo=apple&logoColor=white)](https://developer.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Xcode](https://img.shields.io/badge/Xcode-SwiftUI-007ACC?logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)

<br/>

</div>

> A Dynamic-Island-style floating strip for CLI tasks, review prompts, and completion status, wired to coding agents (Claude Code, Codex, Gemini CLI, and more) via hooks and local channels.

## Overview

**Ai-land** is a native Swift / SwiftUI app whose window sits at the screen edge: collapsed, it shows a compact status strip; expanded, you get the task list, agent-driven confirmation choices, and custom URL handoffs to external tools.


## Features

- **Task island**: in-progress / pending / completed tasks from terminal agents, with previews and jumps to related workspace windows.
- **Interaction panel**: grouped “ask” options (e.g. allow / deny tool use), aligned with island shortcuts and list behavior.
- **Zodiac compact mode**: optional twelve-animal pixel-style micro-animations when collapsed (configurable in settings).
- **Multiple agents**: detects and configures hooks for several CLIs; Settings shows status and quick hook install.
- **Sound & localization**: bundled cue sounds; UI in Simplified Chinese and English (`zh-Hans` / `en`).

## Supported AI CLIs / agents

| Display name        | Executable | Hooks directory (example) |
|---------------------|------------|---------------------------|
| Claude Code         | `claude`   | `~/.claude/hooks`         |
| OpenAI Codex CLI    | `codex`    | `~/.codex/hooks`          |
| Google Gemini CLI   | `gemini`   | `~/.gemini/hooks`         |
| Cursor Agent        | `cursor`   | `~/.cursor/hooks`         |
| OpenCode            | `opencode` | `~/.opencode/hooks`       |
| Factory Droid       | `droid`    | `~/.droid/hooks`          |

Exact paths and install flow follow `ConfigurationManager` and the Settings UI.

## Requirements

- **macOS 15.5** or later (per Xcode `MACOSX_DEPLOYMENT_TARGET`)
- **Xcode** (current stable recommended) to build from source

## Build & run from source

1. Clone the repo:
   ```bash
   git clone https://github.com/oyyxmmd/Ai-land.git
   cd Ai-land
   ```
2. Open **`Ai_land.xcodeproj`** in Xcode.
3. Select Scheme **`Ai_land`**, destination **My Mac**, then Run (⌘R).

On first launch, macOS may prompt for **Automation / Apple Events** (and related) access for window and terminal integration; see the usage string in `Info.plist`.

## URL scheme (deep links)

The app registers:

- `ai-land://…`
- `code-island://…` (legacy alias)

Parameter handling is implemented in `AiLandURLRouting` and related code.

The `assistant` query key is the CLI executable name (lowercase), e.g. `claude`, `codex`, `gemini`, `cursor`, **`opencode`**, `droid`. Display names and aliases (e.g. `OpenCode`, `open-code`) are normalized internally.

Example (OpenCode task running):

```text
open -g "ai-land://task?assistant=opencode&state=running&task_id=demo&title=Demo"
```

## Repository layout

```
Ai_land/           # Main app (SwiftUI, island UI, tasks & interaction logic)
Ai_landTests/      # Unit tests
Ai_landUITests/    # UI tests
Ai_land.xcodeproj/ # Xcode project
music/             # Sound assets
docs/              # Design / planning notes (e.g. superpowers)
Info.plist         # Extra Info.plist used with the project
```

## License

This project is released under the **Apache License 2.0**—see [`LICENSE`](LICENSE) in the repo root.

## Links

- Source & issues: <https://github.com/oyyxmmd/Ai-land>

## Contributing

We’re not full-time pros here—bugs happen; please open **issues** and PRs. Forks and improvements are welcome.

## Screenshots

![Preview 4](images/预览4.png)

![Preview 1](images/预览1.png)

![Preview 2](images/预览2.png)

![Preview 3](images/预览3.png)

---

<p align="center"><a href="README.md">简体中文</a> · <b>English</b></p>
