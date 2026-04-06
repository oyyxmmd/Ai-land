//
//  AiLandPreferences.swift
//  Ai_land
//
//  通用偏好：任务完成声音/系统通知、减弱动画（与系统「减少动态效果」可叠加）。
//

import SwiftUI
import Combine

private enum PrefKeys {
    static let soundTask = "aiLand.pref.soundOnTaskCompletion"
    static let notifyTask = "aiLand.pref.systemNotificationOnTaskCompletion"
    static let reduceMotion = "aiLand.pref.reduceMotionIsland"
    static let completionPreset = "aiLand.pref.completionSoundPreset"
    static let interactionPreset = "aiLand.pref.interactionSoundPreset"
    static let soundInteract = "aiLand.pref.soundOnInteraction"
    static let taskSoundSuccess = "aiLand.pref.taskCompletionSoundSuccessToken"
    static let taskSoundFailure = "aiLand.pref.taskCompletionSoundFailureToken"
    static let interactionSoundToken = "aiLand.pref.interactionSoundToken"
}

private enum LegacyPrefKeys {
    static let soundTask = "codeIsland.pref.soundOnTaskCompletion"
    static let notifyTask = "codeIsland.pref.systemNotificationOnTaskCompletion"
    static let reduceMotion = "codeIsland.pref.reduceMotionIsland"
    static let completionPreset = "codeIsland.pref.completionSoundPreset"
    static let interactionPreset = "codeIsland.pref.interactionSoundPreset"
    static let soundInteract = "codeIsland.pref.soundOnInteraction"
}

/// 灵动岛环境与系统 accessibility 在 `ContentView` 根上合并后注入。
private struct AiLandReduceMotionKey: EnvironmentKey {
    static var defaultValue: Bool { false }
}

extension EnvironmentValues {
    var aiLandReduceMotion: Bool {
        get { self[AiLandReduceMotionKey.self] }
        set { self[AiLandReduceMotionKey.self] = newValue }
    }
}

@MainActor
final class AiLandPreferences: ObservableObject {
    static let shared = AiLandPreferences()
    
    @Published var soundOnTaskCompletion: Bool {
        didSet { UserDefaults.standard.set(soundOnTaskCompletion, forKey: PrefKeys.soundTask) }
    }
    @Published var systemNotificationOnTaskCompletion: Bool {
        didSet { UserDefaults.standard.set(systemNotificationOnTaskCompletion, forKey: PrefKeys.notifyTask) }
    }
    @Published var reduceMotionIsland: Bool {
        didSet { UserDefaults.standard.set(reduceMotionIsland, forKey: PrefKeys.reduceMotion) }
    }
    
    /// `sys:Glass` 或 `res:music/xxx.mp3`。
    @Published var taskCompletionSoundSuccessToken: String {
        didSet { UserDefaults.standard.set(taskCompletionSoundSuccessToken, forKey: PrefKeys.taskSoundSuccess) }
    }
    
    @Published var taskCompletionSoundFailureToken: String {
        didSet { UserDefaults.standard.set(taskCompletionSoundFailureToken, forKey: PrefKeys.taskSoundFailure) }
    }
    
    @Published var interactionSoundToken: String {
        didSet { UserDefaults.standard.set(interactionSoundToken, forKey: PrefKeys.interactionSoundToken) }
    }
    
    @Published var soundOnInteraction: Bool {
        didSet { UserDefaults.standard.set(soundOnInteraction, forKey: PrefKeys.soundInteract) }
    }
    
    private init() {
        let ud = UserDefaults.standard
        
        let soundTaskVal: Bool
        if ud.object(forKey: PrefKeys.soundTask) != nil {
            soundTaskVal = ud.bool(forKey: PrefKeys.soundTask)
        } else if ud.object(forKey: LegacyPrefKeys.soundTask) != nil {
            soundTaskVal = ud.bool(forKey: LegacyPrefKeys.soundTask)
            ud.set(soundTaskVal, forKey: PrefKeys.soundTask)
            ud.removeObject(forKey: LegacyPrefKeys.soundTask)
        } else {
            soundTaskVal = true
        }
        
        let notifyVal: Bool
        if ud.object(forKey: PrefKeys.notifyTask) != nil {
            notifyVal = ud.bool(forKey: PrefKeys.notifyTask)
        } else if ud.object(forKey: LegacyPrefKeys.notifyTask) != nil {
            notifyVal = ud.bool(forKey: LegacyPrefKeys.notifyTask)
            ud.set(notifyVal, forKey: PrefKeys.notifyTask)
            ud.removeObject(forKey: LegacyPrefKeys.notifyTask)
        } else {
            notifyVal = true
        }
        
        let reduceVal: Bool
        if ud.object(forKey: PrefKeys.reduceMotion) != nil {
            reduceVal = ud.bool(forKey: PrefKeys.reduceMotion)
        } else if ud.object(forKey: LegacyPrefKeys.reduceMotion) != nil {
            reduceVal = ud.bool(forKey: LegacyPrefKeys.reduceMotion)
            ud.set(reduceVal, forKey: PrefKeys.reduceMotion)
            ud.removeObject(forKey: LegacyPrefKeys.reduceMotion)
        } else {
            reduceVal = false
        }
        
        let successTok: String
        let failureTok: String
        let interactTok: String
        if let s = ud.string(forKey: PrefKeys.taskSoundSuccess), !s.isEmpty {
            successTok = s
        } else {
            let preset = Self.migrateCompletionPreset(from: ud)
            successTok = "sys:\(preset.completionSuccessNSSoundName)"
            ud.set(successTok, forKey: PrefKeys.taskSoundSuccess)
        }
        if let s = ud.string(forKey: PrefKeys.taskSoundFailure), !s.isEmpty {
            failureTok = s
        } else {
            let preset = Self.migrateCompletionPreset(from: ud)
            failureTok = "sys:\(preset.completionFailureNSSoundName)"
            ud.set(failureTok, forKey: PrefKeys.taskSoundFailure)
        }
        if let s = ud.string(forKey: PrefKeys.interactionSoundToken), !s.isEmpty {
            interactTok = s
        } else {
            let preset = Self.migrateInteractionPreset(from: ud)
            interactTok = "sys:\(preset.interactionNSSoundName)"
            ud.set(interactTok, forKey: PrefKeys.interactionSoundToken)
        }
        
        let soundInteractVal: Bool
        if ud.object(forKey: PrefKeys.soundInteract) != nil {
            soundInteractVal = ud.bool(forKey: PrefKeys.soundInteract)
        } else if ud.object(forKey: LegacyPrefKeys.soundInteract) != nil {
            soundInteractVal = ud.bool(forKey: LegacyPrefKeys.soundInteract)
            ud.set(soundInteractVal, forKey: PrefKeys.soundInteract)
            ud.removeObject(forKey: LegacyPrefKeys.soundInteract)
        } else {
            soundInteractVal = true
        }
        
        soundOnTaskCompletion = soundTaskVal
        systemNotificationOnTaskCompletion = notifyVal
        reduceMotionIsland = reduceVal
        taskCompletionSoundSuccessToken = successTok
        taskCompletionSoundFailureToken = failureTok
        interactionSoundToken = interactTok
        soundOnInteraction = soundInteractVal
    }
    
    private static func migrateCompletionPreset(from ud: UserDefaults) -> AiLandSoundPreset {
        if let s = ud.string(forKey: PrefKeys.completionPreset) {
            return AiLandSoundPreset.stored(s)
        }
        if let s = ud.string(forKey: LegacyPrefKeys.completionPreset) {
            let v = AiLandSoundPreset.stored(s)
            ud.set(v.rawValue, forKey: PrefKeys.completionPreset)
            ud.removeObject(forKey: LegacyPrefKeys.completionPreset)
            return v
        }
        return AiLandSoundPreset.stored(nil)
    }
    
    private static func migrateInteractionPreset(from ud: UserDefaults) -> AiLandSoundPreset {
        if let s = ud.string(forKey: PrefKeys.interactionPreset) {
            return AiLandSoundPreset.stored(s)
        }
        if let s = ud.string(forKey: LegacyPrefKeys.interactionPreset) {
            let v = AiLandSoundPreset.stored(s)
            ud.set(v.rawValue, forKey: PrefKeys.interactionPreset)
            ud.removeObject(forKey: LegacyPrefKeys.interactionPreset)
            return v
        }
        return AiLandSoundPreset.stored(nil)
    }
}
