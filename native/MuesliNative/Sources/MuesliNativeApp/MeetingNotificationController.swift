import AppKit
import Foundation

@MainActor
final class MeetingNotificationController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var onStartRecording: (() -> Void)?
    private var onDismiss: (() -> Void)?

    func show(
        title: String,
        subtitle: String,
        onStartRecording: @escaping () -> Void,
        onDismiss: (() -> Void)? = nil
    ) {
        close()

        self.onStartRecording = onStartRecording
        self.onDismiss = onDismiss

        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 340
        let height: CGFloat = 64
        let margin: CGFloat = 16

        let x = screen.visibleFrame.maxX - width - margin
        let y = screen.visibleFrame.maxY - height - margin

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: y, width: width, height: height),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let contentView = NSView(frame: NSRect(origin: .zero, size: NSSize(width: width, height: height)))
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 12
        contentView.layer?.backgroundColor = NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 0.96).cgColor
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        // Title label
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 14, y: 34, width: 160, height: 18)
        contentView.addSubview(titleLabel)

        // Subtitle label
        let subtitleLabel = NSTextField(labelWithString: subtitle)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.6)
        subtitleLabel.frame = NSRect(x: 14, y: 14, width: 160, height: 16)
        contentView.addSubview(subtitleLabel)

        // Start Recording button
        let startButton = NSButton(title: "Start Recording", target: self, action: #selector(handleStartRecording))
        startButton.bezelStyle = .rounded
        startButton.font = .systemFont(ofSize: 12, weight: .medium)
        startButton.frame = NSRect(x: width - 136, y: 17, width: 116, height: 30)
        startButton.contentTintColor = .white
        startButton.wantsLayer = true
        startButton.layer?.backgroundColor = NSColor(red: 0.2, green: 0.5, blue: 1.0, alpha: 1.0).cgColor
        startButton.layer?.cornerRadius = 6
        startButton.isBordered = false
        contentView.addSubview(startButton)

        // Dismiss button (×)
        let dismissButton = NSButton(title: "×", target: self, action: #selector(handleDismiss))
        dismissButton.bezelStyle = .inline
        dismissButton.font = .systemFont(ofSize: 14, weight: .medium)
        dismissButton.frame = NSRect(x: width - 24, y: height - 22, width: 16, height: 16)
        dismissButton.isBordered = false
        dismissButton.contentTintColor = NSColor.white.withAlphaComponent(0.4)
        contentView.addSubview(dismissButton)

        panel.contentView = contentView
        panel.orderFrontRegardless()
        self.panel = panel

        // Auto-dismiss after 15 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.close()
            }
        }
    }

    func close() {
        dismissTimer?.invalidate()
        dismissTimer = nil
        panel?.close()
        panel = nil
        onStartRecording = nil
        onDismiss = nil
    }

    @objc private func handleStartRecording() {
        let action = onStartRecording
        close()
        action?()
    }

    @objc private func handleDismiss() {
        let action = onDismiss
        close()
        action?()
    }
}
