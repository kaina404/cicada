import Foundation
import SwiftUI

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case system, chinese = "zh-Hans", english = "en"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: L("跟随系统")
        case .chinese: "简体中文"
        case .english: "English"
        }
    }
}

/// Bundle and AppKit cache their localization; apply the preference on the next launch.
@MainActor
final class InterfaceLanguagePreference: ObservableObject {
    private let defaults: UserDefaults
    private let launchChoice: InterfaceLanguage
    @Published var choice: InterfaceLanguage {
        didSet {
            if choice == .system {
                defaults.removeObject(forKey: "AppleLanguages")
            } else {
                defaults.set([choice.rawValue], forKey: "AppleLanguages")
            }
        }
    }
    var needsRelaunch: Bool { choice != launchChoice }

    init(defaults: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) {
        self.defaults = defaults
        // Only the app's override counts; global preferred languages mean “follow system”.
        let languages = domain.flatMap { defaults.persistentDomain(forName: $0)?["AppleLanguages"] as? [String] }
        let choice = languages?.first.flatMap(InterfaceLanguage.init(rawValue:)) ?? .system
        self.choice = choice
        launchChoice = choice
    }
}

struct InterfaceLanguageSettings: View {
    @ObservedObject var preference: InterfaceLanguagePreference
    let relaunch: () -> Void

    var body: some View {
        SettingsCard {
            SettingsRow(title: L("界面语言"), detail: L("重新打开后生效"), divider: preference.needsRelaunch) {
                PillMenu(value: preference.choice.title,
                         options: InterfaceLanguage.allCases.map { ($0.rawValue, $0.title) }) {
                    if let language = InterfaceLanguage(rawValue: $0) { preference.choice = language }
                }
            }
            if preference.needsRelaunch {
                SettingsRow(title: L("语言已保存"), detail: L("重新打开会结束当前会议，请先完成记录"), divider: false) {
                    SoftButton(L("重新打开"), action: relaunch)
                }
            }
        }
    }
}
