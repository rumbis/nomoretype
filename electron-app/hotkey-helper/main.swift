// NoMoreType — Hotkey Helper
// macOS CGEventTap daemon for detecting Right Control double-tap / single-tap.
// Spawned by Electron main process as a subprocess.
// Communicates via stdout JSON lines: {"event":"double-tap"} or {"event":"single-tap"}

import Cocoa
import Foundation

// Right Control key code on macOS
let RIGHT_CONTROL_KEY_CODE: UInt16 = 0x3B
// Double-tap threshold (ms)
let DOUBLE_TAP_THRESHOLD: TimeInterval = 0.4
// For tracking press states
var lastPressTime: Date?
var isRightCtrlDown = false

// Callback function for CGEventTap
let eventCallback: CGEventTapCallBack = { (proxy, type, event, refcon) in
    let now = Date()
    
    if type == .flagsChanged {
        let flags = event.flags
        let isDown = flags.contains(.maskControl) && !flags.contains(.maskShift) && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate)
        
        // Check if it's specifically Right Control
        // When Right Ctrl is pressed, the control flag is set but the key code is 0x3B
        // We detect this by checking: control flag is set AND no command/alt/shift
        
        if isDown && !isRightCtrlDown {
            // Press detected
            isRightCtrlDown = true
            
            if let last = lastPressTime {
                let interval = now.timeIntervalSince(last)
                if interval < DOUBLE_TAP_THRESHOLD {
                    // Double-tap!
                    printJSON(["event": "double-tap"])
                    lastPressTime = nil
                    isRightCtrlDown = false
                    return nil // swallow the event
                }
            }
            lastPressTime = now
            
        } else if !isDown && isRightCtrlDown {
            // Release detected
            isRightCtrlDown = false
            
            // If we didn't already handle it as a double-tap, treat as single tap
            if let last = lastPressTime {
                let interval = now.timeIntervalSince(last)
                if interval > 0.01 && interval < DOUBLE_TAP_THRESHOLD {
                    // It's been held briefly - single tap
                    printJSON(["event": "single-tap"])
                    lastPressTime = nil
                }
            }
        }
    }
    
    // Don't swallow the event — pass through
    return nil
}

func printJSON(_ dict: [String: String]) {
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
       let str = String(data: data, encoding: .utf8) {
        print(str)
        fflush(stdout)
    }
}

func main() {
    // Check accessibility permission
    let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true]
    let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
    
    if !trusted {
        printJSON(["error": "Accessibility permission required"])
        // Keep trying — user may grant permission
        DispatchQueue.global().async {
            while !AXIsProcessTrusted() {
                sleep(1)
            }
            DispatchQueue.main.async {
                printJSON(["event": "permission-granted"])
                startEventTap()
            }
        }
        // Run the run loop so we can detect when permission is granted
        RunLoop.current.run()
        return
    }
    
    startEventTap()
    RunLoop.current.run()
}

func startEventTap() {
    let eventMask = (1 << CGEventType.flagsChanged.rawValue)
    
    guard let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(eventMask),
        callback: eventCallback,
        userInfo: nil
    ) else {
        printJSON(["error": "Failed to create event tap"])
        return
    }
    
    let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    
    printJSON(["event": "started"])
}

main()
