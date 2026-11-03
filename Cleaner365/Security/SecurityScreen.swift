import SafariServices
import SwiftUI
import UniformTypeIdentifiers

enum SecurityTool: Int, CaseIterable, Hashable {
    case generator, aliases, email, password
    var title: String {
        switch self {
        case .generator: "Password generator"
        case .aliases: "Email aliases"
        case .email: "Email breach check"
        case .password: "Password breach check"
        }
    }
    var detail: String {
        switch self {
        case .generator: "Build a random password on this iPhone"
        case .aliases: "Forward mail to your own inbox"
        case .email: "Find breaches linked to your address"
        case .password: "Check for an exposed password"
        }
    }
    var icon: String {
        switch self {
        case .generator: "key.fill"
        case .aliases: "envelope.badge.shield.half.filled"
        case .email: "at"
        case .password: "lock.shield.fill"
        }
    }
    @ViewBuilder var destination: some View {
        switch self {
        case .generator: GeneratorScreen()
        case .aliases: AliasScreen()
        case .email: EmailBreachScreen()
        case .password: PasswordBreachScreen()
        }
    }
}

struct SecurityScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    TimingLabel("365 / FIELD KIT").foregroundStyle(Color.track)
                    Text("Security").font(.system(.largeTitle, design: .rounded, weight: .black))
                    Text("Protect your sign-ins and check for exposure.").font(.subheadline)
                        .frame(maxWidth: 235, alignment: .leading)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(alignment: .trailing) { TrackMark().frame(width: 104).clipped().opacity(0.48) }
                    .background(Color.lane).clipShape(RoundedRectangle(cornerRadius: 20))
                ForEach(SecurityTool.allCases, id: \.self) { tool in
                    if tool == .generator || tool == .email {
                        TimingLabel(tool == .generator ? "01 / CREATE" : "02 / CHECK FOR BREACHES").foregroundStyle(.secondary)
                    }
                    NavigationLink(value: Route.securityTool(tool)) {
                        HStack(spacing: 13) {
                            Image(systemName: tool.icon).foregroundStyle(Color.track).font(.title3)
                                .frame(width: 42, height: 44).background(Color.track.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tool.title).font(.headline)
                                Text(tool.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right").font(.caption)
                        }.securityCard()
                    }.buttonStyle(.plain).accessibilityIdentifier("securityTool-\(tool.rawValue)")
                }
            }.padding(20).frame(maxWidth: 570)
        }.frame(maxWidth: .infinity).background(Color.asphalt).navigationBarTitleDisplayMode(.inline)
    }
}

extension View {
    func securityCard() -> some View {
        padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lane, in: RoundedRectangle(cornerRadius: 15))
    }
}

struct SecurityPage<Content: View>: View {
    let tool: SecurityTool
    @ViewBuilder let content: Content
    @StateObject private var shield = PrivacyShield()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TimingLabel("365 / SECURITY").foregroundStyle(Color.track)
                Text(tool.title).font(.system(.largeTitle, design: .rounded, weight: .black))
                content
            }.padding(20).frame(maxWidth: 570, alignment: .leading)
        }.frame(maxWidth: .infinity).background(Color.asphalt)
            .navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively)
            .onAppear { shield.shouldCover = { true } }
            .onDisappear { shield.shouldCover = { false } }
    }
}

struct ProviderPage: UIViewControllerRepresentable, Identifiable {
    let url: URL
    var id: URL { url }
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.dismissButtonStyle = .done
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

@MainActor func copySecurityValue(_ value: String) {
    UIPasteboard.general.setItems([[UTType.plainText.identifier: value]],
                                  options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(60)])
}

private struct GeneratorScreen: View {
    @State private var length = 24
    @State private var uppercase = true
    @State private var digits = true
    @State private var symbols = true
    @State private var password = PasswordGenerator.make(length: 24, uppercase: true, digits: true, symbols: true)
    @State private var copied = false
    @Environment(\.scenePhase) private var scene
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        SecurityPage(tool: .generator) {
            VStack(alignment: .leading, spacing: 12) {
                TimingLabel("GENERATED ON THIS IPHONE").foregroundStyle(Color.track)
                Text(password.isEmpty ? "Generate a new password" : password)
                    .font(.system(.title3, design: .monospaced, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true).privacySensitive()
                    .accessibilityIdentifier("generatedPassword")
                Button {
                    copySecurityValue(password)
                    copied = true
                } label: { Label(copied ? "Copied for 1 minute" : "Copy password", systemImage: copied ? "checkmark" : "doc.on.doc") }
                    .disabled(password.isEmpty).font(.subheadline.weight(.semibold))
            }.securityCard()
            VStack(spacing: 14) {
                Stepper("Length · \(length)", value: $length, in: PasswordGenerator.lengths)
                Divider()
                Toggle("Uppercase letters", isOn: $uppercase)
                Toggle("Numbers", isOn: $digits)
                Toggle("Symbols", isOn: $symbols)
            }.securityCard()
            Button(action: generate) { ActionLabel(title: "New password", icon: "arrow.clockwise") }
                .buttonStyle(.plain).accessibilityIdentifier("generatePassword")
            Text("Lowercase letters are always included. Save the password in your password manager.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .onChange(of: length) { generate() }.onChange(of: uppercase) { generate() }
        .onChange(of: digits) { generate() }.onChange(of: symbols) { generate() }
        .onChange(of: scene) { _, phase in if phase == .background { password = ""; copied = false } }
    }
    private func generate() {
        password = PasswordGenerator.make(length: length, uppercase: uppercase, digits: digits, symbols: symbols)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { copied = false }
    }
}

private struct EmailBreachScreen: View {
    @State private var email = ""
    @State private var page: ProviderPage?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scene

    var body: some View {
        SecurityPage(tool: .email) {
            Text("Search public breach records for your email address.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                TimingLabel("YOUR EMAIL").foregroundStyle(Color.track)
                TextField("name@example.com", text: $email)
                    .keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($focused).submitLabel(.search).onSubmit(search)
                    .accessibilityIdentifier("breachEmail")
            }.securityCard()
            Text("When you check, your address is sent to Have I Been Pwned. Its results open here in a browser sheet.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(action: search) { ActionLabel(title: "Check email", icon: "magnifyingglass") }
                .buttonStyle(.plain).disabled(SecurityServices.emailLookupURL(email) == nil)
                .opacity(SecurityServices.emailLookupURL(email) == nil ? 0.5 : 1)
                .accessibilityIdentifier("checkEmail")
        }.sheet(item: $page) { $0.ignoresSafeArea() }
            .onChange(of: scene) { _, phase in if phase == .background { email = "" } }
    }
    private func search() {
        guard let url = SecurityServices.emailLookupURL(email) else { return }
        focused = false
        page = ProviderPage(url: url)
    }
}

private struct PasswordBreachScreen: View {
    @State private var password = ""
    @State private var count: Int?
    @State private var message: String?
    @State private var checking: Task<Void, Never>?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scene

    var body: some View {
        SecurityPage(tool: .password) {
            Text("Compare your password with the Have I Been Pwned password database.").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                TimingLabel("PASSWORD TO CHECK").foregroundStyle(Color.track)
                SecureField("Enter a password", text: $password).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().focused($focused).submitLabel(.search)
                    .onSubmit(check).accessibilityIdentifier("breachPassword")
            }.securityCard()
            Text("Only the first five characters of its hash leave this iPhone. The full match is checked locally.")
                .font(.footnote).foregroundStyle(.secondary)
            Button(action: check) { ActionLabel(title: checking == nil ? "Check password" : "Checking…", icon: "magnifyingglass") }
                .buttonStyle(.plain).disabled(password.isEmpty || checking != nil)
                .opacity(password.isEmpty ? 0.5 : 1).accessibilityIdentifier("checkPassword")
            if let count {
                VStack(alignment: .leading, spacing: 8) {
                    Label(count == 0 ? "No match found" : "Password exposed", systemImage: count == 0 ? "checkmark.shield" : "exclamationmark.shield")
                        .font(.headline).foregroundStyle(count == 0 ? Color.track : Color.orange)
                    Text(count == 0 ? "This password did not appear in the checked data. Use a unique password for each account." :
                            "Seen \(count.formatted(.number.locale(Locale(identifier: "en_US")))) times. Replace it wherever you use it.")
                        .font(.subheadline)
                }.securityCard()
            }
            if let message { Text(message).font(.subheadline).accessibilityIdentifier("breachError") }
            Link("Data from Have I Been Pwned", destination: URL(string: "https://haveibeenpwned.com/Passwords")!).font(.footnote)
        }.onChange(of: password) { reset() }
            .onDisappear { reset(); password = "" }
            .onChange(of: scene) { _, phase in if phase == .background { reset(); password = "" } }
    }

    private func reset() {
        checking?.cancel()
        checking = nil
        count = nil
        message = nil
    }
    private func check() {
        guard !password.isEmpty, checking == nil else { return }
        focused = false
        let value = password
        reset()
        checking = Task { @MainActor in
            do {
                let matches = try await SecurityServices.live.passwordOccurrences(value)
                guard !Task.isCancelled, value == password else { return }
                count = matches
            } catch {
                guard !Task.isCancelled, value == password else { return }
                message = error.localizedDescription
            }
            checking = nil
        }
    }
}
