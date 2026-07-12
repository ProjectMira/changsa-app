import SwiftUI

/// Form sections for the profile prompts (`Vocabulary.questions`), shared by
/// onboarding's About-you step and the profile editor. Binds straight into an
/// `answers` dictionary keyed by `ProfileQuestion.key`; empty answers are
/// stripped before submitting.
struct ProfileQuestionFields: View {
    @Binding var answers: [String: String]

    var body: some View {
        ForEach(Vocabulary.questions) { question in
            Section(question.label) {
                switch question.kind {
                case .choice(let options):
                    Picker(question.label, selection: binding(for: question.key)) {
                        Text("Skip").tag("")
                        ForEach(options, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                case .text(let placeholder):
                    TextField(placeholder, text: binding(for: question.key), axis: .vertical)
                        .lineLimit(1...4)
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<String> {
        Binding(
            get: { answers[key] ?? "" },
            set: { answers[key] = $0 }
        )
    }
}
