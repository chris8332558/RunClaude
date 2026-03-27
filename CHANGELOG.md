# RunClaude Changelog

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
