//
//  AiLandSoundPresets.swift
//  Ai_land
//
//  完成 / 交互 音效预设：基于 macOS 自带 NSSound 名称（/System/Library/Sounds）。
//

import Foundation

/// 音效套系：每套含「任务完成成功/失败」与「问道等交互到来」各一种系统音（`/System/Library/Sounds`）。
enum AiLandSoundPreset: String, CaseIterable, Identifiable {
    /// 与早期版本存盘键一致；仅改映射与文案时可安全保留用户已选套系。
    case classic
    case minimal
    case arcade
    case gentle
    case crisp
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .classic: return "系统原味"
        case .minimal: return "轻弹薄雾"
        case .arcade: return "放克声呐"
        case .gentle: return "绵柔绒"
        case .crisp: return "号角木塞"
        }
    }
    
    var subtitle: String {
        switch self {
        case .classic: return "Glass 清脆完成 + Basso 低沉失败 + Tink 轻叮（经典 Mac 三件套）"
        case .minimal: return "Pop 气泡感 + Sosumi 警示 + Ping 短促像素感"
        case .arcade: return "Funk 律动 + Submarine 声呐下沉 + Morse 电报节奏"
        case .gentle: return "Purr 低频呼噜 + Glass 通透失败 + Blow 柔和气流"
        case .crisp: return "Hero 略长庆祝 + Sosumi + Bottle 木塞一声"
        }
    }
    
    /// 任务完成（成功）
    var completionSuccessNSSoundName: String {
        switch self {
        case .classic: return "Glass"
        case .minimal: return "Pop"
        case .arcade: return "Funk"
        case .gentle: return "Purr"
        case .crisp: return "Hero"
        }
    }
    
    /// 任务完成（失败）
    var completionFailureNSSoundName: String {
        switch self {
        case .classic: return "Basso"
        case .minimal: return "Sosumi"
        case .arcade: return "Submarine"
        case .gentle: return "Glass"
        case .crisp: return "Sosumi"
        }
    }
    
    /// 新的「问道 / 交互」请求到达时
    var interactionNSSoundName: String {
        switch self {
        case .classic: return "Tink"
        case .minimal: return "Ping"
        case .arcade: return "Morse"
        case .gentle: return "Blow"
        case .crisp: return "Bottle"
        }
    }
    
    static func stored(_ raw: String?) -> AiLandSoundPreset {
        guard let raw, let v = AiLandSoundPreset(rawValue: raw) else { return .classic }
        return v
    }
}
