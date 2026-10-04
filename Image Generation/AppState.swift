import SwiftUI
import Security
import AppKit
import Combine

enum AIProvider: String, CaseIterable, Identifiable, Codable {
    case openAI = "OpenAI"
    case fal = "fal.ai / FLUX"
    case gemini = "Google Gemini"

    var id: String { rawValue }
    var icon: String {
        switch self { case .openAI: return "brain.head.profile"; case .fal: return "bolt.fill"; case .gemini: return "diamond.fill" }
    }
    var subtitle: String {
        switch self { case .openAI: return "GPT Image"; case .fal: return "FLUX models"; case .gemini: return "Gemini Image" }
    }
    var keyPlaceholder: String {
        switch self { case .openAI: return "sk-…"; case .fal: return "fal key…"; case .gemini: return "AIza…" }
    }
}

final class AppState: ObservableObject {
    @Published var provider: AIProvider
    @Published var isConfigured: Bool
    @Published var showSettings = false

    init() {
        let stored = UserDefaults.standard.string(forKey: "aiProvider").flatMap(AIProvider.init(rawValue:)) ?? .openAI
        provider = stored
        isConfigured = KeychainStore.load(provider: stored) != nil
    }

    func configure(provider: AIProvider, key: String) throws {
        try KeychainStore.save(key, provider: provider)
        self.provider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "aiProvider")
        isConfigured = true
        showSettings = false
    }

    func reset() {
        KeychainStore.delete(provider: provider)
        isConfigured = false
    }
}

enum KeychainStore {
    private static let service = "com.layerai.api-keys"

    static func save(_ value: String, provider: AIProvider) throws {
        let data = Data(value.utf8)
        delete(provider: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    static func load(provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        SecItemDelete(query as CFDictionary)
    }
}

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var provider: AIProvider = .openAI
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            VStack(spacing: 28) {
                VStack(spacing: 10) {
                    Image(systemName: "sparkles.rectangle.stack.fill").font(.system(size: 48)).foregroundStyle(.purple)
                    Text("LayerAI").font(.system(size: 34, weight: .bold))
                    Text("Connect an image model to start building layered AI compositions.").foregroundStyle(.secondary)
                }
                VStack(spacing: 10) {
                    ForEach(AIProvider.allCases) { item in
                        Button { provider = item; key = "" } label: {
                            HStack(spacing: 14) {
                                Image(systemName: item.icon).frame(width: 32, height: 32).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                                VStack(alignment: .leading, spacing: 2) { Text(item.rawValue).fontWeight(.semibold); Text(item.subtitle).font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Image(systemName: provider == item ? "checkmark.circle.fill" : "circle").foregroundStyle(provider == item ? .purple : .secondary)
                            }.padding(12).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(provider == item ? Color.purple.opacity(0.12) : Color.white.opacity(0.025), in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(provider == item ? Color.purple.opacity(0.65) : Color.white.opacity(0.06)))
                    }
                }.frame(width: 440)
                VStack(alignment: .leading, spacing: 8) {
                    Text("API KEY").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    SecureField(provider.keyPlaceholder, text: $key).textFieldStyle(.roundedBorder)
                    Text("Stored locally in macOS Keychain.").font(.caption).foregroundStyle(.secondary)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.frame(width: 440)
                Button("Connect & open LayerAI") {
                    do { try app.configure(provider: provider, key: key.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).tint(.purple).controlSize(.large).disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(50)
        }.frame(minWidth: 760, minHeight: 650).preferredColorScheme(.dark)
    }
}

struct ProviderSettingsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var provider: AIProvider = .openAI
    @State private var key = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("AI Provider").font(.title2.bold())
            Picker("Provider", selection: $provider) { ForEach(AIProvider.allCases) { Text($0.rawValue).tag($0) } }
            SecureField("API key", text: $key).textFieldStyle(.roundedBorder)
            Text("Keys are saved in macOS Keychain, not in your .aiimg project.").font(.caption).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button("Cancel") { dismiss() }; Button("Save") { do { try app.configure(provider: provider, key: key); dismiss() } catch { self.error = error.localizedDescription } }.buttonStyle(.borderedProminent).tint(.purple).disabled(key.isEmpty) }
        }.padding(24).frame(width: 460).onAppear { provider = app.provider }
    }
}
