#if os(macOS)
    import AppKit

    /// macOS quit / last-window behavior.
    ///
    /// SwiftUI keeps a `WindowGroup(id: "player")` scene that can remain as a
    /// hidden window. Combined with system fullscreen and VLC/KSPlayer teardown,
    /// `applicationShouldTerminate` is left on `.terminateLater` and never
    /// replied to — Apex → Quit / ⌘Q appears to do nothing. Force a real exit.
    final class ApexMacAppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
            true
        }

        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            for window in sender.windows where window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            for window in sender.windows {
                window.orderOut(nil)
            }
            return .terminateNow
        }
    }
#endif
