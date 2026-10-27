# [Workflow] MenuBarTimer: High-Contrast Menu Bar Countdown with Notifications & Active Timer Manager

Hi everyone! 👋

I'd like to share **MenuBarTimer**, a workflow I built for Alfred 5 that brings clean, high-visibility live countdown timers directly to the macOS menu bar.

Unlike standard scripts that hide in the background or pop up disruptive modal dialogs, MenuBarTimer gives you a glanceable countdown pill right in your menu bar, native Notification Center alerts when time's up, looping audio that stops the second you interact with it, and a full active timer manager right inside Alfred.

---

### ⏱️ Key Features

- **High-Contrast Menu Bar Pill:** High-contrast capsule badge with custom SF Symbols, white text, and golden digits. Stays crystal-clear on light, dark, and translucent wallpapers.
- **Natural Language Input:** Type `timer 5m Pasta`, `timer 25m Pomodoro`, `timer 1h 15m Code Review`, or `timer 45s Tea`.
- **Manage Active Timers (`timers`):** Type `timers` in Alfred to view all running countdowns with live remaining time, or press <kbd>Enter</kbd> to cancel any timer immediately.
- **Pause & Resume:** Click any menu bar timer or press <kbd>p</kbd> to freeze the countdown. The pill turns amber to show it's paused and resumes smoothly without losing time.
- **Repeating Alert Audio:** Choose from Apple sound chimes (`Radar`, `Alarm`, `Hero`, `Glass`, `Ping`, `Sosumi`, `Submarine`) in Alfred Preferences. The sound loops continuously until you click the menu bar pill or notification.
- **Action Notifications:** Real Notification Center alerts featuring **Repeat** and **End** buttons (no Finder "Show" button).
- **Multiple Timers:** Run separate simultaneous countdowns with their own labels and menu bar items.
- **Accessory App:** Zero Dock clutter (`LSUIElement = true`).

---

### ⌨️ Usage

- `timer 5m 30s Pasta` — Starts a 5-minute, 30-second countdown labeled "Pasta".
- `timer 25m Pomodoro` — Starts a 25-minute Pomodoro timer.
- `timers` — Lists active countdowns with real-time remaining time; press <kbd>Enter</kbd> to cancel.
- **Menu Bar Controls:** Click any timer pill to Pause/Resume, Repeat, or End.

---

### 📥 Download & Source

- **Download:** [MenuBarTimer.alfredworkflow (v1.0.0)](https://github.com/gedeyenite/MenuBarTimer/releases/latest)
- **Source Code & Documentation:** [github.com/gedeyenite/MenuBarTimer](https://github.com/gedeyenite/MenuBarTimer)

*Requires macOS 12+ and Alfred 5 with Powerpack.*

Feedback and suggestions are welcome!
