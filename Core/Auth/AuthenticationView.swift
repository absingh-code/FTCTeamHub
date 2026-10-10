import SwiftUI
import GoogleSignIn

struct AuthenticationView: View {
    @Environment(AuthenticationViewModel.self) private var authVM

    var body: some View {
        VStack(spacing: DS.Spacing.xxl) {
            Spacer()

            Text("FTC Team Hub")
                .font(DS.Font.display)
                .foregroundStyle(DS.Color.labelPrimary)

            Text("Sign in with your team Google account")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.labelSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Spacing.xxl)

            Button {
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let root = scene.windows.first?.rootViewController else { return }
                Task { await authVM.signIn(presenting: root) }
            } label: {
                Text("Continue with Google")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.labelPrimary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(DS.Color.raised, in: RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous))
            }
            .padding(.horizontal, DS.Spacing.xxl)

            if case .error(let msg) = authVM.authState {
                Text(msg)
                    .font(DS.Font.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, DS.Spacing.xxl)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DS.Color.background)
    }
}
