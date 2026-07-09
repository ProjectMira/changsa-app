import SwiftUI

struct MainTabView: View {
    @Environment(SessionStore.self) private var session
    @State private var chats = ChatStore()

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Discover", systemImage: "rectangle.stack.fill") }
            LikesView()
                .tabItem { Label("Likes", systemImage: "heart.fill") }
            ChatsView()
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chats.totalUnread)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .environment(chats)
        .onAppear {
            if let uid = session.uid { chats.start(uid: uid) }
        }
        .onDisappear { chats.stop() }
    }
}
