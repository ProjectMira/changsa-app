import SwiftUI

/// Root tab view for community accounts — a completely different experience
/// from MainTabView: no swiping, likes, or chats, just managing the
/// community's public presence.
struct CommunityTabView: View {
    enum Tab: Hashable {
        case posts, community, settings
    }

    @Environment(SessionStore.self) private var session
    @State private var selection: Tab = .posts

    var body: some View {
        TabView(selection: $selection) {
            CommunityPostsView()
                .tabItem { Label("Posts", systemImage: "megaphone.fill") }
                .tag(Tab.posts)
            CommunityProfileEditorView()
                .tabItem { Label("Community", systemImage: "building.2.fill") }
                .tag(Tab.community)
            CommunitySettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
    }
}
