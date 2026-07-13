import PhotosUI
import SwiftUI

/// The "Community" tab: editing every field collected at onboarding, plus
/// photo management. Unlike a person's profile, none of this is gated on
/// verification — a pending community can (and should) fill everything in
/// while it waits, per docs/COMMUNITIES.md.
struct CommunityProfileEditorView: View {
    @Environment(SessionStore.self) private var session

    @State private var name = ""
    @State private var communityDescription = ""
    @State private var website = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var contactName = ""
    @State private var contactRole = ""
    @State private var contactPhone = ""
    @State private var contactEmail = ""
    @State private var line1 = ""
    @State private var city = ""
    @State private var state = ""
    @State private var country = ""
    @State private var postalCode = ""
    @State private var instagram = ""
    @State private var youtube = ""
    @State private var tiktok = ""
    @State private var facebook = ""

    @State private var photoSelection: PhotosPickerItem?
    @State private var isSaving = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    private var community: CommunityProfile? { session.myCommunity }

    var body: some View {
        NavigationStack {
            Form {
                if community?.isVerified != true {
                    Section {
                        PendingVerificationBanner()
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                photosSection

                Section("About") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $communityDescription, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Contact info") {
                    TextField("Website (https://…)", text: $website)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section {
                    socialField("Instagram", text: $instagram)
                    socialField("YouTube", text: $youtube)
                    socialField("TikTok", text: $tiktok)
                    socialField("Facebook", text: $facebook)
                } header: {
                    Text("Social media")
                }

                Section("Person to contact") {
                    TextField("Name", text: $contactName)
                    TextField("Role", text: $contactRole)
                    TextField("Phone", text: $contactPhone)
                    TextField("Email", text: $contactEmail)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Address") {
                    TextField("Street address", text: $line1)
                    TextField("City", text: $city)
                    TextField("State / province", text: $state)
                    TextField("Country", text: $country)
                    TextField("Postal code", text: $postalCode)
                }

                Section("Status") {
                    HStack {
                        Text("Verification")
                        Spacer()
                        Text(community?.isVerified == true ? "Verified" : "Pending")
                            .foregroundStyle(community?.isVerified == true ? .green : .orange)
                    }
                    HStack {
                        Text("Members")
                        Spacer()
                        Text("\(community?.memberCount ?? 0)").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .overlay { if isWorking { ProgressView() } }
            .task { loadFromSession() }
            .onChange(of: session.myCommunity) { loadFromSession() }
            .refreshable { await session.refreshProfile() }
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

    private var photosSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(community?.photos ?? []) { photo in
                        RemotePhotoView(photo: photo)
                            .frame(width: 90, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Task { await deletePhoto(photo) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }
                    if (community?.photos?.count ?? 0) < 6 {
                        PhotosPicker(selection: $photoSelection, matching: .images) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 90, height: 120)
                                .overlay { Image(systemName: "plus") }
                        }
                    }
                }
            }
            .onChange(of: photoSelection) {
                guard let item = photoSelection else { return }
                photoSelection = nil
                Task { await addPhoto(item) }
            }
        } header: {
            Text("Photos")
        } footer: {
            Text("The first photo is used as your logo across the app.")
        }
    }

    private func socialField(_ title: String, text: Binding<String>) -> some View {
        HStack {
            Text(title)
            TextField("handle", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
    }

    private func loadFromSession() {
        guard let community else { return }
        name = community.name ?? ""
        communityDescription = community.description ?? ""
        website = community.website ?? ""
        phone = community.phone ?? ""
        email = community.email ?? ""
        contactName = community.contactPerson?.name ?? ""
        contactRole = community.contactPerson?.role ?? ""
        contactPhone = community.contactPerson?.phone ?? ""
        contactEmail = community.contactPerson?.email ?? ""
        line1 = community.address?.line1 ?? ""
        city = community.address?.city ?? ""
        state = community.address?.state ?? ""
        country = community.address?.country ?? ""
        postalCode = community.address?.postalCode ?? ""
        instagram = community.socials?.instagram ?? ""
        youtube = community.socials?.youtube ?? ""
        tiktok = community.socials?.tiktok ?? ""
        facebook = community.socials?.facebook ?? ""
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let body = CommunityUpdate(
            name: name.trimmingCharacters(in: .whitespaces),
            description: communityDescription.trimmingCharacters(in: .whitespaces),
            website: nonEmpty(website),
            phone: nonEmpty(phone),
            email: nonEmpty(email),
            contactPerson: ContactPerson(
                name: nonEmpty(contactName),
                role: nonEmpty(contactRole),
                phone: nonEmpty(contactPhone),
                email: nonEmpty(contactEmail)
            ),
            address: CommunityAddress(
                line1: nonEmpty(line1),
                city: nonEmpty(city),
                state: nonEmpty(state),
                country: nonEmpty(country),
                postalCode: nonEmpty(postalCode)
            ),
            socials: Socials(
                instagram: nonEmpty(instagram),
                youtube: nonEmpty(youtube),
                tiktok: nonEmpty(tiktok),
                facebook: nonEmpty(facebook)
            )
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.patch("/api/communities/me", body: body)
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPhoto(_ item: PhotosPickerItem) async {
        isWorking = true
        defer { isWorking = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                errorMessage = PhotoUploaderError.invalidImage.errorDescription
                return
            }
            let storagePath = try await PhotoUploader.uploadCommunityPhoto(image)
            let order = community?.photos?.count ?? 0
            let _: EmptyResponse = try await APIClient.shared.post(
                "/api/communities/me/photos",
                body: CommunityPhotoConfirm(storagePath: storagePath, order: order)
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePhoto(_ photo: Photo) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let _: EmptyResponse = try await APIClient.shared.delete(
                "/api/communities/me/photos",
                query: [URLQueryItem(name: "storage_path", value: photo.storagePath)]
            )
            await session.refreshProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
