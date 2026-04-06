//
//  AiLandURLRouting.swift
//  Ai_land
//
//  统一 `ai-land://`（及历史 `code-island://`）分发与安全边界（总长上限），供 AppDelegate、SwiftUI、Unix Socket 共用。
//

import Foundation

/// 自定义 URL 查询字段规模上限（字符数，非字节），防止恶意超长参数占用内存与 UI。
enum AiLandPayloadLimits {
    static let assistant = 128
    static let taskId = 256
    static let title = 512
    static let detail = 4_000
    static let cwd = 8_192
    static let surface = 64
    static let hookArgs = 8_192
    static let interactId = 256
    static let interactTitle = 512
    static let interactPrompt = 8_000
    static let interactOptionChars = 256
    static let interactMaxOptions = 24
    static let projectName = 256
    static let chatTurn = 800
    static let chatPreviewBlob = 2_400
    static let branch = 128
}

enum AiLandURLRouting {
    /// 当前主 scheme；历史安装仍可能使用 `code-island`。
    static let primaryURLScheme = "ai-land"
    static let legacyURLScheme = "code-island"
    
    static func isAppURLScheme(_ scheme: String?) -> Bool {
        let s = scheme?.lowercased() ?? ""
        return s == primaryURLScheme || s == legacyURLScheme
    }
    
    /// 防止异常长 URL 撑爆日志与解析栈
    static let maxURLLength = 16_384
    
    static func clampField(_ s: String?, maxChars: Int) -> String? {
        guard var t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if t.count > maxChars {
            t = String(t.prefix(maxChars))
        }
        return t
    }
    
    @MainActor
    static func dispatch(_ url: URL) {
        guard isAppURLScheme(url.scheme) else { return }
        guard url.absoluteString.count <= maxURLLength else { return }
        let host = url.host?.lowercased() ?? ""
        switch host {
        case "task":
            TaskActivityManager.shared.handleTaskURL(url)
        case "hook":
            AgentManager.shared.handleHookURL(url)
        case "interact":
            InteractionManager.shared.handleInteractURL(url)
        default:
            TaskActivityManager.shared.handleTaskURL(url)
            AgentManager.shared.handleHookURL(url)
            InteractionManager.shared.handleInteractURL(url)
        }
    }
    
    /// 供后台队列（Socket）调用：切回主 Actor。
    static func dispatchOnMainActor(_ url: URL) {
        Task { @MainActor in
            dispatch(url)
        }
    }
}
