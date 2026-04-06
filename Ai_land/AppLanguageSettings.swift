//
//  AppLanguageSettings.swift
//  Ai_land
//
//  应用内语言：跟随系统 / 英文 / 简体中文；首次启动选择；持久化 UserDefaults。
//

import SwiftUI
import Combine

enum AppLanguageMode: String, CaseIterable, Identifiable {
    case system
    case english
    case simplifiedChinese
    
    var id: String { storageKey }
    
    /// 写入 UserDefaults 的值
    var storageKey: String {
        switch self {
        case .system: return "system"
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
    
    /// `nil` 表示不覆盖环境，跟随系统
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .english: return "en"
        case .simplifiedChinese: return "zh-Hans"
        }
    }
    
    var titleKey: LocalizedStringResource {
        switch self {
        case .system: return "lang_mode_system"
        case .english: return "lang_mode_english"
        case .simplifiedChinese: return "lang_mode_chinese"
        }
    }
    
    static func from(storage: String?) -> AppLanguageMode {
        switch storage {
        case "en": return .english
        case "zh-Hans": return .simplifiedChinese
        default: return .system
        }
    }
}

@MainActor
final class AppLanguageSettings: ObservableObject {
    static let shared = AppLanguageSettings()
    
    private enum Keys {
        static let mode = "aiLand.appLanguageMode"
        static let onboardingDone = "aiLand.languageOnboardingDone"
    }
    
    @Published var mode: AppLanguageMode {
        didSet {
            UserDefaults.standard.set(mode.storageKey, forKey: Keys.mode)
        }
    }
    
    /// 尚未完成语言引导（且未被「老用户」迁移跳过）
    var needsLanguageOnboarding: Bool {
        !UserDefaults.standard.bool(forKey: Keys.onboardingDone)
    }
    
    private init() {
        let ud = UserDefaults.standard
        Self.migrateSkipOnboardingForExistingUsers(ud)
        let stored = ud.string(forKey: Keys.mode)
        mode = AppLanguageMode.from(storage: stored)
    }
    
    /// 已有生肖等持久化数据的视为老用户，不弹语言页。
    private static func migrateSkipOnboardingForExistingUsers(_ ud: UserDefaults) {
        guard !ud.bool(forKey: Keys.onboardingDone) else { return }
        if ud.object(forKey: "aiLand.zodiacRaw") != nil
            || ud.object(forKey: "codeIsland.zodiacRaw") != nil {
            ud.set(true, forKey: Keys.onboardingDone)
        }
    }
    
    func completeOnboarding(selecting selected: AppLanguageMode) {
        mode = selected
        UserDefaults.standard.set(true, forKey: Keys.onboardingDone)
    }
    
    func markOnboardingSkippedForMigration() {
        UserDefaults.standard.set(true, forKey: Keys.onboardingDone)
    }
}

extension View {
    /// 非「跟随系统」时注入 `Locale`，使 `String(localized:)` / `Text` 使用所选语言。
    @ViewBuilder
    func appPreferredLocale(_ settings: AppLanguageSettings) -> some View {
        if let id = settings.mode.localeIdentifier {
            self.environment(\.locale, Locale(identifier: id))
        } else {
            self
        }
    }
}

// MARK: - 首次启动语言选择

struct AppLanguageOnboardingSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var settings: AppLanguageSettings
    @State private var selection: AppLanguageMode = .system
    
    var body: some View {
        VStack(spacing: 20) {
            Text("lang_onboarding_title")
                .font(.title2.weight(.semibold))
            Text("lang_onboarding_subtitle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AppLanguageMode.allCases) { mode in
                    Button {
                        selection = mode
                    } label: {
                        HStack {
                            Text(mode.titleKey)
                                .font(.body.weight(selection == mode ? .semibold : .regular))
                            Spacer()
                            if selection == mode {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selection == mode ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(selection == mode ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 400)
            
            Button {
                settings.completeOnboarding(selecting: selection)
                isPresented = false
            } label: {
                Text("lang_continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: 280)
        }
        .padding(28)
        .frame(minWidth: 460)
        .onAppear {
            let pref = Locale.preferredLanguages.first ?? ""
            if pref.hasPrefix("zh") {
                selection = .simplifiedChinese
            } else if pref.hasPrefix("en") {
                selection = .english
            } else {
                selection = .system
            }
        }
    }
}
