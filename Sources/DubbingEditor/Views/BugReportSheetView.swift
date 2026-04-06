import SwiftUI

struct BugReportSheetView: View {
    private enum SubmitMode {
        case createOnly
        case createAndEmail
    }

    @Environment(\.dismiss) private var dismiss

    @AppStorage("bug_report_recipient_email") private var bugReportRecipientEmail = "info@kiulpekidis.me"
    let destinationURL: URL
    let onCreate: @MainActor (BugReportDraft) async throws -> URL
    let onCreateAndEmail: @MainActor (BugReportDraft) async throws -> URL

    @State private var draft: BugReportDraft
    @State private var isSubmitting = false
    @State private var currentSubmitMode: SubmitMode = .createOnly
    @State private var submissionErrorMessage: String?

    init(
        destinationURL: URL,
        initialDraft: BugReportDraft,
        onCreate: @escaping @MainActor (BugReportDraft) async throws -> URL,
        onCreateAndEmail: @escaping @MainActor (BugReportDraft) async throws -> URL
    ) {
        self.destinationURL = destinationURL
        self.onCreate = onCreate
        self.onCreateAndEmail = onCreateAndEmail
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Nahlasit bug")
                .font(.title2.weight(.semibold))

            Text("Report se ulozi lokalne jako samostatny bundle se screenshotem, logy a stavem projektu.")
                .foregroundStyle(.secondary)

            Form {
                TextField("Krátký název", text: $draft.title)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Kroky k reprodukci")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.reproductionSteps)
                        .frame(minHeight: 90)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Očekávané chování")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.expectedBehavior)
                        .frame(minHeight: 70)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Skutečné chování")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.actualBehavior)
                        .frame(minHeight: 70)
                        .font(.body)
                }

                Toggle("Přiložit screenshot hlavního okna", isOn: $draft.includeWindowScreenshot)
                Toggle("Přiložit logy", isOn: $draft.includeLogs)
                Toggle("Přiložit snapshot projektu", isOn: $draft.includeProjectSnapshot)
            }
            .formStyle(.grouped)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cilova slozka")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(destinationURL.path)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Bug report e-mail")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if bugReportRecipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Neni nastaven. Nastav ho v Nastaveni > Obecne.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(bugReportRecipientEmail)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                if isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                    Text(submissionProgressLabel)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                Spacer()

                Button("Zrusit") {
                    dismiss()
                }
                .disabled(isSubmitting)

                Button("Vytvorit report") {
                    submit(.createOnly)
                }
                .disabled(isSubmitting)

                Button("Vytvorit a odeslat mailem") {
                    submit(.createAndEmail)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting || bugReportRecipientEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 720, height: 700)
        .alert(
            "Report se nepodarilo vytvorit",
            isPresented: Binding(
                get: { submissionErrorMessage != nil },
                set: { visible in
                    if !visible {
                        submissionErrorMessage = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {}
            },
            message: {
                Text(submissionErrorMessage ?? "")
            }
        )
    }

    private var submissionProgressLabel: String {
        switch currentSubmitMode {
        case .createOnly:
            return "Vytvarim report..."
        case .createAndEmail:
            return "Pripravuji report a e-mail..."
        }
    }

    @MainActor
    private func submit(_ mode: SubmitMode) {
        guard !isSubmitting else { return }
        isSubmitting = true
        currentSubmitMode = mode

        Task {
            do {
                switch mode {
                case .createOnly:
                    let reportURL = try await onCreate(draft)
                    NSWorkspace.shared.activateFileViewerSelecting([reportURL])
                case .createAndEmail:
                    _ = try await onCreateAndEmail(draft)
                }
                dismiss()
            } catch {
                submissionErrorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
