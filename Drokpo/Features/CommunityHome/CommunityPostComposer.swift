import PhotosUI
import SwiftUI

/// The composer for all four post kinds — announcement, link, poll, event.
/// Posting is open to any registered community, verified or not — see
/// PendingVerificationBanner for what verification actually unlocks.
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
