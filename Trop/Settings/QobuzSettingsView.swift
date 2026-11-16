import SwiftUI

/// Qobuz account settings are intentionally opt-in. Credentials remain in the
/// iOS Keychain and are never committed, shared, or shown after saving.
struct QobuzSettingsView: View {
    @State private var appId = ""
    @State private var appSecret = ""
    @State private var userAuthToken = ""
    @State private var isConfigured = false
    @State private var isSaving = false
    @State private var status: String?

    var body: some View {
        Form {
            Section {
                TextField("Application ID", text: $appId)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Application secret", text: $appSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("User authentication token", text: $userAuthToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button("Save credentials") {
                    saveCredentials()
                }
                .disabled(isSaving || appId.isEmpty || appSecret.isEmpty || userAuthToken.isEmpty)
            } header: {
                Text("Your Qobuz account")
            } footer: {
                Text("Use credentials you are authorized to use. Full-track streaming requires an eligible Qobuz account and permission to use the API. No community tokens are bundled.")
            }

            Section {
                LabeledContent("Connection", value: isConfigured ? "Configured" : "Not configured")
                if isConfigured {
                    Button("Remove credentials", role: .destructive) {
                        removeCredentials()
                    }
                    .disabled(isSaving)
                }
                if let status {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                }
            } footer: {
                Text("This saves credentials locally in Keychain; it does not verify that Qobuz will authorize full-length playback.")
            }
        }
        .navigationTitle("Qobuz")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isConfigured = await QobuzCredentialStore.shared.isConfigured()
        }
    }

    private func saveCredentials() {
        isSaving = true
        status = nil
        let credentials = QobuzCredentials(
            appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
            appSecret: appSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            userAuthToken: userAuthToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        Task {
            do {
                try await QobuzCredentialStore.shared.save(credentials)
                isConfigured = true
                appId = ""
                appSecret = ""
                userAuthToken = ""
                status = "Saved securely. Search again to see eligible Qobuz tracks."
            } catch {
                status = "Could not save credentials. Check the fields and try again."
            }
            isSaving = false
        }
    }

    private func removeCredentials() {
        isSaving = true
        status = nil
        Task {
            do {
                try await QobuzCredentialStore.shared.remove()
                isConfigured = false
                appId = ""
                appSecret = ""
                userAuthToken = ""
                status = "Qobuz credentials removed."
            } catch {
                status = "Could not remove credentials from Keychain."
            }
            isSaving = false
        }
    }
}
