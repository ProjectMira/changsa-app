import FirebaseFirestore
import SwiftUI

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let senderId: String
    let text: String
    let createdAt: Date
}

struct ChatThreadView: View {
    @Environment(SessionStore.self) private var session
    @Environment(ChatStore.self) private var chats

    let entry: ChatStore.Entry

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var registration: ListenerRegistration?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            bubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages) {
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
                .onAppear {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            inputBar
        }
        .navigationTitle(entry.otherUser?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let other = entry.otherUser {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ProfileDetailView(card: other)
                    } label: {
                        RemotePhotoView(photo: other.photos?.first)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    }
                }
            }
        }
        .onAppear { attachListener() }
        .onDisappear {
            registration?.remove()
            registration = nil
        }
        .alert("Something went wrong", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func bubble(_ message: ChatMessage) -> some View {
        let isMine = message.senderId == session.uid
        return HStack {
            if isMine { Spacer(minLength: 48) }
            Text(message.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(isMine ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                )
                .foregroundStyle(isMine ? .white : .primary)
            if !isMine { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Message…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(.quaternary))
            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func attachListener() {
        guard registration == nil else { return }
        registration = Firestore.firestore()
            .collection("matches").document(entry.matchId)
            .collection("messages")
            .order(by: "createdAt")
            .limit(toLast: 100)
            .addSnapshotListener { snapshot, error in
                if let error {
                    errorMessage = error.localizedDescription
                    return
                }
                messages = (snapshot?.documents ?? []).compactMap { doc in
                    // .estimate resolves pending server timestamps so our own
                    // just-sent messages don't jump around when the write lands.
                    let data = doc.data(with: .estimate)
                    guard let senderId = data["senderId"] as? String,
                          let text = data["text"] as? String else { return nil }
                    return ChatMessage(
                        id: doc.documentID,
                        senderId: senderId,
                        text: text,
                        createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now
                    )
                }
                markRead()
            }
    }

    private func markRead() {
        guard entry.unread > 0 || messages.last?.senderId != session.uid else { return }
        chats.clearUnread(matchId: entry.matchId)
        Task {
            let _: EmptyResponse? = try? await APIClient.shared.post("/api/matches/\(entry.matchId)/read")
        }
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let uid = session.uid else { return }
        isSending = true
        defer { isSending = false }
        do {
            // Direct Firestore write — the security rules verify participation,
            // active status, and senderId; the on_message_created Cloud Function
            // handles lastMessage/unreadCount denormalization and the push.
            try await Firestore.firestore()
                .collection("matches").document(entry.matchId)
                .collection("messages")
                .addDocument(data: [
                    "senderId": uid,
                    "text": text,
                    "imageUrl": NSNull(),
                    "createdAt": FieldValue.serverTimestamp(),
                    "readAt": NSNull(),
                ])
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
