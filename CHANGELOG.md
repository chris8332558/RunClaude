# RunClaude Changelog

## [2026-03-28] — Profile tab: account info, tool usage, plugins

### Added
- `Engine/ClaudeConfigReader.swift`: New file. Reads `~/.claude.json` for account info (oauthAccount), tool usage stats (toolUsage), and `firstStartTime`. Scans `~/.claude/plugins/` for installed plugins, parsing manifest files (package.json, plugin.json, etc.) for name, version, description, and enabled state. Results are cached for 30 seconds to avoid excessive disk I/O on each 0.5s tick.
- `Engine/Models.swift`: `ClaudeAccount` struct — display name, email, org, role, billing type, extra usage flag, with a computed `billingLabel` (stripe_subscription → "Pro", etc.)
- `Engine/Models.swift`: `ToolUsageStat` struct — per-tool invocation count and last-used date, `Identifiable` by tool name
- `Engine/Models.swift`: `PluginInfo` struct — plugin name, version, description, enabled state, and file path
- `Engine/Models.swift`: `ClaudeProfile` struct — aggregates account, tool usage, plugins, and firstStartTime with computed helpers `daysSinceFirstUse` and `totalToolInvocations`
- `Views/UsagePopoverView.swift`: New "Profile" tab with three sections: Account (name, email, org, role, plan type with "Extended" badge), Tool Usage (horizontal bar chart of top 8 tools color-coded by type), Plugins (list with enabled/disabled status, version, description)

### Changed
- `Engine/Models.swift`: `UsageState` gained `claudeProfile: ClaudeProfile` field
- `Engine/TokenUsageEngine.swift`: Instantiates `ClaudeConfigReader` and populates `state.claudeProfile` on every state update
- `Views/UsagePopoverView.swift`: Tab picker expanded from 4 to 5 tabs — Live | Today | 7 Days | 30 Days | Profile

### Decisions
- **30-second cache on config reads** — `~/.claude.json` and the plugins directory rarely change during a session. Caching avoids reading and parsing JSON on every 0.5s velocity tick while still picking up changes within half a minute.
- **Separate ClaudeConfigReader rather than extending LogFileWatcher** — Config files are static metadata (account, preferences) with a completely different access pattern from the streaming JSONL logs. Keeping them in a dedicated reader maintains single-responsibility and allows independent cache tuning.
- **Profile as a 5th tab rather than inline sections** — Account/plugin info is not time-series data and doesn't fit naturally into the Live/Today/7 Days/30 Days time-based paradigm. A dedicated tab keeps the existing tabs focused on usage metrics.

## [2026-03-27] — Per-file live sessions, custom sprite pack

### Added
- `Models.swift`: `sourceFile: String` field on `TokenRecord` — each parsed record now carries the JSONL file path it was read from
- `Models.swift`: `SessionInfo` made `Identifiable`; new fields `sourceFile`, `displayName`, `isActive`, `lastActivity`, `totalTokens`, `estimatedCost` to represent a single Claude Code session (one JSONL file)
- `TokenAggregator.swift`: `FileSession` internal struct and `fileSessions: [String: FileSession]` dictionary to accumulate per-file token data
- `TokenAggregator.swift`: `buildLiveSessions()` — replaces `buildSessionInfo()`; returns one `SessionInfo` per JSONL file, sorted active (recent activity < 30 s) first
- `TokenAggregator.swift`: `displayName(for:)` — derives a short project label from the Claude log directory name (e.g. `-Users-chris-myproject` → `myproject`)
- `UsagePopoverView.swift`: Summary header chips (active count, total tokens, total cost) above the session list
- `UsagePopoverView.swift`: `liveSessionCard(_:)` — compact per-session card with status dot, project name, LIVE badge, progress bar, burn rate, cost, projection, and models
- `UsagePopoverView.swift`: `liveStatChip(value:label:color:)` helper for the summary header
- `RunClaude/Sources/RunClaude/custom/`: New sprite directory replacing `witch_run/`; drop-in location for custom PNG frames

### Changed
- `JSONLParser.swift`: `parseLine`, `parseLines`, `parseNewLines`, and `extractTokenRecord` all accept an optional `sourceFile: String` parameter and thread it into the returned `TokenRecord`
- `LogFileWatcher.swift`: Passes the file path as `sourceFile` when calling `JSONLParser.parseNewLines`
- `Models.swift`: `sessionInfo: SessionInfo` in `UsageState` replaced by `liveSessions: [SessionInfo]`
- `UsagePopoverView.swift`: Live Session tab rebuilt as a scrollable list of `liveSessionCard` rows; removed the old SESSION / USAGE / PROJECTION block layout
- `SpriteGenerator.swift`: `WitchPack` renamed to `CustomPack` (id `custom`); loads frames from `custom/` subdirectory
- `SpriteGenerator.swift`: PixelRobot arms now explicitly carry `sway` offset so they track the body's left/right movement instead of floating in place
- `Package.swift`: Resource copy path updated from `witch_run` to `custom`

### Removed
- `witch_run/B_witch_1…6.png`: Deleted bundled witch sprite PNGs; replaced by the user-configurable `custom/` directory

### Decisions
- **Per-file sessions instead of a single daily session**: Claude Code writes one JSONL file per project/conversation, so mapping sessions 1-to-1 to files gives accurate multi-project visibility without heuristics. The old single-session approach merged all projects into one view, making burn rate meaningless when running multiple workspaces simultaneously.
- **30-second inactivity threshold for "active"**: Matches the polling cadence and gives a responsive but not jittery active/inactive signal. Sessions stay "active" long enough to survive a brief tool-call gap.
- **`custom/` sprite directory**: Replaces the hardcoded `witch_run/` pack with a generic user-replaceable drop zone. Users can supply their own PNG frames without code changes; pack id and display name become `custom`/`Custom` to reflect this.


## [2026-03-27] — Live session monitor, sparkline fix, speed tuning

### Added
- **Models.swift** — New `SessionInfo` struct with session start time, elapsed seconds, burn rate (tok/min), burn status (IDLE/LOW/NORMAL/HIGH/EXTREME), projected tokens and cost over an 8-hour session, projection status (ON TRACK/ELEVATED/HIGH), and active model names. New `SparklineBucket` struct for typed 5-minute sparkline data.
- **TokenAggregator.swift** — `sessionStartTime` tracking (earliest today record), `buildSessionInfo()` method that computes burn rate, classifies status by threshold, linearly projects tokens/cost over 8h, and extracts active model short names. Session resets on midnight crossing.
- **UsagePopoverView.swift** — New "Live" tab (default selected) inspired by `ccusage blocks --live` CLI output. Three card-style blocks: SESSION (cyan progress bar, start time, remaining hours), USAGE (green progress bar, token count, burn rate with colored status badge, cost), PROJECTION (projected tokens/cost with ON TRACK/ELEVATED/HIGH badge). Models row and refresh indicator at bottom. Helper views: `liveBlock`, `liveProgressBar`, `liveStatusBadge`.

### Changed
- **SpeedMapper.swift** — Tuned animation speed defaults: `idleInterval` 0.8→0.4s, `sprintInterval` 0.04→0.03s, `scaleFactor` 50→40, interval numerator 0.5→0.1. Sprites now move roughly 2–3× faster at typical token rates.
- **UsagePopoverView.swift** — Sparkline section now reads `engine.state.sparklineBuckets` (5-minute aggregator buckets) instead of `engine.state.recentSamples` (10s sliding window), fixing the always-empty "Activity (last 6h)" chart. Tab picker expanded to Live | Today | 7 Days | 30 Days with Live as default. Popover height increased 440→480.
- **Models.swift** — `UsageState` gained `sparklineBuckets: [SparklineBucket]` and `sessionInfo: SessionInfo` fields.
- **TokenAggregator.swift** — `buildState()` now populates `sparklineBuckets` from `sparklineData` and `sessionInfo` from `buildSessionInfo()`.

### Fixed
- **UsagePopoverView.swift** — "Activity (last 6h)" sparkline was always empty because it read the 10-second sliding window (`recentSamples`) instead of the 5-minute bucket data (`sparklineData`). The bucket data existed in the aggregator but was never wired through `UsageState` to the view.

### Decisions
- **8-hour session projection window** — Chose 8 hours as the default projection baseline since it represents a typical workday. Burn rate is computed as total tokens / elapsed minutes (simple average) rather than a windowed rate, so it stabilizes over time rather than spiking with short bursts.
- **Burn rate thresholds** — IDLE (<10 tok/min), LOW (<500), NORMAL (<5000), HIGH (<20000), EXTREME (20000+). These were calibrated against typical Claude Code usage patterns where Sonnet generates ~200-500 tok/s in bursts with idle gaps between requests.
- **Sparkline data path redesign** — Added a dedicated `SparklineBucket` type rather than reusing `TokenSample` to make the data flow explicit: aggregator buckets → `UsageState.sparklineBuckets` → sparkline chart. The sliding window samples serve a different purpose (velocity calculation) and have different lifetimes.

## [2026-03-26] — PixelRobot run animation redesign

### Changed
- **SpriteGenerator.swift** — Rewrote `PixelRobotPack.drawRunFrame` to match the idle frame's body design (6×5 px squat block, 4 evenly-spaced legs, 2×2 px arm stubs, transparent eye cutouts). Body sways left/right ±0.5 pt and bounces vertically on each step. Both arms move in the same direction (±1.2 pt swing) for a synchronised pumping feel. Legs alternate in pairs (±1 pt lift). Removed the old separate head and antenna.

## [2026-03-26] — Witch PNG pack, PixelRobot idle redesign

### Added
- **SpriteGenerator.swift** — New `WitchPack` (id: `"witch"`, display name "Witch", 42×18 frame). Loads 6 RGBA PNG frames (`B_witch_1…6.png`) from the app bundle, scales each to `frameSize` using an `NSImage` drawing handler, and marks them as template images. Run animation plays all 6 frames; idle alternates frames 1–2 for a hovering effect.
- **Sources/RunClaude/witch_run/** — 6 PNG sprite frames copied into the SPM target source directory so `Bundle.module` can resolve them at runtime.
- **Package.swift** — Added `.copy("witch_run")` resource rule to bundle the PNG frames.

### Changed
- **SpriteGenerator.swift** — Rewrote `PixelRobotPack.drawIdleFrame` to match the reference pixel-art design: wide 6×5 px squat body, 2×2 px arm stubs on both sides, 4 evenly-spaced 1 px legs, and two 1×1 px eye cutouts in the upper body. Eyes use `.clear` compositing to punch transparent holes through the black body so they are visually distinct in both light and dark mode regardless of `isTemplate = true`.
- **SpriteGenerator.swift** — Fixed `GhostPack.drawIdleFrame`: `isTemplate` was accidentally set to `false`, preventing correct light/dark rendering.
- **SpriteGenerator.swift** — Removed unused `bodyMidX` variable in `RunningCatPack.drawRunFrame` (was causing a compiler warning).

### Decisions
- **`.clear` compositing for eyes** — Template images ignore color; all opaque pixels render as the same system tint. White fills on a black body are indistinguishable. Using `NSGraphicsContext.current?.compositingOperation = .clear` creates truly transparent pixels, letting the menu bar background show through as the contrasting "eye" color.
- **PNGs inside SPM target directory** — SPM requires resources to live within the target's source directory for `Bundle.module` to be generated. The witch PNGs were copied from `Resources/Assets.xcassets/witch_run/` into `Sources/RunClaude/witch_run/` to satisfy this constraint.

## [2026-03-26] — Ghost sprite pack

### Added
- **SpriteGenerator.swift** — New `GhostPack` sprite (id: `"ghost"`, display name "Ghost", 18×18 frame). Body is a single `NSBezierPath`: semicircular rounded head → straight sides → 3-bump wavy skirt. Run animation (8 frames) bobs ±1.5 px with a side tilt that sways in sync for a floaty feel; idle animation (6 frames) drifts ±0.8 px and blinks at phase ≈0.85. Eyes are white ovals; blink state replaces them with short white line segments. Registered in `SpritePackRegistry.allPacks` — appears automatically in the Settings dropdown.

## [2026-03-26] — Phase 4: Sprite packs, cost alerts, trends, Homebrew

### Added
- **SpriteGenerator.swift** — Refactored into a `SpritePack` protocol with `SpritePackRegistry`. Four built-in packs: Claude Bean (default, the rounded capsule character), Running Cat (silhouette with wavy tail), Pixel Robot (blocky 8-bit with antenna), and Sound Wave (audio visualizer bars). All packs produce template images for automatic light/dark mode. Shared drawing utilities extracted into `SpriteDrawing` enum.
- **CostAlertManager.swift** — New file. Monitors daily cost against a user-defined threshold and delivers a macOS notification via `UNUserNotificationCenter` when exceeded. Fires at most once per day per threshold crossing; resets at midnight.
- **HistoryDataPoint** in Models.swift — New `Identifiable` struct for charting historical daily usage (tokens + cost + label).
- **UsagePopoverView.swift** — Added segmented tab bar (Today / 7 Days / 30 Days). History tabs show summary stats (total tokens, cost, avg/day), token bar chart, cost bar chart, and peak day label. Built with Swift Charts `BarMark` + `AxisMarks`.
- **SettingsView.swift** — Added "Character" section with sprite pack picker dropdown; "Cost Alerts" section with enable toggle and USD threshold input field.
- **Scripts/create-release.sh** — Release builder: compiles release binary, assembles .app bundle, zips it, and outputs SHA256 for Homebrew cask.
- **Cask/runclaude.rb** — Homebrew cask formula template. Users can install via `brew install --cask runclaude` once a GitHub release is published.

### Changed
- **SpriteAnimator.swift** — Added `switchPack(_:)` method for hot-swapping sprite packs at runtime; made `runFrames`/`idleFrames` mutable (`var`); added `frameSize` computed property that delegates to the current pack.
- **TokenAggregator.swift** — Added `historicalDays` dictionary tracking per-day usage from all ingested records (not just today). New `weeklyHistory` and `monthlyHistory` computed properties return `[HistoryDataPoint]` arrays for the last 7 and 30 days respectively.
- **TokenUsageEngine.swift** — Integrated `CostAlertManager`; calls `checkCost()` on every state update.
- **Models.swift** — Added `weeklyHistory` and `monthlyHistory` arrays to `UsageState`.
- **MenuBarController.swift** — Animator now initializes from `SpritePackRegistry.currentPack()`; Settings window wired to call `animator.switchPack()` on selection change; frame size is now dynamic per pack.
- **UsagePopoverView.swift** — Version bumped to v0.2.0.

### Decisions
- **Protocol-based sprite packs** — Used a `SpritePack` protocol instead of an enum or subclass hierarchy so that future packs (including user-contributed ones) can be added without modifying existing code. The registry pattern keeps discovery centralized.
- **Four diverse pack styles** — Chose distinctly different visual styles (organic bean, animal, pixel art, abstract visualizer) to demonstrate the range of the system and appeal to different tastes. All are procedurally generated — no external image assets required.
- **UNUserNotificationCenter over NSUserNotification** — The older `NSUserNotification` API is deprecated since macOS 11. `UNUserNotificationCenter` is the modern replacement and integrates with Focus/Do Not Disturb.
- **Historical data in-memory only** — Daily history is rebuilt from JSONL logs on each launch rather than persisted to a database. This keeps the architecture simple and the log files remain the single source of truth. The trade-off is a brief initial scan on startup.
- **Homebrew cask over tap formula** — A cask is the standard Homebrew distribution method for macOS GUI apps. The formula template includes `zap` stanzas for clean uninstallation.

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
