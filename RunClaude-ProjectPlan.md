# RunClaude — Project Plan

A macOS menu bar app that animates a sprite character at a speed proportional to your live Claude Code token usage, inspired by [RunCat](https://apps.apple.com/us/app/runcat/id1429033973?mt=12).

---

## 1. Concept

The menu bar shows an animated Claude character (an Anthropic-style sprite). When you're burning through tokens in Claude Code, the character sprints. When idle, it slows to a gentle walk or stands still. Clicking the icon opens a popover with token usage stats — today's input/output tokens, cost, model breakdown, and a mini usage chart.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────┐
│                  RunClaude.app                   │
│                                                  │
│  ┌──────────────┐   ┌────────────────────────┐  │
│  │ Menu Bar UI  │   │   Token Usage Engine    │  │
│  │ (AppKit +    │◄──│                         │  │
│  │  SwiftUI)    │   │  - Reads JSONL logs     │  │
│  │              │   │    from ~/.claude/       │  │
│  │  NSStatusItem│   │  - Calculates deltas    │  │
│  │  + sprite    │   │  - Emits tokens/sec     │  │
│  │    animation │   │                         │  │
│  └──────────────┘   └────────────────────────┘  │
│          │                                       │
│          ▼                                       │
│  ┌──────────────┐                                │
│  │   Popover    │                                │
│  │  (SwiftUI)   │                                │
│  │              │                                │
│  │  - Daily use │                                │
│  │  - Cost est. │                                │
│  │  - Model mix │                                │
│  │  - Sparkline │                                │
│  └──────────────┘                                │
└─────────────────────────────────────────────────┘
```

**Key design decision:** Build the entire app in **Swift** (AppKit + SwiftUI hybrid). Rather than importing ccusage as a Node.js subprocess, we reimplement the JSONL log reader natively in Swift. This keeps the app lightweight (~5 MB), avoids a Node.js dependency, and lets us use filesystem events for near-real-time updates.

---

## 3. How ccusage Works (and How We Adapt It)

The [ccusage](https://github.com/ryoppippi/ccusage) repo revealed that Claude Code stores conversation logs as **JSONL files** under:

```
~/.claude/projects/<project-hash>/*.jsonl
```

Each line is a JSON object containing token usage fields: `inputTokens`, `outputTokens`, `cacheCreationTokens`, `cacheReadTokens`, along with `model` and timestamp info.

**Our approach:** We port the core logic (file discovery, JSONL parsing, token aggregation) to Swift. This gives us three advantages over shelling out to ccusage: no Node.js dependency, native filesystem event monitoring via `DispatchSource` or `FSEvents`, and lower memory footprint.

---

## 4. Component Breakdown

### 4.1 Token Usage Engine (`TokenUsageEngine`)

**Responsibilities:** Monitor JSONL logs, compute live token velocity, and aggregate daily stats.

| Piece | Detail |
|-------|--------|
| **Log discovery** | Scan `~/.claude/projects/` recursively for `*.jsonl` files. Use `FSEvents` to watch for new files and appends. |
| **JSONL parser** | Stream-read new lines from each file. Parse JSON, extract `inputTokens`, `outputTokens`, `cacheCreationTokens`, `cacheReadTokens`, `model`. |
| **Deduplication** | Hash `(messageId, requestId)` pairs to avoid double-counting (same approach as ccusage). |
| **Token velocity** | Maintain a sliding window (e.g. 10 seconds). Compute `tokens/sec` as the animation speed driver. |
| **Daily aggregation** | Sum tokens by date, model, and session for the popover stats view. |
| **Cost estimation** | Embed a pricing table for Claude models (Opus, Sonnet, Haiku). Multiply tokens by per-model rates. Update pricing periodically from LiteLLM API or hardcode with manual updates. |

**Polling strategy:** Use `DispatchSource.makeFileSystemObjectSource` on each active JSONL file to get notified on writes. Fallback: poll every 1–2 seconds.

### 4.2 Menu Bar UI (`MenuBarController`)

**Responsibilities:** Render the animated sprite in NSStatusItem and control animation speed.

| Piece | Detail |
|-------|--------|
| **NSStatusItem** | Create a variable-length status item. Set its `button.image` on each frame tick. |
| **Sprite sheet** | A set of PNG frames (e.g. 8–12 frames) at 18×18 pt (@2x = 36×36 px). Template images so they adapt to light/dark mode. |
| **Animation timer** | `CADisplayLink` (or `Timer` with 60 fps cap). Frame interval = `f(tokensPerSec)`: high token rate → fast animation, zero → idle/stopped. |
| **Speed mapping** | `animationInterval = max(0.03, 1.0 / (1.0 + tokensPerSec * scaleFactor))`. Clamp between ~0.03s (sprint) and ~1.0s (idle walk). Tune `scaleFactor` so typical usage (e.g. 500 tok/s) looks like a moderate jog. |

### 4.3 Popover / Menu View (`UsagePopoverView`)

**Responsibilities:** Show detailed stats when the user clicks the menu bar icon.

Built in **SwiftUI**, attached to the NSStatusItem as a popover (not an NSMenu — popovers allow richer UI).

Contents:

- **Today's usage** — input tokens, output tokens, cache tokens, total
- **Estimated cost** — formatted as `$X.XX`
- **Model breakdown** — pie chart or segmented bar (Opus / Sonnet / Haiku)
- **Sparkline** — tokens per 5-minute bucket over the last few hours
- **Settings gear** — opens preferences

### 4.4 Sprite Assets

We need two animation sets:

| State | Frames | Description |
|-------|--------|-------------|
| **Running** | 8–12 frames | A stylized Claude character (abstract/geometric, Anthropic-inspired) in a run cycle |
| **Idle** | 2–4 frames | Gentle breathing or blinking animation |

Frame specs: 18×18 pt (36×36 px @2x, 54×54 px @3x). Use **template image** rendering (monochrome with alpha) so macOS tints them for light/dark menu bar automatically.

**Phase 1 option:** Start with simple geometric shapes (a running circle/blob) and refine art later.

### 4.5 Preferences (`SettingsView`)

- Custom Claude data directory path (override default `~/.claude/`)
- Animation style selector (different sprite sets)
- Cost display toggle (show/hide in popover)
- Launch at login toggle (via `SMAppService` on macOS 13+)
- Refresh interval slider

---

## 5. Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | **Swift 5.9+** | Native macOS, no runtime dependencies |
| UI framework | **AppKit** (menu bar) + **SwiftUI** (popover, settings) | AppKit needed for NSStatusItem; SwiftUI for modern declarative views |
| Animation | **CADisplayLink** / **Timer** | Smooth frame-rate-aware animation |
| File watching | **FSEvents** / `DispatchSource` | Near-instant detection of new log lines |
| JSON parsing | **Foundation** `JSONDecoder` | Built-in, fast JSONL parsing |
| Charts | **Swift Charts** (macOS 13+) | Native sparkline/bar charts in popover |
| Build | **Xcode 15+** / **Swift Package Manager** | Standard macOS app build tooling |
| Distribution | **DMG** or direct `.app` download | No App Store needed for v1 |

**Minimum macOS version:** macOS 13 Ventura (for MenuBarExtra, Swift Charts, SMAppService)

---

## 6. Project Structure

```
RunClaude/
├── RunClaude.xcodeproj
├── RunClaude/
│   ├── App/
│   │   ├── RunClaudeApp.swift          # @main, MenuBarExtra scene
│   │   ├── AppDelegate.swift           # NSStatusItem setup, animation loop
│   │   └── AppState.swift              # ObservableObject shared state
│   ├── Engine/
│   │   ├── TokenUsageEngine.swift      # Core: file watching, JSONL parsing
│   │   ├── JSONLParser.swift           # Line-by-line JSONL stream reader
│   │   ├── LogFileWatcher.swift        # FSEvents wrapper
│   │   ├── TokenAggregator.swift       # Sliding window, daily sums
│   │   ├── CostCalculator.swift        # Model pricing × token counts
│   │   └── Models.swift                # Data types: TokenRecord, DailyUsage, etc.
│   ├── MenuBar/
│   │   ├── MenuBarController.swift     # NSStatusItem + animation timer
│   │   ├── SpriteAnimator.swift        # Frame cycling logic
│   │   └── SpeedMapper.swift           # tokens/sec → frame interval
│   ├── Views/
│   │   ├── UsagePopoverView.swift      # Main popover content
│   │   ├── SparklineView.swift         # Token rate mini-chart
│   │   ├── ModelBreakdownView.swift    # Pie/bar chart of model usage
│   │   └── SettingsView.swift          # Preferences window
│   ├── Assets.xcassets/
│   │   ├── RunSprite/                  # Run cycle frames (template images)
│   │   ├── IdleSprite/                 # Idle animation frames
│   │   └── AppIcon.appiconset/
│   └── Info.plist                      # LSUIElement = true (no dock icon)
├── RunClaudeTests/
│   ├── JSONLParserTests.swift
│   ├── TokenAggregatorTests.swift
│   └── SpeedMapperTests.swift
├── README.md
└── LICENSE
```

---

## 7. Implementation Phases

### Phase 1 — Skeleton + Live Data (Week 1–2)

**Goal:** Menu bar icon that animates based on real token data.

1. Set up Xcode project as a menu bar-only app (`LSUIElement = true`)
2. Create `NSStatusItem` with a static placeholder icon
3. Implement `JSONLParser` — read Claude Code log files, extract token records
4. Implement `LogFileWatcher` — detect new lines appended to JSONL files using FSEvents
5. Implement `TokenAggregator` — compute a `tokensPerSecond` sliding window value
6. Implement `SpriteAnimator` — cycle through placeholder frames (colored squares) at a rate driven by `tokensPerSecond`
7. Wire it all together: log watcher → aggregator → animator → menu bar icon

**Deliverable:** App shows an animating icon that speeds up when Claude Code is actively streaming tokens.

### Phase 2 — Popover + Stats (Week 3)

**Goal:** Clicking the icon shows useful usage data.

1. Build `UsagePopoverView` in SwiftUI — show today's token counts and cost estimate
2. Implement `CostCalculator` with hardcoded model pricing
3. Add model breakdown view (which models used today, token split)
4. Add sparkline chart (tokens per 5-min bucket, last 6 hours)
5. Attach popover to NSStatusItem button action

**Deliverable:** Popover with real daily usage stats, cost estimates, and a mini activity chart.

### Phase 3 — Polish + Sprites (Week 4)

**Goal:** Production-quality look and feel.

1. Design and create proper sprite frames (run cycle + idle)
2. Implement template image rendering for automatic light/dark mode support
3. Add smooth speed transitions (ease between animation speeds, don't jump)
4. Add "launch at login" via SMAppService
5. Build Settings view with preferences persistence (UserDefaults)
6. Add a "Quit" option in the popover or a small dropdown

**Deliverable:** A polished app you'd want to actually use daily.

### Phase 4 — Extras (Week 5+, Optional)

- Multiple character/sprite packs (switch in settings)
- Weekly/monthly usage trends in popover
- Notification when daily cost exceeds a threshold
- Historical data export (CSV)
- Homebrew cask distribution
- Sparkle framework for auto-updates
- Support for other AI coding tools (Cursor, Copilot) if they produce similar logs

---

## 8. Key Technical Challenges

### 8.1 JSONL File Format Discovery

We need to reverse-engineer (or confirm from ccusage source) the exact JSONL schema Claude Code writes. Key fields to extract per line:

```json
{
  "type": "assistant",
  "message": { "usage": {
    "input_tokens": 1234,
    "output_tokens": 567,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 890
  }},
  "model": "claude-sonnet-4-20250514",
  "timestamp": "2025-06-01T12:34:56Z"
}
```

**Mitigation:** Study ccusage's `data-loader.ts` carefully during implementation. Write robust parsing that skips unknown line formats gracefully.

### 8.2 Real-Time File Tailing

Claude Code appends to JSONL files during a session. We need to:

- Track file read offset per file
- Detect appended bytes via FSEvents or polling
- Handle file rotation (new session → new file)

**Approach:** `DispatchSource.makeFileSystemObjectSource(fileDescriptor:, eventMask: .write)` per active file. Keep a `Dictionary<String, UInt64>` of file offsets. On write event, seek to last offset, read new lines, update offset.

### 8.3 Animation Smoothness

Jumping directly from 2 fps to 30 fps looks jarring. We need interpolation.

```swift
// Exponential smoothing
currentSpeed += (targetSpeed - currentSpeed) * 0.1  // per frame tick
```

### 8.4 Sandbox and Permissions

The app needs read access to `~/.claude/projects/`. Since we distribute outside the App Store, we can skip sandboxing, or use a temporary entitlement for the specific directory. The user may need to grant "Full Disk Access" or explicitly pick the folder via an open panel on first launch.

---

## 9. Speed Mapping Formula

The core mapping from token velocity to animation frame interval:

```swift
func frameInterval(tokensPerSecond: Double) -> TimeInterval {
    if tokensPerSecond < 1.0 {
        return 1.0  // idle: ~1 frame/sec (gentle idle animation)
    }
    // Logarithmic scaling so high bursts don't oversaturate
    let speed = log2(1.0 + tokensPerSecond / 50.0)
    let interval = max(0.04, 0.5 / speed)  // clamp: fastest = 25fps sprint
    return interval
}
```

| Token rate | Frame interval | Visual |
|-----------|---------------|--------|
| 0 tok/s | 1.0s | Idle/breathing |
| 50 tok/s | ~0.5s | Slow walk |
| 200 tok/s | ~0.25s | Jog |
| 500 tok/s | ~0.13s | Run |
| 1000+ tok/s | ~0.04s | Sprint |

---

## 10. Open Questions

1. **Sprite art** — Should we commission custom art, use AI-generated sprites, or start with simple geometric shapes?
2. **Claude Code log format stability** — Is the JSONL schema stable across Claude Code versions, or should we build a version-adaptive parser?
3. **Privacy** — Should we add an option to NOT read log contents (only file sizes / modification times as a proxy)?
4. **Pricing data source** — Hardcode prices (easy, stale) vs. fetch from LiteLLM API (accurate, needs network)?
5. **Multiple Claude Code instances** — How to handle overlapping sessions writing to different project dirs?

---

## 11. Dependencies (Minimal)

The app has **zero external dependencies** for v1. Everything uses Apple frameworks:

- Foundation (JSON, file I/O)
- AppKit (NSStatusItem, NSStatusBar)
- SwiftUI (popover views, settings)
- Swift Charts (sparkline)
- CoreServices (FSEvents)
- ServiceManagement (launch at login)

This keeps the app tiny, fast to build, and free of supply chain risks.

---

## Summary

RunClaude is a focused, single-purpose macOS menu bar app. The core loop is simple: **tail JSONL logs → count tokens → animate sprite**. The bulk of the engineering effort is in getting the file watching right and making the animation feel good. The popover stats are a straightforward SwiftUI exercise. By keeping dependencies at zero and rewriting the log reader in native Swift, we get a self-contained ~5 MB app that launches instantly and runs quietly in the background.
