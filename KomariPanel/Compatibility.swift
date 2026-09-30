import SwiftUI

extension View {
    // Let the navigation controller own geometry, interruption and the return gesture.
    // Older systems retain their native push/pop, rather than an imitation overlay.
    @ViewBuilder
    func nodeZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func nodeZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID, reduceMotion: Bool) -> some View {
        if #available(iOS 18, *), !reduceMotion {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

struct CompatibleGlassButtonStyle: ButtonStyle {
    var prominent = false
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if #available(iOS 26, *) {
            if prominent { configuration.label.padding(.horizontal, 14).padding(.vertical, 10).glassEffect(.regular.tint(.accentColor).interactive()).opacity(configuration.isPressed ? 0.7 : 1) }
            else { configuration.label.padding(.horizontal, 12).padding(.vertical, 8).glassEffect(.regular.interactive()).opacity(configuration.isPressed ? 0.7 : 1) }
        } else {
            configuration.label.padding(.horizontal, 12).padding(.vertical, 8)
                .background(prominent ? Color.accentColor : Color(.tertiarySystemFill), in: Capsule())
                .foregroundColor(prominent ? .white : .accentColor).opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
struct CompatibleGlassContainer<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content
    @ViewBuilder var body: some View {
        if #available(iOS 26, *) { GlassEffectContainer(spacing: spacing, content: content) }
        else { content() }
    }
}
struct EmptyState: View {
    let title: LocalizedStringKey
    let symbol: String
    let description: String
    init(_ title: LocalizedStringKey, systemImage: String, description: Text? = nil) {
        self.title = title; symbol = systemImage; self.description = ""
        self.detail = description
    }
    private let detail: Text?
    var body: some View {
        VStack(spacing: 12) { Image(systemName: symbol).font(.system(size: 40)).foregroundColor(.secondary); Text(title).font(.title3.bold()); if let detail { detail.font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center) } }.padding(28).frame(maxWidth: .infinity)
    }
}
func hexRGB(_ raw: String) -> UInt32? {
    let hex = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
    guard hex.count == 6, hex.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else { return nil }
    return UInt32(hex, radix: 16)
}
func resolvedAccentColor(_ hex: String) -> Color {
    guard let rgb = hexRGB(hex) else { return .blue }
    return Color(red: Double((rgb >> 16) & 255)/255, green: Double((rgb >> 8) & 255)/255, blue: Double(rgb & 255)/255)
}
struct AppearanceView: View {
    @AppStorage("appAppearance") private var appMode = AppearanceMode.system.rawValue
    @AppStorage("accentHex") private var hex = "#007AFF"
    @State private var custom = false
    let colors = ["#007AFF", "#AF52DE", "#FF2D55", "#FF9500", "#34C759", "#00C7BE"]
    var body: some View {
        Form {
            Section("应用外观") {
                Picker("应用主题", selection: $appMode) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented).accessibilityIdentifier("appAppearance")
            }
            Section("强调色") {
                HStack(spacing: 0) {
                    ForEach(colors, id: \.self) { c in
                        Button { hex = c } label: {
                            Circle().fill(resolvedAccentColor(c)).frame(width: 32, height: 32)
                                .overlay { if hex.uppercased() == c { Image(systemName: "checkmark").foregroundColor(.white).font(.caption.bold()) } }
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.plain).accessibilityLabel(c)
                    }
                    Button { custom = true } label: {
                        Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                            .frame(width: 32, height: 32)
                            .overlay { Image(systemName: colors.contains(hex.uppercased()) ? "plus" : "checkmark").foregroundColor(.white).font(.caption.bold()).shadow(radius: 1.5) }
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).accessibilityLabel("自定义强调色").accessibilityIdentifier("customAccent")
                }
                .padding(.vertical, 4)
            }
        }.navigationTitle("外观")
            .sheet(isPresented: $custom) { CustomAccentEditor(hex: $hex) }
    }
}
struct CustomAccentEditor: View {
    @Binding var hex: String
    @Environment(\.dismiss) private var dismiss
    @State private var draft = Color.blue
    @State private var input = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ColorPicker("选择颜色", selection: $draft, supportsOpacity: false)
                        .accessibilityIdentifier("accentColorPicker")
                    TextField("HEX，例如 #007AFF", text: $input)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                        .accessibilityIdentifier("accentHexInput")
                        .onChange(of: input) { value in
                            invalid = false
                            if hexRGB(value) != nil { draft = resolvedAccentColor(value) }
                        }
                    if invalid { Text("请输入 6 位 HEX 颜色值。").foregroundColor(.red) }
                }
            }.navigationTitle("自定义强调色").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            guard hexRGB(input) != nil else { invalid = true; return }
                            hex = input.hasPrefix("#") ? input.uppercased() : "#" + input.uppercased()
                            dismiss()
                        }.accessibilityIdentifier("saveCustomAccent")
                    }
                }
                .onAppear { input = hex; draft = resolvedAccentColor(hex) }
                .onChange(of: draft) { value in
                    if let normalized = colorHex(value), hexRGB(input) != hexRGB(normalized) { input = normalized }
                }
        }
    }
}
func colorHex(_ color: Color) -> String? {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    guard UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
    return String(format: "#%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
}
struct AboutView: View {
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("AboutIcon").resizable().scaledToFit().frame(width: 88, height: 88).clipShape(RoundedRectangle(cornerRadius: 20))
                    Text("Monitor Panel").font(.title2.bold())
                    Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")").foregroundColor(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical)
                Link("GitHub 仓库", destination: URL(string: "https://github.com/Likhixang/Monitor-Panel-iOS")!)
            }
            Section("安全与兼容") {
                Label("API key 保存在本机 Keychain", systemImage: "lock.shield")
                Text("默认仅允许 HTTPS；HTTP 需逐个面板明确允许。证书必须有效，不绕过 TLS 校验。API key 为管理员权限，请妥善保护。").font(.footnote).foregroundStyle(.secondary)
            }
            Section("开源组件与致谢") {
                Text("应用没有集成第三方运行时组件。SwiftUI、Charts、Foundation、Security 为 Apple 系统框架，不是第三方开源依赖。").font(.footnote)
                NavigationLink("图标与数据许可") {
                    ScrollView {
                        Text((Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt")
                            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? NSLocalizedString("许可文件未能读取", comment: ""))
                            .font(.footnote).textSelection(.enabled).padding()
                    }.navigationTitle("图标与数据许可")
                }
                Link("Komari · MIT", destination: URL(string: "https://github.com/komari-monitor/komari")!)
                Link("哪吒 · Apache-2.0", destination: URL(string: "https://github.com/nezhahq/nezha")!)
                Link("Komari API 文档", destination: URL(string: "https://komari-document.pages.dev/en/dev/api")!)
                Link("哪吒 API 文档", destination: URL(string: "https://nezha.wiki/guide/api.html")!)
                Link("DStatus API 文档", destination: URL(string: "https://docs.vps.mom/public-api")!)
            }
        }.navigationTitle("关于")
    }
}
