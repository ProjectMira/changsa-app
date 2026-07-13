import SwiftUI

/// Settings for a community account — the same appearance/about/account
/// pieces as the person-side SettingsView, minus anything person-specific
/// (blocked users, sent messages) that doesn't apply to a community.
struct CommunitySettingsView: View {
    @Environment(SessionStore.self) private var session

    @AppStorage("drokpo.appearance") private var appearance: AppearanceMode = .system
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $appearance) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section("About") {
                    Link(destination: AppConfig.privacyPolicyURL) {
                        HStack {
                            Text("Privacy policy")
                            Spacer()
                            Image(systemName: "arrow.up.right").foregroundStyle(.secondary)
                        }
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(appVersion).foregroundStyle(.secondary)
                    }
                }
                Section("Account") {
                    HStack {
                        Text("Signed in as")
                        Spacer()
                        Text(session.email ?? "—").foregroundStyle(.secondary)
                    }
                    Button("Sign out") { session.signOut() }
                    Button("Delete community", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .disabled(isDeleting)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .overlay { if isDeleting { ProgressView() } }
            .confirmationDialog(
                "Delete this community?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive) {
                    Task { await deleteCommunity() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your community's profile, photos, and posts will be permanently removed. This cannot be undone.")
            }
            .alert("Couldn't delete community", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func deleteCommunity() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete("/api/communities/me")
            session.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
