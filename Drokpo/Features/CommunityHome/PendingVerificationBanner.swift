import SwiftUI

/// Shown across every community-account screen while `verification != "verified"`.
/// Registration is open — the community can post and appear in Discover right
/// away — so this is purely informational about what verification adds: the
/// checkmark seal, and (per the Discover deck) the ability to like people.
struct PendingVerificationBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting verification")
                    .font(.subheadline.bold())
                Text("You can post and appear in Discover right away. The verified badge — and liking people from the deck — unlock once your community is approved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.orange.opacity(0.12)))
        .padding(.horizontal)
        .padding(.top, 4)
    }
}
