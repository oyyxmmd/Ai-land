//
//  SoundManager.swift
//  Ai_land
//
//  播放：`sys:名称`（NSSound 系统音）与 `res:music/文件`（包内资源）。
//

import AppKit
import Foundation

enum SoundType: String, CaseIterable {
    case success = "success"
    case error = "error"
    case warning = "warning"
    case notification = "notification"
    
    var description: String { rawValue }
}

final class SoundManager {
    static let shared = SoundManager()
    
    private init() {}
    
    /// 按内置类型播放（未走用户套系；保留给旧调用或调试）。
    func playSound(_ type: SoundType) {
        let soundName: String
        switch type {
        case .success: soundName = "Glass"
        case .error: soundName = "Basso"
        case .warning: soundName = "Sosumi"
        case .notification: soundName = "Tink"
        }
        playNamed(soundName)
    }
    
    /// 任务完成：尊重 `soundOnTaskCompletion` 与偏好里保存的 token。须在主线程调用（与 `TaskActivityManager` 一致）。
    @MainActor
    func playTaskCompletionIfEnabled(success: Bool) {
        guard AiLandPreferences.shared.soundOnTaskCompletion else { return }
        let token = success
            ? AiLandPreferences.shared.taskCompletionSoundSuccessToken
            : AiLandPreferences.shared.taskCompletionSoundFailureToken
        playToken(token)
    }
    
    /// 交互请求到达：尊重 `soundOnInteraction` 与偏好里保存的 token。
    @MainActor
    func playInteractionIfEnabled() {
        guard AiLandPreferences.shared.soundOnInteraction else { return }
        playToken(AiLandPreferences.shared.interactionSoundToken)
    }
    
    /// `sys:Glass` 或 `res:music/foo.mp3`。
    func playToken(_ token: String) {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("sys:") {
            let name = String(t.dropFirst(4))
            playNamed(name)
            return
        }
        if t.hasPrefix("res:") {
            let name = String(t.dropFirst(4))
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            if let url = Bundle.main.url(forResource: base, withExtension: ext.isEmpty ? nil : ext),
               let sound = NSSound(contentsOf: url, byReference: true) {
                sound.play()
                return
            }
        }
        NSSound.beep()
    }
    
    func playNamed(_ soundName: String) {
        if let sound = NSSound(named: NSSound.Name(soundName)) {
            sound.play()
        } else {
            NSSound.beep()
        }
    }
    
    func playSystemBeep() {
        NSSound.beep()
    }
    
    func playCustomSound(named soundName: String) {
        playNamed(soundName)
    }
}
