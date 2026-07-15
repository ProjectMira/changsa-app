import FirebaseAuth
import SwiftUI

private struct CountryCode: Identifiable, Hashable {
    let name: String
    let dialCode: String
    var id: String { dialCode }
}

private let countryCodes: [CountryCode] = [
    .init(name: "India", dialCode: "+91"),
    .init(name: "Nepal", dialCode: "+977"),
    .init(name: "Bhutan", dialCode: "+975"),
    .init(name: "US / Canada", dialCode: "+1"),
    .init(name: "Switzerland", dialCode: "+41"),
    .init(name: "France", dialCode: "+33"),
    .init(name: "Germany", dialCode: "+49"),
    .init(name: "United Kingdom", dialCode: "+44"),
    .init(name: "Australia", dialCode: "+61"),
]

/// Firebase Phone Auth sign-in: country code + number, then a 6-digit SMS
/// code. A sibling to Apple/Google in SignInView — success routes through
/// the same SessionStore auth listener as any other provider.
struct PhoneSignInView: View {
    @Environment(\.dismiss) private var dismiss

    private enum Step {
        case enterNumber
        case enterCode(verificationID: String)
    }

    @State private var step: Step = .enterNumber
    @State private var countryCode = countryCodes[0]
    @State private var useCustomCode = false
    @State private var customDialCode = ""
    @State private var phoneNumber = ""
    @State private var code = ""
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0
    @State private var cooldownTask: Task<Void, Never>?

    private var dialCode: String { useCustomCode ? customDialCode : countryCode.dialCode }

    private var e164: String {
        "\(dialCode)\(phoneNumber.filter(\.isNumber))"
    }

    private var canContinue: Bool {
        guard !isWorking else { return false }
        guard dialCode.hasPrefix("+"), dialCode.count > 1 else { return false }
        return phoneNumber.filter(\.isNumber).count >= 6
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch step {
                case .enterNumber:
                    numberEntry
                case .enterCode:
                    codeEntry
                }
                Spacer()
            }
            .padding()
            .navigationTitle("Phone number")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay { if isWorking { ProgressView() } }
            .onDisappear { cooldownTask?.cancel() }
            .alert("Couldn't sign in", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var numberEntry: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Menu {
                    ForEach(countryCodes) { code in
                        Button("\(code.name) (\(code.dialCode))") {
                            useCustomCode = false
                            countryCode = code
                        }
                    }
                    Button("Other…") { useCustomCode = true }
                } label: {
                    HStack(spacing: 4) {
                        Text(useCustomCode ? "Other" : "\(countryCode.dialCode)")
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                }
                if useCustomCode {
                    TextField("+xx", text: $customDialCode)
                        .keyboardType(.phonePad)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                }
                TextField("Phone number", text: $phoneNumber)
                    .keyboardType(.phonePad)
                    .textFieldStyle(.roundedBorder)
            }
            Button("Continue") {
                Task { await sendCode() }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .disabled(!canContinue)
        }
    }

    private var codeEntry: some View {
        VStack(spacing: 16) {
            Text("Enter the 6-digit code sent to \(e164)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .multilineTextAlignment(.center)
                .font(.title2.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .onChange(of: code) {
                    code = String(code.filter(\.isNumber).prefix(6))
                    if code.count == 6 {
                        Task { await verifyCode() }
                    }
                }
            Button(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend code") {
                Task { await sendCode() }
            }
            .buttonStyle(.bordered)
            .disabled(resendCooldown > 0 || isWorking)
        }
    }

    private func sendCode() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let verificationID = try await AuthService.startPhoneVerification(e164)
            step = .enterCode(verificationID: verificationID)
            code = ""
            startResendCooldown()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func verifyCode() async {
        guard case .enterCode(let verificationID) = step else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.signInWithPhone(verificationID: verificationID, code: code)
            // SessionStore's auth listener takes over from here.
            dismiss()
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    private func startResendCooldown() {
        cooldownTask?.cancel()
        resendCooldown = 30
        cooldownTask = Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                resendCooldown -= 1
            }
        }
    }

    private static func friendlyMessage(for error: Error) -> String {
        let nsError = error as NSError
        switch AuthErrorCode(rawValue: nsError.code) {
        case .invalidPhoneNumber: return "That doesn't look like a valid phone number."
        case .missingPhoneNumber: return "Enter a phone number first."
        case .quotaExceeded: return "Too many attempts right now — try again in a bit."
        case .invalidVerificationCode: return "That code isn't right. Check and try again."
        case .sessionExpired, .invalidVerificationID: return "This code expired — request a new one."
        default: return error.localizedDescription
        }
    }
}
