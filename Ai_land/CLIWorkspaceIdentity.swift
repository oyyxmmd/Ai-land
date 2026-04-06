//
//  CLIWorkspaceIdentity.swift
//  Ai_land
//
//  由 context.abs_path（或 cwd）稳定映射配色，用于「一眼识屏」；Identicon 首字母。
//

import AppKit
import CryptoKit
import Foundation
import SwiftUI

enum CLIWorkspaceIdentity {
    /// 稳定锚点路径：优先 abs_path，否则 cwd，否则回退 task_id。
    static func anchorPath(absPath: String?, workspacePath: String?, taskId: String) -> String {
        if let a = absPath?.trimmingCharacters(in: .whitespacesAndNewlines), !a.isEmpty { return a }
        if let w = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty { return w }
        return "task:\(taskId)"
    }
    
    /// 固定饱和/明度区间，避免过浅或过深。
    static func nsColor(forAnchor path: String) -> NSColor {
        let digest = SHA256.hash(data: Data(path.utf8))
        let b = Array(digest)
        guard b.count >= 4 else {
            return NSColor(calibratedHue: 0.55, saturation: 0.5, brightness: 0.5, alpha: 1)
        }
        let b0 = Double(b[0])
        let b1 = Double(b[1])
        let b2 = Double(b[2])
        let b3 = Double(b[3])
        let hue = (b0 * 256 + b1) / 65535.0
        let sat = 0.52 + (b2 / 255.0) * 0.38
        let bri = 0.42 + (b3 / 255.0) * 0.38
        return NSColor(calibratedHue: hue, saturation: sat, brightness: bri, alpha: 1)
    }
    
    static func swiftUIColor(forAnchor path: String) -> Color {
        Color(nsColor: nsColor(forAnchor: path))
    }
    
    /// 展示用项目名：显式 project_name，否则取路径最后一段。
    static func displayProjectName(explicit: String?, workspacePath: String?) -> String? {
        if let e = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { return e }
        guard let w = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty else { return nil }
        let base = (w as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }
    
    /// Identicon 单字：project_name 或路径基名首字符（字母/数字/CJK 均可取首 grapheme）。
    static func identiconCharacter(projectName: String?, workspacePath: String?, titleFallback: String) -> String {
        var candidates: [String] = []
        if let p = projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty {
            candidates.append(p)
        }
        if let w = workspacePath?.trimmingCharacters(in: .whitespacesAndNewlines), !w.isEmpty {
            let base = (w as NSString).lastPathComponent
            if !base.isEmpty { candidates.append(base) }
        }
        let t = titleFallback.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { candidates.append(t) }
        guard let s = candidates.first else { return "?" }
        let ch = s.first.map(String.init) ?? "?"
        return ch.uppercased()
    }
}
