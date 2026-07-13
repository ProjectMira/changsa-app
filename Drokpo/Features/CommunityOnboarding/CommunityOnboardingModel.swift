import SwiftUI

@Observable
final class CommunityOnboardingModel {
    enum Step: Int, CaseIterable {
        case basics, contact, contactPerson, address, photos
    }

    var step: Step = .basics

    // Basics
    var name = ""
    var communityDescription = ""

    // Contact
    var website = ""
    var phone = ""
    var email = ""
    var instagram = ""
    var youtube = ""
    var tiktok = ""
    var facebook = ""

    // Contact person
    var contactName = ""
    var contactRole = ""
    var contactPhone = ""
    var contactEmail = ""

    // Address
    var line1 = ""
    var city = ""
    var state = ""
    var country = ""
    var postalCode = ""

    // Photos
    var pickedImages: [UIImage] = []

    var isSubmitting = false
    var errorMessage: String?
    /// True once POST /api/communities/onboarding (and any picked photos)
    /// succeed; the view uses this to hand control back to SessionStore.
    var completed = false

    var canAdvance: Bool {
        switch step {
        case .basics:
            return !name.trimmed.isEmpty && !communityDescription.trimmed.isEmpty
        case .contact:
            return true // every field here is optional
        case .contactPerson:
            return !contactName.trimmed.isEmpty
        case .address:
            return !city.trimmed.isEmpty && !country.trimmed.isEmpty
        case .photos:
            return true // no photo is required to finish
        }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    /// Leaving the address step creates the community on the backend (all
    /// text fields collected so far); leaving the photos step just finishes —
    /// any picked photos upload first.
    @MainActor
    func advance() async {
        guard canAdvance else { return }
        switch step {
        case .address:
            await createCommunity()
        case .photos:
            await uploadPhotosAndFinish()
        default:
            step = Step(rawValue: step.rawValue + 1) ?? step
        }
    }

    private func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmed
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    private func createCommunity() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let socials = Socials(
            instagram: nonEmpty(instagram),
            youtube: nonEmpty(youtube),
            tiktok: nonEmpty(tiktok),
            facebook: nonEmpty(facebook)
        )
        let body = CommunityOnboardingIn(
            name: name.trimmed,
            description: communityDescription.trimmed,
            website: nonEmpty(website),
            phone: nonEmpty(phone),
            email: nonEmpty(email),
            contactPerson: ContactPerson(
                name: contactName.trimmed,
                role: nonEmpty(contactRole),
                phone: nonEmpty(contactPhone),
                email: nonEmpty(contactEmail)
            ),
            address: CommunityAddress(
                line1: nonEmpty(line1),
                city: city.trimmed,
                state: nonEmpty(state),
                country: country.trimmed,
                postalCode: nonEmpty(postalCode)
            ),
            socials: socials
        )
        do {
            let _: EmptyResponse = try await APIClient.shared.post("/api/communities/onboarding", body: body)
            step = .photos
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Photos confirmed with the backend so far — same resume-after-failure
    /// bookkeeping as OnboardingModel's person-photo upload.
    private var confirmedPhotoCount = 0

    @MainActor
    private func uploadPhotosAndFinish() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            for (index, image) in pickedImages.enumerated().dropFirst(confirmedPhotoCount) {
                let storagePath = try await PhotoUploader.uploadCommunityPhoto(image)
                let _: EmptyResponse = try await APIClient.shared.post(
                    "/api/communities/me/photos",
                    body: CommunityPhotoConfirm(storagePath: storagePath, order: index)
                )
                confirmedPhotoCount = index + 1
            }
            completed = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
