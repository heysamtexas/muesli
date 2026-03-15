import AppKit
import CoreAudio
import Foundation

@MainActor
final class MicActivityMonitor {
    var onMeetingAppDetected: ((String) -> Void)?
    private var timer: Timer?
    private var lastDetectedBundleID: String?
    private var suppressUntil: Date?

    private static let meetingApps: [String: String] = [
        "us.zoom.xos": "Zoom",
        "us.zoom.ZoomPhone": "Zoom Phone",
        "com.google.Chrome": "Chrome",
        "com.apple.FaceTime": "FaceTime",
        "com.microsoft.teams2": "Teams",
        "com.microsoft.teams": "Teams",
        "com.tinyspeck.slackmacgap": "Slack",
        "com.brave.Browser": "Brave",
        "company.thebrowser.Browser": "Arc",
        "org.mozilla.firefox": "Firefox",
        "com.apple.Safari": "Safari",
        "com.webex.meetingmanager": "Webex",
        "com.cisco.webexmeetingsapp": "Webex",
    ]

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.poll()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Suppress notifications for a period (e.g., after user dismisses or starts recording)
    func suppress(for duration: TimeInterval = 120) {
        suppressUntil = Date().addingTimeInterval(duration)
    }

    private func poll() {
        guard isMicInUse() else {
            lastDetectedBundleID = nil
            return
        }

        // Check if suppressed
        if let until = suppressUntil, Date() < until {
            return
        }

        // Find which running meeting app is likely using the mic
        let runningApps = NSWorkspace.shared.runningApplications
        for app in runningApps {
            guard let bundleID = app.bundleIdentifier,
                  let appName = Self.meetingApps[bundleID],
                  app.isActive || app.activationPolicy == .regular else { continue }

            // Only trigger once per app activation
            if lastDetectedBundleID == bundleID { return }
            lastDetectedBundleID = bundleID
            onMeetingAppDetected?(appName)
            return
        }
    }

    private func isMicInUse() -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address, 0, nil, &size, &deviceID
        ) == noErr else { return false }

        // Check if the input device is running
        var isRunning: UInt32 = 0
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        size = UInt32(MemoryLayout<UInt32>.size)

        guard AudioObjectGetPropertyData(
            deviceID, &runningAddress, 0, nil, &size, &isRunning
        ) == noErr else { return false }

        return isRunning != 0
    }
}
