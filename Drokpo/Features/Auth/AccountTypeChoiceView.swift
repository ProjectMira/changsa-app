import SwiftUI

/// Shown once, right after first sign-in, before either onboarding endpoint
/// has been called — purely local routing (SessionStore.chooseAccountType).
/// The account only becomes real once the matching onboarding flow submits.
struct AccountTypeChoiceView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 8) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                    Text("Welcome to Drokpo")
                        .font(.title2.bold())
                    Text("How will you be using Drokpo?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 16) {
                    choiceCard(
                        icon: "person.fill",
                        title: "I'm here to make friends",
                        subtitle: "Build a personal profile, swipe to meet people nearby and across the diaspora.",
                        action: { session.chooseAccountType(.person) }
                    )
                    choiceCard(
                        icon: "building.2.fill",
                        title: "Register a community or organization",
                        subtitle: "Share announcements, events, and polls with the community.",
                        footnote: "Community accounts are reviewed before they appear publicly.",
                        action: { session.chooseAccountType(.community) }
                    )
                }
                .padding(.horizontal, 20)

                Spacer()
                Spacer()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { session.signOut() }
                }
            }
        }
    }

    private func choiceCard(
        icon: String,
        title: String,
        subtitle: String,
        footnote: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let footnote {
                        Text(footnote)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}
