import PhotosUI
import SwiftUI

struct CommunityOnboardingFlow: View {
    @Environment(SessionStore.self) private var session
    @State private var model = CommunityOnboardingModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(
                    value: Double(model.step.rawValue + 1),
                    total: Double(CommunityOnboardingModel.Step.allCases.count)
                )
                .padding(.horizontal)

                Group {
                    switch model.step {
                    case .basics: CommunityBasicsStep(model: model)
                    case .contact: CommunityContactStep(model: model)
                    case .contactPerson: CommunityContactPersonStep(model: model)
                    case .address: CommunityAddressStep(model: model)
                    case .photos: CommunityPhotosStep(model: model)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button {
                    Task {
                        await model.advance()
                        if model.completed {
                            await session.refreshProfile()
                        }
                    }
                } label: {
                    Group {
                        if model.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text(model.step == .photos ? "Finish" : "Continue")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canAdvance || model.isSubmitting)
                .padding()
            }
            .navigationTitle("Register your community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.step != .basics {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { model.back() }
                            .disabled(model.isSubmitting)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") { session.signOut() }
                }
            }
            .alert("Something went wrong", isPresented: .init(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }
}

// MARK: - Steps

private struct CommunityBasicsStep: View {
    @Bindable var model: CommunityOnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("Organization or community name", text: $model.name)
                TextField("Description", text: $model.communityDescription, axis: .vertical)
                    .lineLimit(4...8)
            } header: {
                Text("About your community")
            } footer: {
                Text("This is what members see first — say who you are and what you do.")
            }
        }
    }
}

private struct CommunityContactStep: View {
    @Bindable var model: CommunityOnboardingModel

    var body: some View {
        Form {
            Section("Contact info") {
                TextField("Website (https://…)", text: $model.website)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Phone", text: $model.phone)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $model.email)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section {
                socialField("Instagram", text: $model.instagram)
                socialField("YouTube", text: $model.youtube)
                socialField("TikTok", text: $model.tiktok)
                socialField("Facebook", text: $model.facebook)
            } header: {
                Text("Social media")
            } footer: {
                Text("All optional — add whichever accounts you use.")
            }
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
}

private struct CommunityContactPersonStep: View {
    @Bindable var model: CommunityOnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $model.contactName)
                TextField("Role (e.g. Coordinator)", text: $model.contactRole)
                TextField("Phone", text: $model.contactPhone)
                    .textContentType(.telephoneNumber)
                TextField("Email", text: $model.contactEmail)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Person to contact")
            } footer: {
                Text("Who should members or Drokpo reach out to with questions? Name is required.")
            }
        }
    }
}

private struct CommunityAddressStep: View {
    @Bindable var model: CommunityOnboardingModel

    var body: some View {
        Form {
            Section {
                TextField("Street address", text: $model.line1)
                TextField("City", text: $model.city)
                TextField("State / province", text: $model.state)
                TextField("Country", text: $model.country)
                TextField("Postal code", text: $model.postalCode)
            } header: {
                Text("Address")
            } footer: {
                Text("City and country are required.")
            }
        }
    }
}

private struct CommunityPhotosStep: View {
    @Bindable var model: CommunityOnboardingModel
    @State private var selection: [PhotosPickerItem] = []

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]

    var body: some View {
        VStack(spacing: 16) {
            Text("Add a logo and photos")
                .font(.title2.bold())
            Text("Optional — the first photo becomes your logo. You can add or change these later.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(model.pickedImages.enumerated()), id: \.offset) { index, image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 133)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.pickedImages.remove(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white, .black.opacity(0.6))
                                }
                                .padding(4)
                            }
                    }
                    if model.pickedImages.count < 6 {
                        PhotosPicker(
                            selection: $selection,
                            maxSelectionCount: 6 - model.pickedImages.count,
                            matching: .images
                        ) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: 100, height: 133)
                                .overlay { Image(systemName: "plus").font(.title2) }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .onChange(of: selection) {
            let items = selection
            selection = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        model.pickedImages.append(image)
                    }
                }
            }
        }
    }
}
