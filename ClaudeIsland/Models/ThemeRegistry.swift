//
//  ThemeRegistry.swift
//  ClaudeIsland
//
//  Central registry for built-in and plugin-provided notch themes.
//

import Combine
import Foundation

struct ThemeDescriptor: Equatable, Identifiable {
    let id: NotchThemeID
    let fallbackDisplayName: String
    let previewIdleLabelEN: String
    let previewIdleLabelZH: String
    let prefersUppercasePreviewLabel: Bool
    let tokens: ThemeTokens
    let source: ThemeSource

    enum ThemeSource: Equatable {
        case builtIn
        case plugin(pluginID: String)
        case file(path: String)
    }

    func previewIdleLabel(isChinese: Bool) -> String {
        isChinese ? previewIdleLabelZH : previewIdleLabelEN
    }
}

private struct ThemePluginManifest: Codable {
    let id: String
    let displayName: String
    let previewIdleLabelEN: String?
    let previewIdleLabelZH: String?
    let prefersUppercasePreviewLabel: Bool?
    let tokens: ThemeTokens
}

@MainActor
final class ThemeRegistry: ObservableObject {
    static let shared = ThemeRegistry()

    @Published private(set) var availableThemes: [ThemeDescriptor]
    private var cancellables: Set<AnyCancellable> = []

    private init() {
        self.availableThemes = Self.builtInDescriptors
        NativePluginManager.shared.$loadedPlugins
            .sink { [weak self] _ in
                self?.loadAll()
            }
            .store(in: &cancellables)
    }

    var themeIDs: [NotchThemeID] {
        availableThemes.map(\.id)
    }

    func descriptor(for id: NotchThemeID) -> ThemeDescriptor {
        availableThemes.first(where: { $0.id == id }) ?? Self.builtInDescriptors[0]
    }

    func displayName(for id: NotchThemeID) -> String {
        descriptor(for: id).fallbackDisplayName
    }

    func loadAll(pluginBundles: [Bundle]? = nil) {
        var descriptors = Self.builtInDescriptors
        var seen = Set(descriptors.map(\.id))
        let resolvedBundles = pluginBundles ?? NativePluginManager.shared.loadedPlugins.map(\.bundle)

        for descriptor in loadThemeFiles(in: userThemesDirectory(), source: .file(path: userThemesDirectory().path)) {
            guard !seen.contains(descriptor.id) else { continue }
            descriptors.append(descriptor)
            seen.insert(descriptor.id)
        }

        for bundle in resolvedBundles where bundle != Bundle.main {
            let source = ThemeDescriptor.ThemeSource.plugin(pluginID: bundle.bundleIdentifier ?? bundle.bundleURL.lastPathComponent)
            for descriptor in loadThemeFiles(in: bundle.bundleURL.appendingPathComponent("Contents/Resources/Themes"), source: source) {
                guard !seen.contains(descriptor.id) else { continue }
                descriptors.append(descriptor)
                seen.insert(descriptor.id)
            }
        }

        availableThemes = descriptors
    }

    private func loadThemeFiles(in directory: URL, source: ThemeDescriptor.ThemeSource) -> [ThemeDescriptor] {
        guard FileManager.default.fileExists(atPath: directory.path),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let manifest = try? decoder.decode(ThemePluginManifest.self, from: data) else {
                    return nil
                }
                return ThemeDescriptor(
                    id: NotchThemeID(rawValue: manifest.id),
                    fallbackDisplayName: manifest.displayName,
                    previewIdleLabelEN: manifest.previewIdleLabelEN ?? "Idle",
                    previewIdleLabelZH: manifest.previewIdleLabelZH ?? "空闲",
                    prefersUppercasePreviewLabel: manifest.prefersUppercasePreviewLabel ?? false,
                    tokens: manifest.tokens,
                    source: source
                )
            }
    }

    private func userThemesDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/codeisland/themes")
    }

    static let builtInDescriptors: [ThemeDescriptor] = [
        ThemeDescriptor(
            id: .classic,
            fallbackDisplayName: "Classic",
            previewIdleLabelEN: "Idle",
            previewIdleLabelZH: "空闲",
            prefersUppercasePreviewLabel: false,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "000000"), overlay: .init(hex: "1A1A1A"), border: .init(hex: "2A2A2A")),
                text: .init(primary: .white, secondary: .init(hex: "FFFFFF"), muted: .init(hex: "9A9A9A"), inverse: .black),
                status: .init(idle: .init(hex: "CAFF00"), working: .init(hex: "66E8F8"), needsYou: .init(hex: "F59E0B"), error: .init(hex: "EF4444"), done: .init(hex: "4ADE80"), thinking: .init(hex: "A78BFA")),
                badges: .init(agentText: .init(hex: "60A5FA"), agentFill: .init(hex: "1E3A8A"), terminalText: .init(hex: "93C5FD"), terminalFill: .init(hex: "1E3A8A"), subduedText: .init(hex: "FFFFFF"), subduedFill: .init(hex: "262626")),
                usage: .init(text: .init(hex: "FFFFFF"), track: .init(hex: "2A2A2A"), fill: .init(hex: "4ADE80"), border: .init(hex: "2A2A2A")),
                chat: .init(bodyText: .white, secondaryText: .init(hex: "D1D5DB"), bubbleText: .white, bubbleFill: .init(hex: "2F2F2F"), assistantDot: .init(hex: "FFFFFF"))
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .forest,
            fallbackDisplayName: "Forest",
            previewIdleLabelEN: "Idle",
            previewIdleLabelZH: "空闲",
            prefersUppercasePreviewLabel: false,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "0D1F14"), overlay: .init(hex: "163020"), border: .init(hex: "294534")),
                text: .init(primary: .init(hex: "E8F5E9"), secondary: .init(hex: "B8D0BE"), muted: .init(hex: "8BA896"), inverse: .black),
                status: .init(idle: .init(hex: "7CC85A"), working: .init(hex: "66E8F8"), needsYou: .init(hex: "F59E0B"), error: .init(hex: "EF4444"), done: .init(hex: "4ADE80"), thinking: .init(hex: "A78BFA")),
                badges: .init(agentText: .init(hex: "CFE9D7"), agentFill: .init(hex: "23422E"), terminalText: .init(hex: "A8DAB7"), terminalFill: .init(hex: "1B3525"), subduedText: .init(hex: "D5E6DA"), subduedFill: .init(hex: "1B3525")),
                usage: .init(text: .init(hex: "DCEFE1"), track: .init(hex: "284033"), fill: .init(hex: "7CC85A"), border: .init(hex: "284033")),
                chat: .init(bodyText: .init(hex: "E8F5E9"), secondaryText: .init(hex: "B8D0BE"), bubbleText: .init(hex: "E8F5E9"), bubbleFill: .init(hex: "23422E"), assistantDot: .init(hex: "CFE9D7"))
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .neonTokyo,
            fallbackDisplayName: "Night Circuit",
            previewIdleLabelEN: "IDLE_",
            previewIdleLabelZH: "IDLE_",
            prefersUppercasePreviewLabel: true,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "070B1A"), overlay: .init(hex: "111A38"), border: .init(hex: "1D2A59")),
                text: .init(primary: .init(hex: "F7F3FF"), secondary: .init(hex: "C7B6F8"), muted: .init(hex: "7DA6D9"), inverse: .black),
                status: .init(idle: .init(hex: "FF2FAE"), working: .init(hex: "00E5FF"), needsYou: .init(hex: "FFB703"), error: .init(hex: "FF4D6D"), done: .init(hex: "C084FC"), thinking: .init(hex: "7C3AED")),
                badges: .init(agentText: .init(hex: "FF7AC8"), agentFill: .init(hex: "2A1144"), terminalText: .init(hex: "6CF2FF"), terminalFill: .init(hex: "0D2C45"), subduedText: .init(hex: "D8CCFF"), subduedFill: .init(hex: "151F46")),
                usage: .init(text: .init(hex: "E8DEFF"), track: .init(hex: "162347"), fill: .init(hex: "FF2FAE"), border: .init(hex: "24356A")),
                chat: .init(bodyText: .init(hex: "F7F3FF"), secondaryText: .init(hex: "C7B6F8"), bubbleText: .init(hex: "F7F3FF"), bubbleFill: .init(hex: "141D3D"), assistantDot: .init(hex: "00E5FF"))
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .sunset,
            fallbackDisplayName: "Sunset",
            previewIdleLabelEN: "At rest",
            previewIdleLabelZH: "静候",
            prefersUppercasePreviewLabel: false,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "FFF4E8"), overlay: .init(hex: "F6E6D3"), border: .init(hex: "E8D1BD")),
                text: .init(primary: .init(hex: "4A2618"), secondary: .init(hex: "6D4330"), muted: .init(hex: "A06850"), inverse: .white),
                status: .init(idle: .init(hex: "E8552A"), working: .init(hex: "0F766E"), needsYou: .init(hex: "B45309"), error: .init(hex: "B91C1C"), done: .init(hex: "15803D"), thinking: .init(hex: "7C3AED")),
                badges: .init(agentText: .init(hex: "7C2D12"), agentFill: .init(hex: "F7D7BF"), terminalText: .init(hex: "5B4636"), terminalFill: .init(hex: "F1DECF"), subduedText: .init(hex: "5B4636"), subduedFill: .init(hex: "F1DECF")),
                usage: .init(text: .init(hex: "4A2618"), track: .init(hex: "E8D1BD"), fill: .init(hex: "E8552A"), border: .init(hex: "E8D1BD")),
                chat: .init(bodyText: .init(hex: "4A2618"), secondaryText: .init(hex: "6D4330"), bubbleText: .init(hex: "4A2618"), bubbleFill: .init(hex: "F6E6D3"), assistantDot: .init(hex: "4A2618"))
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .retroArcade,
            fallbackDisplayName: "Retro Arcade",
            previewIdleLabelEN: "IDLE",
            previewIdleLabelZH: "IDLE",
            prefersUppercasePreviewLabel: true,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "10B981"), overlay: .init(hex: "6EE7B7"), border: .init(hex: "065F46")),
                text: .init(primary: .black, secondary: .black, muted: .black, inverse: .white),
                status: .init(idle: .init(hex: "064E3B"), working: .init(hex: "065F46"), needsYou: .init(hex: "92400E"), error: .init(hex: "991B1B"), done: .init(hex: "14532D"), thinking: .init(hex: "312E81")),
                badges: .init(agentText: .black, agentFill: .init(hex: "A7F3D0"), terminalText: .black, terminalFill: .init(hex: "6EE7B7"), subduedText: .black, subduedFill: .init(hex: "86EFAC")),
                usage: .init(text: .black, track: .init(hex: "A7F3D0"), fill: .init(hex: "064E3B"), border: .init(hex: "065F46")),
                chat: .init(bodyText: .black, secondaryText: .black, bubbleText: .black, bubbleFill: .init(hex: "A7F3D0"), assistantDot: .init(hex: "064E3B"))
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .highContrast,
            fallbackDisplayName: "High Contrast",
            previewIdleLabelEN: "Idle",
            previewIdleLabelZH: "空闲",
            prefersUppercasePreviewLabel: false,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "000000"), overlay: .init(hex: "111111"), border: .init(hex: "FFFFFF")),
                text: .init(primary: .white, secondary: .white, muted: .white, inverse: .black),
                status: .init(idle: .init(hex: "FFE600"), working: .init(hex: "66E8F8"), needsYou: .init(hex: "FFE600"), error: .init(hex: "FF4D4D"), done: .init(hex: "4ADE80"), thinking: .init(hex: "A78BFA")),
                badges: .init(agentText: .white, agentFill: .init(hex: "000000"), terminalText: .white, terminalFill: .init(hex: "000000"), subduedText: .white, subduedFill: .init(hex: "000000")),
                usage: .init(text: .white, track: .init(hex: "333333"), fill: .init(hex: "FFE600"), border: .white),
                chat: .init(bodyText: .white, secondaryText: .white, bubbleText: .white, bubbleFill: .init(hex: "111111"), assistantDot: .white)
            ),
            source: .builtIn
        ),
        ThemeDescriptor(
            id: .sakura,
            fallbackDisplayName: "Pink Mist",
            previewIdleLabelEN: "Resting",
            previewIdleLabelZH: "小憩",
            prefersUppercasePreviewLabel: false,
            tokens: ThemeTokens(
                chrome: .init(background: .init(hex: "FFF4FB"), overlay: .init(hex: "FFE3F2"), border: .init(hex: "F6BDD9")),
                text: .init(primary: .init(hex: "7A3558"), secondary: .init(hex: "A2557D"), muted: .init(hex: "C27AA1"), inverse: .white),
                status: .init(idle: .init(hex: "F472B6"), working: .init(hex: "F9A8D4"), needsYou: .init(hex: "FB7185"), error: .init(hex: "E11D48"), done: .init(hex: "EC4899"), thinking: .init(hex: "C084FC")),
                badges: .init(agentText: .init(hex: "8F3A66"), agentFill: .init(hex: "FFD6EB"), terminalText: .init(hex: "7A3558"), terminalFill: .init(hex: "FFF0F8"), subduedText: .init(hex: "7A3558"), subduedFill: .init(hex: "FFE7F4")),
                usage: .init(text: .init(hex: "7A3558"), track: .init(hex: "FAD7E8"), fill: .init(hex: "F472B6"), border: .init(hex: "F3B7D2")),
                chat: .init(bodyText: .init(hex: "7A3558"), secondaryText: .init(hex: "A2557D"), bubbleText: .init(hex: "7A3558"), bubbleFill: .init(hex: "FFF0F8"), assistantDot: .init(hex: "C2417A"))
            ),
            source: .builtIn
        ),
    ]
}
