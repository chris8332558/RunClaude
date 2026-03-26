# RunClaude Changelog

## [2026-03-26] — Phase 3: Polish, sprites, and launch-at-login

### Changed
- **SpriteGenerator.swift** — Replaced stick-figure sprites with a rounded Claude-inspired bean/capsule character. Body uses `NSBezierPath(roundedRect:)` with squash-and-stretch during run cycle. Face has a cutout eye with sparkle highlight. Idle animation includes a blink at phase ~0.75. Frame count increased (10 run, 6 idle) for smoother motion. Frame width widened from 18pt to 20pt to accommodate the new body shape.
- **SpriteAnimator.swift** — Added deadband threshold (0.005s) to skip timer rescheduling on tiny interval fluctuations; reduced smoothing factor from 0.15 to 0.12 for a more natural ~0.5s ramp time between speed changes.
- **MenuBarController.swift** — Polished context menu: shows capitalized speed tier, token count alongside cost, added "Settings..." menu item (Cmd+,). Settings opens a standalone `NSWindow` hosting `SettingsView`. Tooltip now respects the "showCostInTooltip" user preference.
- **SettingsView.swift** — Wired launch-at-login to `SMAppService.mainApp.register()/unregister()` (macOS 13+) with error handling and toggle revert on failure. Removed placeholder GitHub link, added descriptive subtitle.

### Decisions
- **Bean/capsule character over stick figure** — The rounded shape reads better at 18pt menu bar size and evokes the friendly Claude aesthetic. Template-image rendering preserved so macOS still handles light/dark adaptation automatically.
- **Squash-and-stretch on run cycle** — The body compresses 8% at peak leg extension and widens 2.4% to compensate, following the classic animation principle. This makes the run feel bouncy and alive even at tiny pixel sizes.
- **Deadband on animation timer** — Without this, tiny floating-point drifts in the smoothing calculation caused the timer to be invalidated and rescheduled every frame even at steady state, wasting CPU. The 5ms deadband eliminates this.
- **SMAppService for launch-at-login** — Preferred over the deprecated `LSSharedFileListInsertItemURL` and `SMLoginItemSetEnabled` APIs. Requires the app to be distributed as a proper .app bundle (which `make-app.sh` already produces).

## [2026-03-26] — Initial project scaffold and Phase 1+2 implementation

### Added
- **Package.swift** — SwiftPM manifest targeting macOS 13+, zero external dependencies
- **Sources/RunClaude/main.swift** — App entry point; configures NSApplication as `.accessory` (no Dock icon)
- **Sources/RunClaude/AppDelegate.swift** — Application delegate; wires up TokenUsageEngine and MenuBarController
- **Sources/RunClaude/Engine/Models.swift** — Core data types: `TokenRecord`, `DailyUsage`, `ModelUsage`, `TokenSample`, `UsageState`
- **Sources/RunClaude/Engine/JSONLParser.swift** — Streams Claude Code JSONL logs; extracts token usage from multiple JSON formats with deduplication key generation
- **Sources/RunClaude/Engine/LogFileWatcher.swift** — Monitors `~/.claude/projects/` via GCD `DispatchSource` for near-real-time detection of new log lines; tracks per-file byte offsets
- **Sources/RunClaude/Engine/TokenAggregator.swift** — Sliding-window token velocity (tokens/sec), daily aggregation, 5-minute sparkline buckets
- **Sources/RunClaude/Engine/CostCalculator.swift** — Hardcoded per-model pricing (Opus 4, Sonnet 4, Haiku 3.5, legacy models) with USD cost estimation
- **Sources/RunClaude/Engine/TokenUsageEngine.swift** — Central orchestrator; publishes `@Published var state` combining file watcher, aggregator, and cost calculator
- **Sources/RunClaude/MenuBar/SpeedMapper.swift** — Logarithmic mapping from tokens/sec to animation frame interval (idle → walk → jog → run → sprint)
- **Sources/RunClaude/MenuBar/SpriteGenerator.swift** — Procedural stick-figure sprite drawing (8 run frames, 4 idle frames) as NSImage template images for automatic light/dark mode
- **Sources/RunClaude/MenuBar/SpriteAnimator.swift** — Frame cycling with exponential smoothing between speed transitions
- **Sources/RunClaude/MenuBar/MenuBarController.swift** — NSStatusItem management; left-click popover, right-click context menu, Combine subscription to engine state
- **Sources/RunClaude/Views/UsagePopoverView.swift** — SwiftUI popover: live status indicator, today's token counts, cost estimate, color-coded model breakdown, Swift Charts sparkline
- **Sources/RunClaude/Views/SettingsView.swift** — SwiftUI preferences: custom data path, cost tooltip toggle, launch-at-login toggle (Phase 3 wiring)
- **Resources/Info.plist** — App bundle config with `LSUIElement = true` (menu-bar-only app)
- **Scripts/make-app.sh** — Build script: `swift build` → assembles `.app` bundle → ad-hoc codesign
- **Scripts/generate-test-data.swift** — Test data generator with one-shot and `--live` modes simulating bursty Claude Code sessions
- **README.md** — Project overview, build instructions, architecture diagram, testing guide
- **RunClaude-ProjectPlan.md** — Full project plan covering architecture, phases, tech stack, speed mapping formula, and open questions

### Fixed
- **SettingsView.swift** — Changed `.onChange(of:) { _, newValue in }` (macOS 14+ only) to `.onChange(of:) { newValue in }` for macOS 13 compatibility

### Decisions
- **Native Swift over wrapping ccusage** — Ported the JSONL log reader to Swift instead of shelling out to ccusage's Node.js CLI. This eliminates the Node.js runtime dependency, keeps the app at ~5 MB, and enables native FSEvents file watching for near-instant response to new token data.
- **Procedural sprites over image assets** — Phase 1 draws stick-figure frames programmatically via NSBezierPath. This avoids the need for external art assets during early development and guarantees template-image rendering for automatic light/dark menu bar adaptation. Custom sprite art is deferred to Phase 3.
- **Logarithmic speed mapping** — Used `log2(1 + tokensPerSec / 50)` rather than linear scaling so that low token rates produce visible animation changes while high bursts don't oversaturate. The curve was tuned so typical Sonnet usage (~200-500 tok/s) maps to a natural "jogging" speed.
- **GCD DispatchSource + periodic fallback** — Primary file monitoring uses `DispatchSource.makeFileSystemObjectSource` for low-overhead event-driven detection, with a 2-second periodic full scan as a fallback to catch new subdirectories and edge cases that FSEvents may miss.
- **Exponential smoothing on animation speed** — Applied `currentInterval += (targetInterval - currentInterval) * 0.15` per frame tick to prevent jarring speed jumps when token velocity changes abruptly.
