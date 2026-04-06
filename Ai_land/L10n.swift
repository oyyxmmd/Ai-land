//
//  L10n.swift
//
//  非 SwiftUI 视图内使用的本地化；与 AppLanguageSettings 使用同一 UserDefaults 键，避免 MainActor 与初始化顺序问题。
//

import Foundation

enum L10n {
    private static let modeKey = "aiLand.appLanguageMode"
    
    private static var resolvedLocale: Locale {
        switch UserDefaults.standard.string(forKey: modeKey) {
        case "en": return Locale(identifier: "en")
        case "zh-Hans": return Locale(identifier: "zh-Hans")
        default: return .autoupdatingCurrent
        }
    }
    
    static func str(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), locale: resolvedLocale)
    }
    
    static func fmt(_ key: String, _ arguments: CVarArg...) -> String {
        let format = str(key)
        return withVaList(arguments) {
            NSString(format: format, locale: resolvedLocale as NSLocale?, arguments: $0) as String
        }
    }
}
