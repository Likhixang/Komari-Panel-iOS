import SwiftUI
import UIKit

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: return "跟随系统"; case .light: return "浅色"; case .dark: return "深色" } }
    var scheme: ColorScheme? { switch self { case .system: return nil; case .light: return .light; case .dark: return .dark } }
}

// A restore-only interface: app themes must never select alternate icons.
@MainActor protocol AppIconClient: AnyObject {
    var alternateIconName: String? { get }
    var supportsAlternateIcons: Bool { get }
    func restorePrimaryIcon() async throws
}

extension UIApplication: AppIconClient {
    func restorePrimaryIcon() async throws {
        // nil restores AppIcon; SpringBoard chooses Any/Dark without running us.
        try await setAlternateIconName(nil)
    }
}

@MainActor final class AppIconController: ObservableObject {
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    private let app: AppIconClient
    private let defaults: UserDefaults

    init(app: AppIconClient? = nil, defaults: UserDefaults = .standard) {
        self.app = app ?? UIApplication.shared
        self.defaults = defaults
    }

    func restoreSystemIcon() async -> Bool {
        guard !busy else { return false }
        // Inspect UIKit, not a migration flag or the old preference. This also
        // recovers installs with a lost preference but a still-selected alternate.
        guard app.alternateIconName != nil else {
            defaults.removeObject(forKey: "iconAppearance")
            error = nil
            return true
        }
        guard app.supportsAlternateIcons else {
            error = "系统暂不允许恢复默认图标，下次打开 App 时会重试。"
            return false
        }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.restorePrimaryIcon()
            guard app.alternateIconName == nil else {
                error = "系统尚未恢复默认图标，下次打开 App 时会重试。"
                return false
            }
            // Retire the preference only after UIKit confirms the primary icon.
            defaults.removeObject(forKey: "iconAppearance")
            return true
        } catch {
            self.error = "恢复默认图标失败：\(error.localizedDescription) 下次打开 App 时会重试。"
            return false
        }
    }
}

struct AppAppearanceRoot: View {
    @AppStorage("appAppearance") private var appMode = AppearanceMode.system.rawValue
    @AppStorage("accentHex") private var hex = "#007AFF"
    @StateObject private var icons = AppIconController()
    @Environment(\.scenePhase) private var phase

    var body: some View {
        RootView()
            .tint(resolvedAccentColor(hex))
            .preferredColorScheme((AppearanceMode(rawValue: appMode) ?? .system).scheme)
            .task(id: phase) {
                guard phase == .active else { return }
                _ = await icons.restoreSystemIcon()
            }
    }
}
