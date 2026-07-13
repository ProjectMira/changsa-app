import SwiftUI

/// Shown across every community-account screen while `verification != "verified"`
/// — the account can still edit everything and upload photos, it just can't
/// post yet and won't show up publicly (see backend docs/COMMUNITIES.md).
struct PendingVerificationBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting verification")
                    .font(.subheadline.bold())
                Text("Complete your profile now — posting unlocks, and you'll appear publicly, once you're verified.")
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
