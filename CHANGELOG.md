# RunClaude Changelog

## [2026-04-03] — Fix standalone app 10s usage-limit fetch

### Fixed
- `Engine/RateLimitFetcher.swift`: The `/usage` earlyExit was triggering on `"Esc to cancel"` from the loading spinner, before actual usage data had arrived. Changed to wait for `"used"` so the fetch only completes once real percentages are rendered.
- `Engine/RateLimitFetcher.swift`: Removed explicit `process.environment` override so `/bin/zsh -l` login shell can construct the full user environment from scratch, fixing the 10s timeout when the app is launched outside a terminal (e.g. from /Applications via Finder).
- `Engine/RateLimitFetcher.swift`: Added startup buffer logging to aid future debugging of PTY prompt detection.

### Decisions
- **`"used"` instead of `"Esc to cancel"` for earlyExit**: The `/usage` panel renders "Esc to cancel" twice — once during the loading spinner and again after the data loads. Keying on `"used"` (from "N% used") ensures we only stop after real data is present.

## [2026-04-03] — Persistent PTY for fast rate-limit fetching

### Changed
- `Engine/RateLimitFetcher.swift`: The `claude` process is now kept alive between refreshes instead of being respawned on every fetch. `runClaudeUsage(claudePath:)` was split into `startPersistentProcess(claudePath:)` (spawn once, wait for initial REPL prompt) and `fetchUsage(master:)` (drain stale output, send `/usage\r`, read until panel renders, dismiss with ESC). Subsequent fetches drop from ~10 s to ~1 s because Node.js startup is paid only once.
- `Engine/RateLimitFetcher.swift`: The rate-limit fetch now fires automatically at app launch (via `MenuBarController.setup()`) so data is ready before the popover is first opened.
- `MenuBar/MenuBarController.swift`: Now owns the `RateLimitFetcher` instance (moved out of the SwiftUI view) and calls `refresh()` during `setup()`. Marked `@MainActor` since it was always main-thread-only.
- `Views/UsagePopoverView.swift`: `RateLimitFetcher` property changed from `@StateObject` (self-owned) to `@ObservedObject` (injected from `MenuBarController`).

### Decisions
- **`nonisolated(unsafe)` for `persistentMaster`/`persistentProcess`**: `deinit` is not actor-isolated in Swift 5.9, so these properties need `nonisolated(unsafe)` to be accessible for cleanup. Access is safe because `refresh()` serializes mutations via the `isLoading` guard.
- **Fixed 0.3 s sleep instead of waiting for `> ` prompt after ESC**: The REPL redraws the screen with ANSI codes after ESC, making prompt detection unreliable. A short sleep is sufficient since the next call's drain step clears any leftover output anyway.

## [2026-04-03] — Fix Usage Limit fetch returning no data

### Fixed
- `Engine/RateLimitFetcher.swift`: ANSI stripping now replaces cursor-forward sequences (`ESC[NC`) with a space before removing other escape codes. The Claude CLI performs differential terminal redraws using `ESC[NC` to skip characters already on screen; stripping them as plain escape codes dropped those characters entirely — `"Current session"` → `"Curretsession"` — so context detection never fired and `parse()` always returned `nil`.
- `Engine/RateLimitFetcher.swift`: Context detection for "session" and "week" simplified to `line.contains(...)` now that word boundaries are preserved by the space substitution.
- `Engine/RateLimitFetcher.swift`: `^Rese\w*\s` match pattern relaxed to `^Rese\w*` (no required trailing whitespace) to tolerate `"Reses1pm"` where the space after the label was itself a cursor-forward skip.

### Decisions
- **Replace `ESC[NC` with a single space, not N spaces**: strictly correct substitution would insert N space characters, but a single space is sufficient since lines are trimmed before matching and only word separation matters, not column-accurate reconstruction.

## [2026-04-01] — CustomPack PNG animation with per-pack speed control

### Added
- `SpriteGenerator.swift`: `frameIntervalScale: Double` property on `SpritePack` protocol — a multiplier applied to the frame interval produced by `SpeedMapper`. Default is `1.0` (no change); values >1 slow the animation down, <1 speed it up. All existing packs inherit the default via the protocol extension and are unaffected.
- `SpriteGenerator.swift`: `CustomPack.clipDefinitions` — a static array of `(clipId, category, frameRange)` tuples that drives `clips()`. Adding a new PNG animation sequence is a single line in this array.
- `SpriteAnimator.swift`: `frameIntervalScale` stored on the animator, read from the active pack on `init` and updated in `switchPack(_:)`. Applied in `update(interval:idle:)` as `targetInterval = interval * frameIntervalScale`.

### Changed
- `SpriteGenerator.swift`: `CustomPack` migrated from legacy `generateRunFrames()`/`generateIdleFrames()` to the new-style `clips()` API, enabling future random clip selection between multiple run or idle variants at cycle boundaries (already supported by `SpriteAnimator`).
- `SpriteGenerator.swift`: `CustomPack` frame mapping updated — frames `claude1–6` → `"idle"` clip, `claude7–18` → `"run"` clip.
- `SpriteGenerator.swift`: `CustomPack.frameIntervalScale` set to `1.8` (runs ~80% slower than the default Clawd pack).

### Decisions
- **`frameIntervalScale` lives on `SpritePack`**, not on `SpeedMapper`, so each pack can opt into its own speed feel without touching the global velocity-to-interval curve. The animator multiplies after `SpeedMapper` computes the interval, keeping the two concerns separate.
- **Speed is adjusted in one place**: `CustomPack.frameIntervalScale` in `SpriteGenerator.swift`. Change `1.8` to tune: `1.0` = same as Clawd, `2.0` = half speed, `0.5` = double speed.

## [2026-03-31] — Reduce animation coast time after token activity stops

### Changed
- `Engine/TokenUsageEngine.swift`: `windowDuration` default reduced from 45 s to 10 s. The sliding velocity window now drains in ≤ 10 s after the last token arrives, so the running animation stops much sooner after Claude goes idle.

## [2026-03-31] — Add run_two animation variant with sequential leg lift

### Added
- `SpriteGenerator.swift`: `drawRunFrameTwo(phase:)` on `ClawdPack` — a second forward-facing run animation registered as the `"run_two"` clip. Differences from `drawRunFrame`: arms swing in opposite directions (left arm back while right arm forward), legs lift one at a time via ¼-cycle stagger (`legPhase = phase + i × 0.25`) instead of in alternating pairs, lift height increased to 1.5 px, and eye positions shifted slightly asymmetrically.

### Changed
- `SpriteGenerator.swift` — `ClawdPack.clips()` updated to expose `"run_two"` as the active run clip (original `"run"` and `"run_angled"` remain in the source but are commented out).

## [2026-03-31] — Multi-clip animation system with 45° angled run variant

### Added
- `SpriteGenerator.swift`: `AnimationCategory` enum (`.run` / `.idle`) and `AnimationClip` struct (`id`, `category`, `frames`) — the new primitive for naming and categorising animation sequences.
- `SpriteGenerator.swift`: `drawAngledRunFrame(phase:)` on `ClawdPack` — draws the bean character from a 45-degree angled perspective by rendering the body as a parallelogram (top edge sheared 3 pt right), differentiating near/far arms, and positioning the eye cutouts at the sheared top of the body. Registered as the `"run_angled"` clip.
- `SpritePack`: `clips() -> [AnimationClip]` protocol requirement with extension defaults in both directions — packs that implement `clips()` get the legacy `generateRunFrames/IdleFrames()` for free; packs that implement the legacy pair get a single-variant `clips()` for free.
- `SpritePack`: `randomClip(for:)` extension helper — returns a random clip for the given category.

### Changed
- `SpriteGenerator.swift` — `ClawdPack` now exposes multiple run clips (`"run"`, `"run_angled"`) via `clips()` instead of a flat `generateRunFrames()`. The standard forward-facing run is currently commented out so only the angled variant plays.
- `SpriteAnimator.swift` — replaced `runFrames`/`idleFrames` flat arrays with `runClips`/`idleClips` clip libraries. `currentClip` tracks the playing clip; at the end of each cycle `advanceFrame()` randomly selects the next clip from the active category, giving natural variety without any jarring mid-clip cuts.

### Decisions
- **Dual-default extension pattern** — rather than forcing all existing packs to be rewritten, the `SpritePack` extension provides defaults for both the old (`generateRunFrames/IdleFrames`) and new (`clips()`) APIs. A pack only needs to implement one side; Swift's dynamic dispatch resolves the other. This keeps the migration incremental.
- **Randomise at cycle boundary, not on mode switch** — swapping clips mid-cycle would cause a visual jump. Waiting for `currentFrameIndex` to wrap back to 0 ensures clean boundaries between variants.

## [2026-03-31] — Fix reset-time parser dropping time token (e.g. "2pm")

### Fixed
- `Engine/RateLimitFetcher.swift`: `resetsAt` extraction now strips only the leading letter portion of the garbled "Resets" word (`Rese[a-zA-Z]*`) rather than everything up to the first whitespace. PTY `\r` overwrites can merge "Resets" with the next token (e.g. `"Reses2pm (America/Los_Angeles)"`); the old fallback found the first space after "2pm", discarding the time entirely. The new regex stops before digits so "2pm" is preserved.

### Decisions
- **Regex `Rese[a-zA-Z]*` over splitting on whitespace** — the first-space approach works when the garbled prefix and the time are separated by a space, but fails when they're merged into one word. Matching only the letter run after "Rese" is robust to both the clean and garbled cases without needing a special-case branch for each.

## [2026-03-30] — Speed up rate-limit fetch: 5-min cache + early PTY termination

### Changed
- `Engine/RateLimitFetcher.swift`: `refresh()` now accepts a `force: Bool` parameter and skips the PTY spawn when cached data is < 5 minutes old (`cacheMaxAge = 300s`). Repeat opens of the Profile tab are instant; the ↻ button passes `force: true` to always re-fetch.
- `Engine/RateLimitFetcher.swift`: After sending `/usage\r`, the PTY read loop now exits as soon as `"Esc to cancel"` appears in the buffer — the last line rendered by the usage panel — rather than waiting for the trailing REPL `> ` prompt to redraw. Saves ~0.5–1 s per fetch.
- `Engine/RateLimitFetcher.swift`: Renamed `waitForPrompt` to `waitFor` and added an `earlyExit` predicate parameter to express both stop conditions uniformly.
- `Views/UsagePopoverView.swift`: Refresh button now calls `refresh(force: true)`.

### Decisions
- **Can't use the API directly** — the `claude.ai/api/organizations/{id}/rate_limits` endpoint exists but is behind Cloudflare bot protection; plain HTTP requests with the Bearer token receive a JS challenge. The `claude` CLI solves this internally. The PTY approach is unavoidable.
- **`--bare` flag not usable** — `--bare` starts in ~1s but disables OAuth/keychain reads, so `/usage` reports "Not logged in".
- **Cache instead of keep-alive** — keeping a long-running `claude` process resident would eliminate startup time but adds complexity and resource overhead; a 5-min cache achieves the same perceived speed for the typical "glance at limits" use case.

## [2026-03-30] — Persist rate-limit data across popover open/close; clock timestamp

### Fixed
- `MenuBar/MenuBarController.swift`: `showPopover()` was creating a new `NSPopover` + `NSHostingController` on every open, resetting all SwiftUI `@StateObject` instances (including `RateLimitFetcher`) to initial state. Popover is now created once and reused — fetched data survives close/reopen.

### Changed
- `Views/UsagePopoverView.swift`: "Updated" timestamp changed from a relative string ("2m ago") to an absolute clock time ("3:45 PM"). Relative time requires a live timer to stay accurate; absolute time is always correct without any refresh mechanism.

## [2026-03-30] — Fix rate-limit parser: \r garbling, missing space in % token

### Fixed
- `Engine/RateLimitFetcher.swift`: `parse()` now normalises PTY line endings (`\r\n` → `\n`, bare `\r` → `\n`) before ANSI stripping. Without this, progress-spinner overwrites left `\r` mid-string, causing lines like `"Resets at 1m"` to be garbled into `"Reses1m"` and miss the `hasPrefix("Resets")` guard entirely.
- `Engine/RateLimitFetcher.swift`: `extractPercentage` regex changed from `\d+%\s+used` to `\d+%\s*used` — ANSI stripping was collapsing the space between `%` and `used` (e.g. `"0%used"`), causing percentage extraction to return `nil` for every line.
- `Engine/RateLimitFetcher.swift`: "Resets" line detection changed from `hasPrefix("Resets")` to a regex `^Rese\w*\s` to tolerate garbled prefixes that may survive even after `\r` normalisation. `resetsAt` extraction falls back to "everything after the first whitespace block" when the clean `"Resets "` prefix is absent.

### Decisions
- **Normalise before stripping, not after** — `\r` must be handled before the ANSI regex runs; a bare `\r` is not an ANSI sequence and the existing regex would leave it in place, causing split-by-newline to include both the original and overwritten text on the same "line".

## [2026-03-30] — Event-driven PTY synchronisation for rate-limit fetcher

### Changed
- `Engine/RateLimitFetcher.swift`: `runClaudeUsage()` rewritten to be event-driven instead of timer-based. Previously, startup was gated by a fixed 3.5 s `sleep` followed by a drain-and-discard; now the function waits for the REPL's `> ` prompt to appear in the PTY output before sending `/usage`. Response collection likewise waits for the next `> ` prompt rather than using a 2.5 s "settled output" heuristic with a 10 s hard deadline.
- `Engine/RateLimitFetcher.swift`: stderr now routed into the same slave PTY as stdout (was discarded to `/dev/null`), so startup errors (e.g. auth failures) are captured in the raw output and visible in debug logs.
- `Engine/RateLimitFetcher.swift`: Command terminator changed from `/usage\n` + second `\n` (workaround for autocomplete) to `/usage\r`, which is the correct line-end character for a PTY.
- `Engine/RateLimitFetcher.swift`: Read loop extracted into a `readAvailable(into:)` local helper, called by a shared `waitForPrompt()` function used for both startup and post-command synchronisation.

### Decisions
- **Prompt detection over fixed sleeps** — Fixed delays are fragile: they over-wait on fast machines and under-wait under load. Watching for `> ` in the PTY stream is the minimal reliable signal that the REPL is ready without requiring any changes to how `claude` is invoked.

## [2026-03-30] — Fix duplicate model rows, document cache token discrepancy

### Fixed
- `Views/UsagePopoverView.swift`: Today tab showed duplicate model rows (e.g. two "Sonnet" entries) when multiple model version IDs mapped to the same family. Root cause: `modelBreakdown` keys are raw API model strings (`claude-sonnet-4-6`, `claude-sonnet-4-20250514`, etc.), so variants accumulated as separate entries. `modelBreakdownSection` now groups by `shortModelName()` before rendering, merging tokens and costs across all variants into a single row per family.

### Changed
- `docs/token_cost_counting.md`: Added "Why totals differ from Claude Code's `/stats`" subsection explaining that cache read tokens dominate counts (~90% of total in a typical session), which causes a ~100× difference between RunClaude's `totalTokens` (all 4 types) and what `/stats` likely reports (input + output only). Includes a real example table. Also corrected sliding window duration from 10s to 45s.

### Decisions
- **Merge at display time, not storage time** — Model variants are kept as separate keys in `modelBreakdown` so that per-version cost calculation remains accurate (each raw model ID resolves to its own pricing). Merging happens only in the view layer when rendering the breakdown list.

## [2026-03-30] — Cost bug fixes, CPU optimisations, profile stat redesign

### Added
- `TokenAggregator.swift`: Three reusable `DateFormatter` instance properties (`weekdayFormatter`, `shortDateFormatter`, `dayNumberFormatter`) — replaces two per-call allocations inside `buildHistory()` and `buildCurrentMonth()` that fired 2×/sec
- `TokenAggregator.swift`: `cachedLifetimeTotalTokens` — running counter incremented in `ingest()` so `lifetimeTotalTokens` is O(1) instead of iterating all historical days on every `buildState()` call
- `TokenAggregator.swift`: `cachedSparklineData` + `sparklineDirty` flag — sparkline sort is only rebuilt when buckets actually change, not on every 0.5s tick

### Changed
- `TokenAggregator.swift`: `today` getter now populates `DailyUsage.estimatedCost` and per-model `ModelUsage.estimatedCost` via `computeDayCost()` — previously both were always `0.0`, causing the header cost chip and model breakdown costs to show `$0.00`
- `TokenUsageEngine.swift`: `updateState()` simplified — removed the redundant second call to `aggregator.today` and duplicate cost loop; `buildState()` already returns a fully-costed `todayUsage`, so the cost alert now reads `state.todayUsage.estimatedCost` directly
- `Views/UsagePopoverView.swift`: Profile Account section redesigned — days-since-first-use and lifetime token count moved to the top of the section as two prominent rows with large bold monospaced numbers (`size 22, weight .bold`) above the account detail rows
- `SpriteGenerator.swift`: `ClawdPack` run animation — right arm reverted to same-direction swing (`armBaseY + armSwing`) matching the left arm; both arms pump together
- `docs/token_cost_counting.md`: Moved from repo root `docs/` to `RunClaude/docs/`

### Fixed
- **Header cost always `$0.00`** — `DailyUsage.estimatedCost` was never written during ingest; cost is now computed on read in the `today` getter from the model breakdown
- **Model breakdown cost always `$0.00`** — Same root cause; `ModelUsage.estimatedCost` is now populated alongside `DailyUsage.estimatedCost` in the same pass

### Decisions
- **Compute cost on read, not on write** — Rather than accumulating `estimatedCost` during `ingest()` (which would require adding cost deltas per-record and keeping two values in sync), cost is derived from the already-correct `modelBreakdown` in the `today` getter. This is called at most 2×/sec and iterates only a handful of model entries, so the overhead is negligible.
- **Cache with dirty flag over always-recompute** — `sparklineData` sorted 288 entries and `lifetimeTotalTokens` iterated all historical days on every 0.5s tick regardless of whether anything had changed. Caching with an invalidation flag on ingest eliminates the redundant work without adding meaningful complexity.

## [2026-03-29] — Skills in profile, animation persistence, live session cleanup

### Added
- `Engine/Models.swift`: `SkillInfo` struct — skill name and marketplace source, `Identifiable` by name
- `Engine/ClaudeConfigReader.swift`: `readSkills()` — scans `~/.claude/plugins/marketplaces/<marketplace>/skills/` for installed skill directories; groups by marketplace
- `Views/UsagePopoverView.swift`: "Skills" section in Profile tab — sparkles icon header with count, adaptive grid of cyan skill tags grouped by marketplace

### Changed
- `Engine/TokenUsageEngine.swift`: Sliding window duration increased from 10s to 45s — velocity now averages over a longer period so the sprite animation persists through natural gaps in Claude Code output (thinking, tool calls, file reads)
- `Engine/TokenAggregator.swift`: `isActive` threshold widened from 5s to 30s — matches the session inactive timeout so the green status dot stays lit through typical inter-request pauses
- `Engine/TokenAggregator.swift`: Added `sessionVisibilityTimeout` (300s) — inactive sessions are hidden from the Live tab after 5 minutes instead of lingering all day; underlying data preserved for daily totals
- `MenuBar/SpriteAnimator.swift`: Smoothing factor reduced from 0.12 to 0.05 — gives a ~2s ramp-down instead of 0.5s so the sprite decelerates gradually when token flow pauses

### Fixed
- **Live tab clutter** — Sessions from hours ago no longer appear in the Live tab. The `buildLiveSessions()` filter now requires `lastRecord` within `sessionVisibilityTimeout` (5 min) in addition to `totalTokens > 0`.
- **Animation stops mid-generation** — The 10s sliding window caused velocity to drop to zero during normal Claude Code pauses (tool execution, thinking). The 45s window plus gentler smoothing keeps the sprite running through these gaps.

### Decisions
- **45-second sliding window** — Chosen as a balance between responsiveness and persistence. Short enough to detect idle-vs-active within a minute, long enough to bridge typical 10–30s gaps between Claude Code JSONL writes. The old 10s window was tuned for instantaneous responsiveness but felt broken in practice.
- **5-minute session visibility timeout** — Long enough to see a session wind down after it finishes, short enough that sessions from earlier in the day don't clutter the Live tab. Sessions remain in `fileSessions` for accurate daily totals regardless.
- **Skills as tags rather than list rows** — Skills are just names (no version, no toggle), so compact tags in an adaptive grid use space more efficiently than the list format used for plugins.

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
