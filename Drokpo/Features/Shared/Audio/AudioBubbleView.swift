import SwiftUI

/// A play/pause button + progress bar + duration for a voice clip — used in
/// both chat bubbles and comment rows. Playback goes through the shared
/// AudioPlaybackCenter, so starting one clip stops any other playing.
struct AudioBubbleView: View {
    let id: String
    let url: URL
    let durationSec: Int
    /// True for the sender's own outgoing chat bubble — flips to a
    /// light-on-tint palette instead of the default foreground/secondary one.
    var isOnTintBackground: Bool = false

    private let center = AudioPlaybackCenter.shared

    private var isPlaying: Bool { center.playingId == id }
    private var progress: Double { isPlaying ? center.progress : 0 }
    private var foreground: Color { isOnTintBackground ? .white : .primary }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                center.play(id: id, url: url)
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(foreground)
            }
            .buttonStyle(.plain)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(foreground.opacity(0.25))
                    Capsule().fill(foreground)
                        .frame(width: geometry.size.width * max(0.03, progress))
                }
            }
            .frame(height: 4)

            Text(durationLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(foreground.opacity(0.8))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(minWidth: 140)
    }

    private var durationLabel: String {
        let remaining = isPlaying ? max(0, durationSec - Int((progress * Double(durationSec)).rounded())) : durationSec
        return String(format: "%d:%02d", remaining / 60, remaining % 60)
    }
}
