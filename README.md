
# RunClaude  <img src="images/Icon.png" alt="Icon" width="80">


A little Clawd that lives in your Mac's menu bar that helps you track your token usage.


<video src="images/RunClaude Demo.mp4" controls width="80%"></video>


https://github.com/user-attachments/assets/1888f406-ad95-4be4-b69c-900cb1193d11



---

## Download

Get the latest release from the [Releases page](https://github.com/chris8332558/RunClaude/releases).

1. Download `RunClaude-v1.0.0.zip` and unzip it
2. Move `RunClaude.app` to `/Applications`
3. **First launch:** macOS will block the app since it is not notarized. Right-click → **Open** → **Open Anyway** to run it

---

## Screenshots

**Live** — real-time tokens and cost for the active Claude session, refreshing every 0.5 seconds.

<img src="images/Live.png" alt="Live" width="280">

**7 Days** — token and cost breakdown over the past week, with daily bar charts.

<img src="images/7Days.png" alt="7 Days" width="280">

**Profile** — account summary showing total days, lifetime tokens, and usage limits for the current session and week.

<img src="images/profile.png" alt="Profile" width="280">


---

Inspired by [ccusage](https://github.com/ryoppippi/ccusage).

---

## Test Token Using

```bash
swift Scripts/generate-test-data.swift --live
```
