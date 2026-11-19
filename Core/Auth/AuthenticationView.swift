import SwiftUI

struct AuthenticationView: View {
    @Environment(AuthenticationViewModel.self) private var auth

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xxxl) {
                TeamIdentity()

                VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                    Text("Team Hub")
                        .font(DS.Font.display)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your match schedule, scouting reports and pit checks in one place.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: DS.Spacing.md) {
                    if auth.isGoogleConfigured {
                        Button {
                            Task { await auth.signIn() }
                        } label: {
                            Group {
                                if auth.isSigningIn {
                                    ProgressView().tint(.white)
                                        .accessibilityLabel("Signing in with Google")
                                } else {
                                    Text("Continue with Google")
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(auth.isSigningIn)
                    } else {
                        Label("Google Sign-In needs to be configured for this build.", systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button { auth.openDeviceWorkspace() } label: {
                        Label("Use On This Device", systemImage: "iphone")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(auth.isSigningIn)
                    Text("On-device reports and team records are stored in this workspace on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if case .error(let message) = auth.authState {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
            .frame(maxWidth: 430)
            .padding(.horizontal, DS.Spacing.xxl)
            .padding(.vertical, 56)
            .frame(maxWidth: .infinity)
        }
        .background(DS.Color.background)
    }
}
