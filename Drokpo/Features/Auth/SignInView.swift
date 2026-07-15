import AuthenticationServices
import SwiftUI

struct SignInView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var errorMessage: String?
    @State private var isSigningIn = false
    @State private var showPhoneSignIn = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 96, height: 96)
                Text("Drokpo")
                    .font(.largeTitle.bold())
                Text("Make friends and find your people in the Tibetan community")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.signIn) { request in
                    AuthService.prepareAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        signIn { try await AuthService.completeAppleSignIn(authorization) }
                    case .failure(let error):
                        if (error as? ASAuthorizationError)?.code != .canceled {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: 50)

                Button {
                    signIn { try await AuthService.signInWithGoogle() }
                } label: {
                    HStack {
                        Image(systemName: "g.circle.fill")
                        Text("Sign in with Google")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)

                Button {
                    showPhoneSignIn = true
                } label: {
                    HStack {
                        Image(systemName: "phone.fill")
                        Text("Continue with phone")
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.bordered)

                Text("You must be 18 or older to use Drokpo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .disabled(isSigningIn)
        }
        .overlay {
            if isSigningIn { ProgressView() }
        }
        .sheet(isPresented: $showPhoneSignIn) {
            PhoneSignInView()
        }
        .alert("Sign-in failed", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func signIn(_ operation: @escaping () async throws -> Void) {
        isSigningIn = true
        Task {
            defer { isSigningIn = false }
            do {
                try await operation()
                // SessionStore's auth listener takes over from here.
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
