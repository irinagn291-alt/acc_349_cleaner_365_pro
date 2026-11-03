import SwiftUI

struct AliasScreen: View {
    @State private var input = ""
    @State private var connectedKey: String?
    @State private var aliases: [ForwardingAlias] = []
    @State private var page = 0
    @State private var hasMore = false
    @State private var refreshBeforeCreating = true
    @State private var busy = false
    @State private var message: String?
    @State private var copied: Int?
    @State private var provider: ProviderPage?
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scene
    private let api = SecurityServices.live

    var body: some View {
        SecurityPage(tool: .aliases) {
            if connectedKey == nil { setup } else { connected }
            if busy { ProgressView("Contacting SimpleLogin…").font(.footnote) }
            if let message { Text(message).font(.subheadline).accessibilityIdentifier("aliasMessage") }
        }.sheet(item: $provider) { $0.ignoresSafeArea() }
            .task {
                guard connectedKey == nil, !busy else { return }
                do {
                    if let key = try AliasKey.read() {
                        connectedKey = key
                        busy = true
                        defer { busy = false }
                        try await refresh(key)
                    }
                } catch { if !Task.isCancelled { message = error.localizedDescription } }
            }
            .onChange(of: scene) { _, phase in if phase == .background { input = "" } }
    }

    @ViewBuilder private var setup: some View {
        Text("Give each service a different address. SimpleLogin delivers incoming mail to your verified mailbox.").foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 12) {
            TimingLabel("01 / LINK YOUR MAILBOX").foregroundStyle(Color.track)
            Text("Sign in to SimpleLogin with the inbox you want to use, verify it, then create a personal API key named Cleaner 365.")
                .font(.subheadline)
            Button("Open SimpleLogin", systemImage: "arrow.up.right") {
                provider = ProviderPage(url: URL(string: "https://app.simplelogin.io/dashboard/api_key")!)
            }
        }.securityCard()
        VStack(alignment: .leading, spacing: 12) {
            TimingLabel("02 / CONNECT ON THIS IPHONE").foregroundStyle(Color.track)
            SecureField("Personal API key", text: $input).autocorrectionDisabled().textInputAutocapitalization(.never)
                .focused($focused).submitLabel(.done).onSubmit(connect).accessibilityIdentifier("aliasKey")
            Text("Your key is stored in this iPhone’s Keychain.").font(.footnote).foregroundStyle(.secondary)
        }.securityCard()
        Button(action: connect) { ActionLabel(title: "Connect SimpleLogin", icon: "link") }
            .buttonStyle(.plain).disabled(trimmedKey.isEmpty || busy)
            .opacity(trimmedKey.isEmpty ? 0.5 : 1).accessibilityIdentifier("connectAliases")
    }

    @ViewBuilder private var connected: some View {
        Text("New aliases forward to your default SimpleLogin mailbox. Each address below shows its assigned inbox.")
            .font(.subheadline).foregroundStyle(.secondary)
        Button(action: create) { ActionLabel(title: "Create forwarding alias", icon: "plus") }
            .buttonStyle(.plain).disabled(busy || refreshBeforeCreating).opacity(refreshBeforeCreating ? 0.5 : 1)
            .accessibilityIdentifier("createAlias")
        HStack {
            TimingLabel("YOUR ALIASES")
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") {
                if let key = connectedKey { perform { try await refresh(key) } }
            }.disabled(busy)
        }
        if aliases.isEmpty && !busy && !refreshBeforeCreating {
            Text("Your first alias will appear here.").font(.subheadline).foregroundStyle(.secondary)
        }
        ForEach(aliases) { alias in
            VStack(alignment: .leading, spacing: 7) {
                Label(alias.enabled ? "Active" : "Disabled", systemImage: alias.enabled ? "checkmark.circle" : "pause.circle")
                    .font(.caption.bold()).foregroundStyle(alias.enabled ? Color.track : .secondary)
                Text(alias.email).font(.headline).textSelection(.enabled)
                Text("Forwards to " + alias.mailboxes.map(\.email).joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary)
                Button {
                    copySecurityValue(alias.email)
                    copied = alias.id
                } label: { Label(copied == alias.id ? "Copied for 1 minute" : "Copy alias", systemImage: "doc.on.doc") }
                    .font(.subheadline)
            }.securityCard()
        }
        if hasMore {
            Button("Load more aliases") {
                guard let key = connectedKey else { return }
                perform {
                    let next = page + 1
                    let items = try await api.aliases(key: key, page: next)
                    let known = Set(aliases.map(\.id))
                    aliases.append(contentsOf: items.filter { !known.contains($0.id) })
                    page = next
                    hasMore = items.count >= 20
                }
            }.disabled(busy)
        }
        Button("Manage mailboxes in SimpleLogin", systemImage: "arrow.up.right") {
            provider = ProviderPage(url: URL(string: "https://app.simplelogin.io/dashboard/mailbox")!)
        }.font(.subheadline)
        Button("Disconnect this iPhone") {
            do {
                try AliasKey.remove()
                aliases = []
                hasMore = false
                refreshBeforeCreating = true
                connectedKey = nil
                copied = nil
                message = nil
            } catch { message = error.localizedDescription }
        }.font(.subheadline).disabled(busy)
    }

    private var trimmedKey: String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func connect() {
        let key = trimmedKey
        guard !key.isEmpty else { return }
        guard key.utf8.count <= 1024, key.utf8.allSatisfy({ (33...126).contains($0) }) else {
            message = "Paste the personal API key from SimpleLogin."
            return
        }
        focused = false
        perform {
            let items = try await api.aliases(key: key)
            try AliasKey.save(key)
            connectedKey = key
            input = ""
            replaceList(items)
        }
    }
    private func create() {
        guard let key = connectedKey, !refreshBeforeCreating else { return }
        perform {
            do {
                let item = try await api.createAlias(key: key)
                aliases.removeAll { $0.id == item.id }
                aliases.insert(item, at: 0)
                message = "Alias created. You can give this address out now."
            } catch {
                refreshBeforeCreating = true
                message = error.localizedDescription + " Refresh your aliases before trying again."
            }
        }
    }
    private func refresh(_ key: String) async throws {
        let items = try await api.aliases(key: key)
        replaceList(items)
    }
    private func replaceList(_ items: [ForwardingAlias]) {
        aliases = items
        page = 0
        hasMore = items.count >= 20
        refreshBeforeCreating = false
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        message = nil
        Task { @MainActor in
            defer { busy = false }
            do { try await operation() }
            catch { message = error.localizedDescription }
        }
    }
}
