import SwiftUI
import SwiftData

struct TeamTabView: View {
    @Query(sort: \AppUser.name) private var members: [AppUser]
    @Environment(AuthenticationViewModel.self) private var authVM
    @State private var search = ""

    var filtered: [AppUser] {
        if search.isEmpty { return members }
        return members.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let current = authVM.currentUser {
                    Section("You") {
                        MemberRow(user: current)
                    }
                }

                Section("Roster") {
                    ForEach(filtered) { user in
                        MemberRow(user: user)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(DS.Color.background)
            .searchable(text: $search, prompt: "Search members")
            .navigationTitle("Team")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        ChatView()
                    } label: {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out") {
                        authVM.signOut()
                    }
                }
            }
            .overlay {
                if members.isEmpty && authVM.currentUser == nil {
                    ContentUnavailableView(
                        "No members",
                        systemImage: "person.2",
                        description: Text("Team members appear after they sign in.")
                    )
                }
            }
        }
    }
}

struct MemberRow: View {
    let user: AppUser

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            AvatarView(url: user.profileImageURL, name: user.name)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(user.name)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.labelPrimary)
                Text(user.role)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.labelSecondary)
            }
            Spacer()
            if user.isActive {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
    }
}

struct AvatarView: View {
    let url: String?
    let name: String

    var body: some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(String(name.prefix(1)).uppercased())
            .font(DS.Font.label)
            .foregroundStyle(DS.Color.labelPrimary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Color.raised)
    }
}

struct ChatView: View {
    @State private var messages: [String] = []
    @State private var draft = ""
    @State private var isConnected = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            if let error = errorMessage {
                Text(error)
                    .font(DS.Font.caption)
                    .foregroundStyle(.red)
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.raised)
            }

            if !isConnected {
                Text("Offline — messages will send when connected")
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.labelSecondary)
                    .padding(DS.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.surface)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Spacing.md) {
                    ForEach(messages, id: \.self) { msg in
                        Text(msg)
                            .font(DS.Font.body)
                            .padding(DS.Spacing.md)
                            .background(DS.Color.raised, in: RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous))
                    }
                }
                .padding(DS.Spacing.lg)
            }

            HStack(spacing: DS.Spacing.sm) {
                TextField("Message", text: $draft)
                    .textFieldStyle(.roundedBorder)
                Button {
                    guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    messages.append(draft)
                    draft = ""
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(DS.Spacing.lg)
            .background(DS.Color.surface)
        }
        .background(DS.Color.background)
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Opt-in Firebase connection would set isConnected / errorMessage
            isConnected = false
            errorMessage = nil
        }
    }
}
