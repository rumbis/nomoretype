// NoMoreType — Hotkey Helper
// macOS CGEventTap daemon for detecting Left Control key:
//   - Double-tap Left Control → start recording
//   - Single-tap Left Control (while recording) → stop recording
// Spawned by Electron as subprocess, communicates via stdout JSON.
//
// key codes: Left Ctrl=0x3B, Right Ctrl=0x3E

import Cocoa
import Foundation

let RIGHT_CTRL: UInt16 = 0x3B
let DOUBLE_TAP_WINDOW: TimeInterval = 0.4 // seconds

var firstPressTime: Date?
var pendingSingleTap: DispatchWorkItem?

// ─── CGEventTap callback ──────────────────────────────────────────

let eventCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
    if type == .flagsChanged {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == RIGHT_CTRL else {
            return Unmanaged.passUnretained(event) // pass through other keys
        }

        let flags = event.flags
        let isDown = flags.contains(.maskControl)
        let now = Date()

        if isDown {
            // ── PRESSED ──
            if let first = firstPressTime {
                let elapsed = now.timeIntervalSince(first)
                if elapsed < DOUBLE_TAP_WINDOW {
                    // Second press within window → DOUBLE TAP!
                    pendingSingleTap?.cancel()
                    pendingSingleTap = nil
                    firstPressTime = nil
                    log(["event": "double-tap"])
                    return nil // swallow
                }
            }

            // First press (or too slow for double-tap)
            pendingSingleTap?.cancel()
            firstPressTime = now

        } else {
            // ── RELEASED ──
            guard let first = firstPressTime else {
                return nil
            }

            let elapsed = now.timeIntervalSince(first)

            if elapsed > DOUBLE_TAP_WINDOW {
                // Held too long for double-tap → single tap
                firstPressTime = nil
                log(["event": "single-tap"])
            } else {
                // Released quickly — wait for possible second press
                let task = DispatchWorkItem {
                    if firstPressTime != nil {
                        firstPressTime = nil
                        log(["event": "single-tap"])
                    }
                }
                pendingSingleTap = task
                DispatchQueue.main.asyncAfter(deadline: .now() + DOUBLE_TAP_WINDOW, execute: task)
            }
        }
    }
    return Unmanaged.passUnretained(event)
}

// ─── JSON output ──────────────────────────────────────────────────

func log(_ dict: [String: String]) {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

// ─── Event Tap Setup ──────────────────────────────────────────────

func startTap() {
    let mask = (1 << CGEventType.flagsChanged.rawValue)
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(mask),
        callback: eventCallback,
        userInfo: nil
    ) else {
        log(["error": "Failed to create event tap"])
        return
    }
    let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    log(["event": "started"])
}

// ─── Main ─────────────────────────────────────────────────────────

func main() {
    // Warm up accessibility — prompts user if not granted
    let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts) {
        log(["error": "Accessibility permission required"])
        // Poll until granted
        DispatchQueue.global().async {
            while !AXIsProcessTrusted() { Thread.sleep(forTimeInterval: 1) }
            DispatchQueue.main.async {
                log(["event": "permission-granted"])
                startTap()
            }
        }
        RunLoop.current.run()
        return
    }
    startTap()
    RunLoop.current.run()
}

main()
