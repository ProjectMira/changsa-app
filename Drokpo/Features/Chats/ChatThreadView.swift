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
    @Environment(\.dismiss) private var dismiss

    let matchId: String

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var registration: ListenerRegistration?
    /// Last message id we've sent a read receipt for, so snapshot churn
    /// doesn't spam POST /read.
    @State private var lastMarkedMessageId: String?
    @State private var errorMessage: String?
    @State private var showUnmatchConfirm = false
    @State private var showBlockConfirm = false
    @State private var showReportDialog = false

    /// The live match entry, looked up by id every render so unread/profile
    /// stay current — and nil during a push deep-link cold start before the
    /// ChatStore listener has delivered this match.
    private var entry: ChatStore.Entry? {
        chats.entries.first { $0.matchId == matchId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            let meta = metadata(at: index)
                            if let day = meta.daySeparator {
                                daySeparator(day)
                            }
                            bubble(message)
                                .id(message.id)
                            if let time = meta.timestamp {
                                timestampCaption(time, isMine: message.senderId == session.uid)
                            }
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
        .navigationTitle(entry?.otherUser?.displayName ?? "Chat")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let other = entry?.otherUser {
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
            if entry != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Unmatch", role: .destructive) { showUnmatchConfirm = true }
                        Button("Block", role: .destructive) { showBlockConfirm = true }
                        Button("Report") { showReportDialog = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
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
        .confirmationDialog("Unmatch?", isPresented: $showUnmatchConfirm, titleVisibility: .visible) {
            Button("Unmatch", role: .destructive) { Task { await unmatch() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer see each other or be able to message.")
        }
        .confirmationDialog("Block this person?", isPresented: $showBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) { Task { await block() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They won't be able to message you, and you'll be unmatched.")
        }
        .confirmationDialog("Report this person", isPresented: $showReportDialog, titleVisibility: .visible) {
            ForEach(Vocabulary.reportReasons, id: \.self) { reason in
                Button(reason) { Task { await report(reason: reason) } }
            }
            Button("Cancel", role: .cancel) {}
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

    // MARK: - Timestamps

    /// What to render around the message at `index`: an optional day-separator
    /// chip above, and an optional time caption below.
    private struct RowMetadata {
        var daySeparator: Date?
        var timestamp: Date?
    }

    private func metadata(at index: Int) -> RowMetadata {
        let message = messages[index]
        var meta = RowMetadata()
        let calendar = Calendar.current
        if index == 0 || !calendar.isDate(message.createdAt, inSameDayAs: messages[index - 1].createdAt) {
            meta.daySeparator = message.createdAt
        }
        if index == messages.count - 1 {
            meta.timestamp = message.createdAt
        } else {
            let next = messages[index + 1]
            // End of a consecutive run from the same sender, or a gap over 10
            // minutes to the next message.
            if next.senderId != message.senderId
                || next.createdAt.timeIntervalSince(message.createdAt) > 600 {
                meta.timestamp = message.createdAt
            }
        }
        return meta
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(daySeparatorText(date))
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.quaternary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func daySeparatorText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    private func timestampCaption(_ date: Date, isMine: Bool) -> some View {
        Text(date.formatted(date: .omitted, time: .shortened))
            .font(.caption2)
            .foregroundStyle(.secondary)
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
            .collection("matches").document(matchId)
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
        // Reads the live entry (not a stale captured copy), so the unread guard
        // reflects the current count.
        guard (entry?.unread ?? 0) > 0 || messages.last?.senderId != session.uid else { return }
        // The listener fires on every snapshot (including our own sends and
        // presence-style updates); only POST when there's actually a new
        // incoming message since the last read receipt.
        guard let lastId = messages.last?.id, lastId != lastMarkedMessageId else { return }
        lastMarkedMessageId = lastId
        chats.clearUnread(matchId: matchId)
        Task {
            let _: EmptyResponse? = try? await APIClient.shared.post("/api/matches/\(matchId)/read")
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
                .collection("matches").document(matchId)
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

    // MARK: - Thread actions

    private func unmatch() async {
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/matches/\(matchId)/unmatch")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func block() async {
        guard let otherUid = entry?.otherUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/blocks/\(otherUid)")
            BlockStore.shared.record(uid: otherUid, displayName: entry?.otherUser?.displayName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func report(reason: String) async {
        guard let otherUid = entry?.otherUid else { return }
        do {
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/reports",
                body: ReportIn(reportedUid: otherUid, reason: reason, note: "")
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
