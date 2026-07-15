import AVFoundation
import Foundation

/// Plays one voice clip at a time, app-wide — starting a new clip stops
/// whatever was already playing. Downloads remote audio to a small temp
/// file cache keyed by URL (voice clips are short; re-playing the same clip
/// within a session skips the network).
@Observable
@MainActor
final class AudioPlaybackCenter: NSObject {
    static let shared = AudioPlaybackCenter()

    private(set) var playingId: String?
    /// 0...1 progress of the currently playing clip.
    private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var progressTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    /// Tapping the clip that's already playing stops it (a pause gesture);
    /// tapping any other clip stops the current one and starts the new one.
    func play(id: String, url: URL) {
        if playingId == id {
            stop()
            return
        }
        stop()
        Task {
            do {
                let localURL = try await Self.cachedFile(for: url)
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, options: [.mixWithOthers])
                try session.setActive(true)
                let player = try AVAudioPlayer(contentsOf: localURL)
                player.delegate = self
                player.play()
                self.player = player
                playingId = id
                startProgressLoop()
            } catch {
                // Silent — a failed voice-clip playback shouldn't surface an alert.
            }
        }
    }

    func stop() {
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        player = nil
        playingId = nil
        progress = 0
    }

    private func startProgressLoop() {
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                guard let player, player.isPlaying else { continue }
                progress = player.duration > 0 ? player.currentTime / player.duration : 0
            }
        }
    }

    private static var cacheDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("voice-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cachedFile(for url: URL) async throws -> URL {
        // A composer's just-recorded preview clip is already a local file —
        // play it directly instead of round-tripping it through the cache.
        if url.isFileURL { return url }
        let fileName = "\(abs(url.absoluteString.hashValue)).m4a"
        let localURL = cacheDirectory.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: localURL.path) {
            return localURL
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        try data.write(to: localURL)
        return localURL
    }
}

extension AudioPlaybackCenter: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
