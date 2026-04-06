//
//  AiLandDiagnostics.swift
//  Ai_land
//
//  导出脱敏诊断文本：版本、Socket 路径、钩子存在性、PATH 探测等。
//

import AppKit
import Foundation

enum AiLandDiagnostics {
    static func buildReport() -> String {
        var lines: [String] = []
        let bundle = Bundle.main
        let ver = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        lines.append("\(IslandTheme.appDisplayName) \(ver) (\(build))")
        lines.append("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        lines.append("Home: \(NSHomeDirectory())")
        lines.append("Socket: /tmp/ai-land.sock (JSON 行协议，见下)")
        lines.append("")
        lines.append("— Hooks —")
        for t in AIAssistantType.allCases {
            let path = ConfigurationManager.shared.hookFilePath(for: t)
            let ok = FileManager.default.fileExists(atPath: path)
            lines.append("[\(ok ? "✓" : "·")] \(t.executableName): \(path)")
        }
        lines.append("")
        lines.append("— Claude extras —")
        let ask = ConfigurationManager.shared.claudeAskUserQuestionHookPath()
        lines.append("[\(FileManager.default.fileExists(atPath: ask) ? "✓" : "·")] AskUserQuestion: \(ask)")
        lines.append("")
        lines.append("— Sample socket line —")
        lines.append(#"{"op":"url","u":"ai-land://task?assistant=claude&state=running&task_id=demo&title=Demo"}"#)
        return lines.joined(separator: "\n")
    }
}
