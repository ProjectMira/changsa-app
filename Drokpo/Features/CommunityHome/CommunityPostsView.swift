import PhotosUI
import SwiftUI

/// A community's own posts (published and unpublished) plus the composer for
/// creating new ones. Posting — and this whole tab being useful — is gated on
/// the community being verified; see PendingVerificationBanner.
struct CommunityPostsView: View {
    @Environment(SessionStore.self) private var session
    @State private var posts: [CommunityPostCard] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showComposer = false

    private var isVerified: Bool { session.myCommunity?.isVerified ?? false }
    private var myCid: String? { session.myCommunity?.uid ?? session.uid }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !isVerified {
                    PendingVerificationBanner()
                }
                List {
                    if posts.isEmpty && !isLoading {
                        ContentUnavailableView(
                            "No posts yet",
                            systemImage: "megaphone",
                            description: Text(
                                isVerified
                                    ? "Share an announcement, link, or poll with your members."
                                    : "You'll be able to publish once your community is verified."
                            )
                        )
                    } else {
                        ForEach(posts) { post in
                            CommunityPostRow(post: post)
                                .swipeActions {
                                    Button(post.active == false ? "Republish" : "Unpublish") {
                                        Task { await toggleActive(post) }
                                    }
                                    .tint(post.active == false ? .green : .orange)
                                }
                        }
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Posts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .disabled(!isVerified)
                }
            }
            .overlay { if isLoading && posts.isEmpty { ProgressView() } }
            .refreshable { await load() }
            .task { await load() }
            .sheet(isPresented: $showComposer) {
                CommunityPostComposerView {
                    await load()
                }
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
    }

    private func load() async {
        guard let myCid else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response: CommunityPostsResponse = try await APIClient.shared.get(
                "/api/communities/\(myCid)/posts",
                query: [URLQueryItem(name: "limit", value: "50")]
            )
            posts = response.posts ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleActive(_ post: CommunityPostCard) async {
        do {
            let _: EmptyResponse = try await APIClient.shared.patch(
                "/api/communities/me/posts/\(post.postId)",
                body: CommunityPostUpdate(active: !(post.active ?? true))
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct CommunityPostRow: View {
    let post: CommunityPostCard

    private var icon: String {
        switch post.kind {
        case "link": "link"
        case "poll": "chart.bar.fill"
        case "event": "calendar"
        default: "megaphone.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title ?? "")
                    .font(.headline)
                if let body = post.body, !body.isEmpty {
                    Text(body).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if post.active == false {
                    Text("Unpublished")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                if post.kind == "poll", let poll = post.poll {
                    Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if post.kind == "event" {
                    HStack(spacing: 8) {
                        if let date = post.eventDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                        }
                        Text("\(post.attendeeCount ?? 0) going")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Composer

private enum PostKind: String, CaseIterable, Identifiable {
    case announcement, link, poll, event
    var id: String { rawValue }
    var label: String {
        switch self {
        case .announcement: "Announcement"
        case .link: "Link"
        case .poll: "Poll"
        case .event: "Event"
        }
    }
}

/// A poll option being drafted. Identity-stable so removing a row can't
/// re-bind neighbours mid-update (the crash-prone indices+remove(at:) combo).
private struct PollOptionDraft: Identifiable {
    let id = UUID()
    var text = ""
}

struct CommunityPostComposerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PostKind = .announcement
    @State private var title = ""
    @State private var postBody = ""
    @State private var linkUrl = ""
    @State private var ctaLabel = ""
    @State private var pollOptions: [PollOptionDraft] = [PollOptionDraft(), PollOptionDraft()]
    @State private var eventDate = Date().addingTimeInterval(3600)
    @State private var eventLocation = ""
    @State private var photoSelection: PhotosPickerItem?
    @State private var pickedImage: UIImage?
    @State private var isSaving = false
    @State private var errorMessage: String?

    let onSaved: () async -> Void

    private var filledPollOptions: [String] {
        pollOptions.map { $0.text.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty, !isSaving else { return false }
        switch kind {
        case .announcement:
            return true
        case .link:
            return linkUrl.trimmingCharacters(in: .whitespaces).hasPrefix("https://")
        case .poll:
            let filled = filledPollOptions
            return filled.count >= 2 && Set(filled).count == filled.count
        case .event:
            let trimmedLink = linkUrl.trimmingCharacters(in: .whitespaces)
            let linkOK = trimmedLink.isEmpty || trimmedLink.hasPrefix("https://")
            return eventDate > Date() && linkOK
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Post type") {
                    Picker("Type", selection: $kind) {
                        ForEach(PostKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section(kind == .poll ? "Question" : (kind == .event ? "Event" : "Post")) {
                    TextField(kind == .poll ? "Ask a question" : (kind == .event ? "Event name" : "Title"), text: $title)
                    if kind != .poll {
                        TextField("Description", text: $postBody, axis: .vertical)
                            .lineLimit(3...8)
                    }
                }
                if kind == .event {
                    Section("Event details") {
                        DatePicker(
                            "Date & time",
                            selection: $eventDate,
                            in: Date()...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        TextField("Location (optional)", text: $eventLocation)
                    }
                }
                if kind == .link {
                    Section {
                        TextField("https://…", text: $linkUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Button label (optional, e.g. \"Register\")", text: $ctaLabel)
                    } header: {
                        Text("Link")
                    } footer: {
                        Text("Members open this in-app when they swipe right on your card.")
                    }
                }
                if kind == .event {
                    Section {
                        TextField("https://… (optional)", text: $linkUrl)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("Button label (optional, e.g. \"Register\")", text: $ctaLabel)
                    } header: {
                        Text("Registration link")
                    } footer: {
                        Text("Optional. Members open this in-app when they swipe right on your card.")
                    }
                }
                if kind == .poll {
                    Section {
                        ForEach($pollOptions) { $option in
                            HStack {
                                TextField("Poll option", text: $option.text)
                                if pollOptions.count > 2 {
                                    Button {
                                        pollOptions.removeAll { $0.id == option.id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        if pollOptions.count < 4 {
                            Button("Add option") { pollOptions.append(PollOptionDraft()) }
                        }
                    } header: {
                        Text("Options")
                    } footer: {
                        Text("2–4 options. Members can change their vote any time.")
                    }
                }
                Section("Photo (optional)") {
                    if let pickedImage {
                        Image(uiImage: pickedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 160)
                        Button("Remove photo", role: .destructive) {
                            self.pickedImage = nil
                            photoSelection = nil
                        }
                    }
                    PhotosPicker(pickedImage == nil ? "Choose photo" : "Replace photo",
                                 selection: $photoSelection, matching: .images)
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
            .onChange(of: photoSelection) {
                guard let item = photoSelection else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                    } else {
                        errorMessage = "That photo couldn't be loaded — try picking another one."
                    }
                }
            }
            .alert("Couldn't post", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            var photoStoragePath: String?
            if let pickedImage {
                photoStoragePath = try await PhotoUploader.uploadCommunityPhoto(pickedImage)
            }
            let payload = CommunityPostIn(
                kind: kind.rawValue,
                title: title.trimmingCharacters(in: .whitespaces),
                // The Description field is hidden for polls — don't let a
                // draft typed under another kind leak into the poll.
                body: kind == .poll ? "" : postBody,
                photoStoragePath: photoStoragePath,
                linkUrl: kind == .link
                    ? linkUrl.trimmingCharacters(in: .whitespaces)
                    : (kind == .event ? nonEmpty(linkUrl) : nil),
                ctaLabel: (kind == .link || kind == .event) ? nonEmpty(ctaLabel) : nil,
                pollOptions: kind == .poll ? filledPollOptions : nil,
                eventAt: kind == .event ? ISO8601DateFormatter().string(from: eventDate) : nil,
                location: kind == .event ? nonEmpty(eventLocation) : nil
            )
            let _: EmptyResponse = try await APIClient.shared.post("/api/communities/me/posts", body: payload)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
