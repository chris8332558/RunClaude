# RunClaude

A macOS menu bar app that animates a sprite character at a speed proportional to your live **Claude Code** token usage. Inspired by [RunCat](https://apps.apple.com/us/app/runcat/id1429033973?mt=12).

When Claude Code is actively streaming tokens, the character sprints. When idle, it stands still with a gentle breathing animation. Click the icon to see today's usage stats, cost estimate, and model breakdown.

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (or Swift 5.9+ toolchain)
- Claude Code installed (the app reads its JSONL log files)

## Quick Start

### Option A: Build script (recommended)

```bash
cd RunClaude
./Scripts/make-app.sh

# Run it
open build/RunClaude.app

# Or install to Applications
cp -r build/RunClaude.app /Applications/
```

### Option B: Swift Package Manager

```bash
cd RunClaude
swift build
.build/debug/RunClaude
```

> Note: Running via SwiftPM works for development but won't hide the Dock icon
> (that requires the .app bundle with Info.plist's LSUIElement flag).

### Option C: Open in Xcode

```bash
cd RunClaude
open Package.swift
```

Then press Cmd+R to build and run.

## How It Works

1. **Watches** Claude Code's JSONL log files in `~/.claude/projects/`
2. **Parses** new lines as they're appended during active sessions
3. **Computes** a token velocity (tokens/second) over a sliding window
4. **Animates** a sprite in the menu bar — faster velocity = faster animation

The app uses zero external dependencies. Everything is built on Apple frameworks:
Foundation, AppKit, SwiftUI, Swift Charts, CoreServices.

## Menu Bar Features

- **Left-click**: Opens a popover with usage stats
  - Today's token counts (input, output, cache)
  - Estimated cost (USD)
  - Model breakdown (Opus/Sonnet/Haiku)
  - Activity sparkline
- **Right-click**: Context menu with quick stats + Quit
- **Tooltip**: Hover to see current speed tier and cost

## Project Structure

```
Sources/RunClaude/
├── main.swift              # Entry point
├── AppDelegate.swift       # App lifecycle
├── Engine/
│   ├── Models.swift        # Data types
│   ├── JSONLParser.swift   # JSONL log parser
│   ├── LogFileWatcher.swift # File system monitoring
│   ├── TokenAggregator.swift # Sliding window + daily stats
│   ├── CostCalculator.swift # Model pricing
│   └── TokenUsageEngine.swift # Orchestrator
├── MenuBar/
│   ├── MenuBarController.swift # NSStatusItem management
│   ├── SpriteAnimator.swift    # Frame cycling
│   ├── SpriteGenerator.swift   # Procedural sprite drawing
│   └── SpeedMapper.swift       # tok/s → animation speed
└── Views/
    ├── UsagePopoverView.swift  # Stats popover (SwiftUI)
    └── SettingsView.swift      # Preferences (SwiftUI)
```

## Testing with Sample Data

To test without active Claude Code usage, use the included test data generator:

```bash
swift Scripts/generate-test-data.swift
```

This creates sample JSONL files in `~/.claude/projects/_runclaude_test/` that simulate
a Claude Code session with varying token activity.

## Roadmap

- [x] Phase 1: Menu bar animation driven by real token data
- [x] Phase 2: Popover with usage stats, cost, model breakdown
- [ ] Phase 3: Custom sprite art, smooth transitions, launch-at-login
- [ ] Phase 4: Multiple sprite packs, cost alerts, Homebrew distribution

## License

MIT
