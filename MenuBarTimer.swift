#!/usr/bin/env swift

import Cocoa
import UserNotifications

// MARK: - State Management
struct TimerState: Codable {
    let pid: Int32
    let label: String
    let totalSeconds: Int
    let targetDateEpoch: Double
    let isPaused: Bool
    let pausedRemainingSeconds: Int

    var remainingSeconds: Int {
        if isPaused {
            return pausedRemainingSeconds
        } else {
            let target = Date(timeIntervalSince1970: targetDateEpoch)
            return max(0, Int(ceil(target.timeIntervalSinceNow)))
        }
    }
}

let stateDirectory: URL = {
    let base = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/com.stephenmurphy.menubartimer/active", isDirectory: true)
    try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}()

func saveState(pid: Int32, label: String, totalSeconds: Int, targetDate: Date, isPaused: Bool, pausedRemaining: Int) {
    let state = TimerState(
        pid: pid,
        label: label,
        totalSeconds: totalSeconds,
        targetDateEpoch: targetDate.timeIntervalSince1970,
        isPaused: isPaused,
        pausedRemainingSeconds: pausedRemaining
    )
    let file = stateDirectory.appendingPathComponent("\(pid).json")
    if let data = try? JSONEncoder().encode(state) {
        try? data.write(to: file)
    }
}

func removeState(pid: Int32) {
    let file = stateDirectory.appendingPathComponent("\(pid).json")
    try? FileManager.default.removeItem(at: file)
}

func listActiveTimersJSON() -> String {
    let fm = FileManager.default
    guard let files = try? fm.contentsOfDirectory(at: stateDirectory, includingPropertiesForKeys: nil) else {
        return emptyTimersJSON()
    }

    var items: [[String: Any]] = []
    let appIconPath = "/Applications/MenuBarTimer.app/Contents/Resources/icon.png"

    for file in files where file.pathExtension == "json" {
        guard let data = try? Data(contentsOf: file),
              let state = try? JSONDecoder().decode(TimerState.self, from: data) else {
            try? fm.removeItem(at: file)
            continue
        }

        // Check if process is still alive
        if kill(state.pid, 0) != 0 {
            try? fm.removeItem(at: file)
            continue
        }

        let rem = state.remainingSeconds
        let formatted = formatDuration(rem)
        let displayLabel = state.label.isEmpty ? "Timer" : state.label
        let statusText = state.isPaused ? "Paused at \(formatted)" : "\(formatted) remaining"

        var item: [String: Any] = [
            "title": "\(displayLabel)  [\(formatted)]",
            "subtitle": "\(statusText) • Press Enter to cancel",
            "arg": "\(state.pid)",
            "valid": true
        ]
        if fm.fileExists(atPath: appIconPath) {
            item["icon"] = ["path": appIconPath]
        }
        items.append(item)
    }

    if items.isEmpty {
        return emptyTimersJSON()
    }

    let payload: [String: Any] = ["items": items]
    if let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted),
       let jsonStr = String(data: jsonData, encoding: .utf8) {
        return jsonStr
    }
    return emptyTimersJSON()
}

func emptyTimersJSON() -> String {
    let appIconPath = "/Applications/MenuBarTimer.app/Contents/Resources/icon.png"
    var item: [String: Any] = [
        "title": "No Active Timers",
        "subtitle": "Type 'timer [time] [label]' to start a countdown",
        "valid": false
    ]
    if FileManager.default.fileExists(atPath: appIconPath) {
        item["icon"] = ["path": appIconPath]
    }
    let payload: [String: Any] = ["items": [item]]
    let data = try! JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted)
    return String(data: data, encoding: .utf8)!
}

func cancelTimerByPID(_ pidString: String) {
    guard let pid = Int32(pidString.trimmingCharacters(in: .whitespaces)) else { return }
    kill(pid, SIGTERM)
    removeState(pid: pid)
}

func formatDuration(_ totalSec: Int) -> String {
    let sec = max(0, totalSec)
    let hours = sec / 3600
    let minutes = (sec % 3600) / 60
    let seconds = sec % 60

    if hours > 0 {
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - CLI Dispatch: List or Cancel
if CommandLine.arguments.count > 1 {
    let arg1 = CommandLine.arguments[1]
    if arg1 == "--list" || arg1 == "-l" {
        print(listActiveTimersJSON())
        exit(0)
    }
    if arg1 == "--cancel" || arg1 == "-c" {
        if CommandLine.arguments.count > 2 {
            cancelTimerByPID(CommandLine.arguments[2])
        }
        exit(0)
    }
}

// MARK: - Smart Argument Parser
func parseCommandLineArguments(_ args: [String]) -> (seconds: Int, label: String, sound: String)? {
    guard args.count > 1 else { return nil }

    var cleanArgs: [String] = []
    var soundName = ProcessInfo.processInfo.environment["ALERT_SOUND"] ?? "Radar"

    var i = 1
    while i < args.count {
        let arg = args[i]
        if (arg == "--sound" || arg == "-s") && i + 1 < args.count {
            soundName = args[i + 1]
            i += 2
            continue
        }
        cleanArgs.append(arg)
        i += 1
    }

    let raw = cleanArgs.joined(separator: " ")
    let tokens = raw.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    guard !tokens.isEmpty else { return nil }

    var totalSeconds = 0
    var labelIndex = 0
    var foundTime = false

    for (idx, token) in tokens.enumerated() {
        let lower = token.lowercased()

        // Match hours: 1h, 2hr, 2hours
        if lower.hasSuffix("h") || lower.hasSuffix("hr") || lower.hasSuffix("hours") {
            let numStr = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? ""
            if let h = Int(numStr), h > 0 {
                totalSeconds += h * 3600
                foundTime = true
                labelIndex = idx + 1
                continue
            }
        }

        // Match minutes: 5m, 10min, 10mins
        if lower.hasSuffix("m") || lower.hasSuffix("min") || lower.hasSuffix("mins") {
            let numStr = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? ""
            if let m = Int(numStr), m > 0 {
                totalSeconds += m * 60
                foundTime = true
                labelIndex = idx + 1
                continue
            }
        }

        // Match seconds: 30s, 45sec, 60secs
        if lower.hasSuffix("s") || lower.hasSuffix("sec") || lower.hasSuffix("secs") {
            let numStr = lower.components(separatedBy: CharacterSet.decimalDigits.inverted).first ?? ""
            if let s = Int(numStr), s > 0 {
                totalSeconds += s
                foundTime = true
                labelIndex = idx + 1
                continue
            }
        }

        // Match pure digits without unit on first token
        if !foundTime, let num = Int(lower), num > 0 {
            totalSeconds += num
            foundTime = true
            labelIndex = idx + 1
            continue
        }

        // Encountered a non-time word: the rest is the label
        break
    }

    guard totalSeconds > 0 else { return nil }

    let label = tokens.dropFirst(labelIndex).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    return (totalSeconds, label, soundName)
}

// MARK: - Double-Click / Direct App Launch Handling
if CommandLine.arguments.count <= 1 {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let alert = NSAlert()
    alert.messageText = "MenuBarTimer for Alfred"
    alert.informativeText = """
    MenuBarTimer runs live countdown timers in your macOS menu bar through Alfred.

    How to use in Alfred:
      timer 5m 30s Refresh Browser
      timer 25m Pomodoro
      timer 45s Check Oven
      timers (view and cancel running timers)

    Note: Ensure notifications are allowed for MenuBarTimer in System Settings so alert banners appear when timers finish.
    """
    alert.alertStyle = .informational

    if let icon = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: Bundle.main.path(forResource: "icon", ofType: "png") ?? "") {
        alert.icon = icon
    }

    alert.addButton(withTitle: "Open Notification Settings")
    alert.addButton(withTitle: "OK")

    NSApp.activate(ignoringOtherApps: true)
    let response = alert.runModal()
    if response == .alertFirstButtonReturn {
        let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
    exit(0)
}

guard let parsed = parseCommandLineArguments(CommandLine.arguments) else {
    let scriptName = (CommandLine.arguments[0] as NSString).lastPathComponent
    fputs("Usage: \(scriptName) <time> [label] [--sound <name>]\n", stderr)
    fputs("       \(scriptName) --list\n", stderr)
    fputs("       \(scriptName) --cancel <pid>\n", stderr)
    exit(1)
}

let totalSeconds = parsed.seconds
let timerLabel = parsed.label
let configuredSound = parsed.sound

// MARK: - App Delegate
class MenuBarTimerDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSUserNotificationCenterDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var countdownTimer: Timer?
    private let totalSeconds: Int
    private let label: String
    private let soundName: String
    private var targetDate: Date
    private var isFinished = false

    private var isPaused = false
    private var pausedRemainingSeconds: Int = 0

    private var activeSound: NSSound?
    private var soundRepeatTimer: Timer?
    private var statusMenuItem: NSMenuItem?
    private var pauseResumeMenuItem: NSMenuItem?
    private var sigSource: DispatchSourceSignal?

    init(seconds: Int, label: String, sound: String) {
        self.totalSeconds = seconds
        self.label = label
        self.soundName = sound
        self.targetDate = Date().addingTimeInterval(TimeInterval(seconds))
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupSignalHandler()
        setupNotifications()
        setupStatusItem()
        setupMenu()
        updateDisplay(remaining: totalSeconds)
        saveCurrentState()
        startCountdown()
    }

    private func setupSignalHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            self?.cancelClicked()
        }
        source.resume()
        self.sigSource = source
    }

    private func saveCurrentState() {
        saveState(
            pid: ProcessInfo.processInfo.processIdentifier,
            label: label,
            totalSeconds: totalSeconds,
            targetDate: targetDate,
            isPaused: isPaused,
            pausedRemaining: isPaused ? pausedRemainingSeconds : max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
        )
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let repeatAction = UNNotificationAction(identifier: "REPEAT", title: "Repeat", options: [.foreground])
        let endAction = UNNotificationAction(identifier: "END", title: "End", options: [.destructive])
        let category = UNNotificationCategory(identifier: "TIMER_EXPIRED",
                                              actions: [repeatAction, endAction],
                                              intentIdentifiers: [],
                                              options: [.customDismissAction])
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        NSUserNotificationCenter.default.delegate = self
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = ""
    }

    private func setupMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let headerTitle = label.isEmpty ? "Timer" : "Timer: \(label)"
        let headerItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        let statusItem = NSMenuItem(title: "Remaining: \(formatDuration(totalSeconds))", action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        self.statusMenuItem = statusItem

        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: "Pause Timer", action: #selector(togglePauseClicked), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)
        self.pauseResumeMenuItem = pauseItem

        let repeatItem = NSMenuItem(title: "Repeat Timer", action: #selector(repeatClicked), keyEquivalent: "r")
        repeatItem.target = self
        menu.addItem(repeatItem)

        let cancelItem = NSMenuItem(title: "End Timer", action: #selector(cancelClicked), keyEquivalent: "q")
        cancelItem.target = self
        menu.addItem(cancelItem)

        self.statusItem.menu = menu
    }

    private func startCountdown() {
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.countdownTimer = timer
    }

    private func tick() {
        guard !isPaused else { return }
        let remaining = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
        updateDisplay(remaining: remaining)

        if remaining <= 0 {
            finishTimer()
        }
    }

    private func updateDisplay(remaining: Int) {
        let timeString = formatDuration(remaining)
        statusMenuItem?.title = isPaused ? "Paused: \(timeString)" : "Remaining: \(timeString)"

        let badgeImage = renderBadge(title: label, time: timeString, isFinished: remaining <= 0, isPaused: isPaused)
        statusItem.button?.image = badgeImage
        statusItem.button?.imagePosition = .imageOnly
    }

    private func renderBadge(title: String, time: String, isFinished: Bool, isPaused: Bool) -> NSImage {
        let titleFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .heavy)

        let combined = NSMutableAttributedString()

        // Choose SF Symbol
        let symbolName: String
        let iconColor: NSColor
        if isFinished {
            symbolName = "checkmark.circle.fill"
            iconColor = NSColor(calibratedRed: 0.3, green: 1.0, blue: 0.4, alpha: 1.0)
        } else if isPaused {
            symbolName = "pause.fill"
            iconColor = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.25, alpha: 1.0)
        } else {
            symbolName = "timer"
            iconColor = NSColor.white
        }

        if let sf = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let conf = NSImage.SymbolConfiguration(pointSize: 11, weight: .bold).applying(.init(paletteColors: [iconColor]))
            if let icon = sf.withSymbolConfiguration(conf) {
                let attach = NSTextAttachment()
                attach.image = icon
                combined.append(NSAttributedString(attachment: attach))
                combined.append(NSAttributedString(string: " "))
            }
        }

        // Bold title
        if !title.isEmpty {
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .foregroundColor: NSColor.white
            ]
            combined.append(NSAttributedString(string: "\(title)  ", attributes: titleAttrs))
        }

        // Time digits
        let timeColor: NSColor
        if isFinished {
            timeColor = NSColor(calibratedRed: 0.35, green: 1.0, blue: 0.45, alpha: 1.0)
        } else if isPaused {
            timeColor = NSColor(calibratedRed: 1.0, green: 0.85, blue: 0.3, alpha: 1.0)
        } else {
            timeColor = NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.25, alpha: 1.0)
        }

        let timeAttrs: [NSAttributedString.Key: Any] = [
            .font: timeFont,
            .foregroundColor: timeColor
        ]
        combined.append(NSAttributedString(string: time, attributes: timeAttrs))

        let textSize = combined.size()
        let padH: CGFloat = 8
        let width = ceil(textSize.width + padH * 2)
        let height: CGFloat = 22

        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()

        let pillRect = NSRect(x: 0, y: 1, width: width, height: height - 2)
        let path = NSBezierPath(roundedRect: pillRect, xRadius: (height - 2) / 2, yRadius: (height - 2) / 2)

        // Choose pill colors
        let pillColor: NSColor
        let strokeColor: NSColor
        if isFinished {
            pillColor = NSColor(calibratedRed: 0.05, green: 0.25, blue: 0.12, alpha: 1.0)
            strokeColor = NSColor(calibratedRed: 0.25, green: 0.85, blue: 0.4, alpha: 0.8)
        } else if isPaused {
            pillColor = NSColor(calibratedRed: 0.22, green: 0.15, blue: 0.04, alpha: 1.0)
            strokeColor = NSColor(calibratedRed: 0.95, green: 0.70, blue: 0.20, alpha: 0.85)
        } else {
            pillColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
            strokeColor = NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.95, alpha: 0.7)
        }

        pillColor.setFill()
        path.fill()

        strokeColor.setStroke()
        path.lineWidth = 1.0
        path.stroke()

        let textRect = NSRect(x: padH,
                              y: (height - textSize.height) / 2 - 0.5,
                              width: textSize.width,
                              height: textSize.height)
        combined.draw(in: textRect)

        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    @objc private func togglePauseClicked() {
        guard !isFinished else { return }
        if isPaused {
            // Resume
            isPaused = false
            self.targetDate = Date().addingTimeInterval(TimeInterval(pausedRemainingSeconds))
            pauseResumeMenuItem?.title = "Pause Timer"
            startCountdown()
            updateDisplay(remaining: pausedRemainingSeconds)
        } else {
            // Pause
            isPaused = true
            countdownTimer?.invalidate()
            countdownTimer = nil
            pausedRemainingSeconds = max(0, Int(ceil(targetDate.timeIntervalSinceNow)))
            pauseResumeMenuItem?.title = "Resume Timer"
            updateDisplay(remaining: pausedRemainingSeconds)
        }
        saveCurrentState()
    }

    private func finishTimer() {
        guard !isFinished else { return }
        isFinished = true

        countdownTimer?.invalidate()
        countdownTimer = nil

        // Clean up from active state list so `timers` doesn't list it as counting
        removeState(pid: ProcessInfo.processInfo.processIdentifier)

        startRepeatingAlertSound()
        displayAppNotification()
        updateDisplay(remaining: 0)

        // Safety timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 600.0) { [weak self] in
            if self?.isFinished == true {
                self?.cancelClicked()
            }
        }
    }

    private func startRepeatingAlertSound() {
        stopAlertSound()
        var chosenSound: NSSound?

        let tonePath = "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/\(soundName).m4r"
        if FileManager.default.fileExists(atPath: tonePath),
           let tone = NSSound(contentsOfFile: tonePath, byReference: true) {
            chosenSound = tone
        } else if let sysSound = NSSound(named: soundName) {
            chosenSound = sysSound
        } else if let radar = NSSound(contentsOfFile: "/System/Library/PrivateFrameworks/ToneLibrary.framework/Versions/A/Resources/Ringtones/Radar.m4r", byReference: true) {
            chosenSound = radar
        }

        guard let sound = chosenSound else {
            NSSound.beep()
            return
        }

        self.activeSound = sound

        if sound.duration >= 3.0 {
            sound.loops = true
            sound.play()
        } else {
            sound.loops = false
            sound.play()
            let timer = Timer(timeInterval: max(2.5, sound.duration + 1.0), repeats: true) { [weak self] _ in
                self?.activeSound?.play()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.soundRepeatTimer = timer
        }
    }

    private func stopAlertSound() {
        soundRepeatTimer?.invalidate()
        soundRepeatTimer = nil
        activeSound?.stop()
        activeSound = nil
    }

    private func displayAppNotification() {
        let title: String = label.isEmpty ? "Timer Finished" : "Timer Finished: \(label)"
        let message: String = label.isEmpty ? "Your countdown timer has completed." : "“\(label)” has finished!"

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.categoryIdentifier = "TIMER_EXPIRED"
        content.sound = .default

        let request = UNNotificationRequest(identifier: "TIMER_\(Date().timeIntervalSince1970)", content: content, trigger: nil)
        center.add(request) { _ in }

        let legacyNotif = NSUserNotification()
        legacyNotif.title = title
        legacyNotif.informativeText = message
        legacyNotif.soundName = NSUserNotificationDefaultSoundName
        legacyNotif.hasActionButton = true
        legacyNotif.actionButtonTitle = "Repeat"
        legacyNotif.otherButtonTitle = "End"
        NSUserNotificationCenter.default.deliver(legacyNotif)
    }

    func menuWillOpen(_ menu: NSMenu) {
        if isFinished {
            stopAlertSound()
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        stopAlertSound()
        if response.actionIdentifier == "REPEAT" {
            repeatClicked()
        } else {
            cancelClicked()
        }
        completionHandler()
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        stopAlertSound()
        if notification.activationType == .actionButtonClicked {
            repeatClicked()
        } else {
            cancelClicked()
        }
    }

    @objc private func repeatClicked() {
        isFinished = false
        isPaused = false
        pauseResumeMenuItem?.title = "Pause Timer"
        stopAlertSound()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        NSUserNotificationCenter.default.removeAllDeliveredNotifications()
        self.targetDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
        updateDisplay(remaining: totalSeconds)
        saveCurrentState()
        startCountdown()
    }

    @objc private func cancelClicked() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        stopAlertSound()
        removeState(pid: ProcessInfo.processInfo.processIdentifier)
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        NSUserNotificationCenter.default.removeAllDeliveredNotifications()
        NSApp.terminate(nil)
    }
}

// MARK: - Application Lifecycle
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let delegate = MenuBarTimerDelegate(seconds: totalSeconds, label: timerLabel, sound: configuredSound)
app.delegate = delegate
app.run()
