import FluidAudio
import Foundation

/// Bridges real-time mic audio to VadManager's streaming API.
/// Emits chunk boundary signals on speechEnd events for VAD-driven rotation.
final class StreamingVadController {
    /// Called when VAD detects a natural speech boundary (rotation point).
    var onChunkBoundary: (() -> Void)?

    private let vadManager: VadManager
    private var streamState: VadStreamState?
    private var lastRotationTime: Date?
    private var isActive = false

    /// Minimum chunk duration before allowing rotation (prevents rapid flipping).
    private let minChunkDuration: TimeInterval = 3.0
    /// Maximum chunk duration before forcing rotation (safety cap).
    private let maxChunkDuration: TimeInterval = 60.0
    /// Timer for max duration fallback.
    private var maxDurationTimer: Timer?

    init(vadManager: VadManager) {
        self.vadManager = vadManager
    }

    func start() {
        isActive = true
        lastRotationTime = Date()

        // Initialize streaming state
        Task {
            streamState = await vadManager.makeStreamState()
        }

        // Max duration fallback timer
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.maxDurationTimer = Timer.scheduledTimer(withTimeInterval: self.maxChunkDuration, repeats: true) { [weak self] _ in
                guard let self, self.isActive else { return }
                fputs("[vad] max chunk duration reached, forcing rotation\n", stderr)
                self.lastRotationTime = Date()
                self.onChunkBoundary?()
            }
        }
    }

    func stop() {
        isActive = false
        maxDurationTimer?.invalidate()
        maxDurationTimer = nil
        streamState = nil
    }

    /// Feed a chunk of Float audio samples (4096 samples = 256ms at 16kHz).
    func processAudio(_ samples: [Float]) {
        guard isActive, let currentState = streamState else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.vadManager.processStreamingChunk(
                    samples,
                    state: currentState
                )
                self.streamState = result.state

                // Check for speech end event
                if let event = result.event, event.kind == .speechEnd {
                    let now = Date()
                    let elapsed = now.timeIntervalSince(self.lastRotationTime ?? now)

                    if elapsed >= self.minChunkDuration {
                        fputs("[vad] speech end detected at \(String(format: "%.1f", elapsed))s, rotating chunk\n", stderr)
                        self.lastRotationTime = now

                        // Reset max duration timer
                        DispatchQueue.main.async { [weak self] in
                            self?.maxDurationTimer?.fireDate = Date().addingTimeInterval(self?.maxChunkDuration ?? 60)
                        }

                        self.onChunkBoundary?()
                    }
                }
            } catch {
                // VAD failure is non-critical — chunk will rotate on max duration fallback
            }
        }
    }

    /// Notify that a rotation just happened (e.g., from external trigger).
    func notifyRotation() {
        lastRotationTime = Date()
        DispatchQueue.main.async { [weak self] in
            self?.maxDurationTimer?.fireDate = Date().addingTimeInterval(self?.maxChunkDuration ?? 60)
        }
    }
}
