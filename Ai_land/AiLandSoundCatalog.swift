//
//  AiLandSoundCatalog.swift
//  Ai_land
//
//  合并：App 包内 `music/` 资源与 macOS `/System/Library/Sounds`。
//

import Foundation

struct AiLandSoundRow: Identifiable, Hashable {
    /// `sys:Glass` 或 `res:music/foo.mp3`（相对 Bundle Resources）
    let id: String
    /// 列表展示名
    let title: String
    /// 分组标题
    let section: String
}

enum AiLandSoundCatalog {
    private static let audioExtensions: Set<String> = ["mp3", "m4a", "aiff", "aif", "caf", "wav"]

    static let sectionDisplayOrder = ["项目 music 文件夹", "macOS 系统音效"]

    /// 设置摘要行展示用。
    static func displayLabel(forToken token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("sys:") { return String(t.dropFirst(4)) }
        if t.hasPrefix("res:") {
            let path = String(t.dropFirst(4))
            return (path as NSString).deletingPathExtension.components(separatedBy: "/").last ?? path
        }
        return t.isEmpty ? "—" : t
    }

    /// 供设置界面与诊断使用；在 `Task { @MainActor in }` 外也可调用（仅读盘）。
    static func allRows() -> [AiLandSoundRow] {
        var rows: [AiLandSoundRow] = []
        rows.append(contentsOf: bundledMusicRows())
        rows.append(contentsOf: systemSoundRows())
        return rows
    }

    /// Xcode 将同步组 `music/` 内文件拷到 **Resources 根目录**，故 token 为 `res:文件名`。
    private static func bundledMusicRows() -> [AiLandSoundRow] {
        var urls: [URL] = []
        for ext in ["mp3", "m4a", "wav", "caf", "aiff", "aif"] {
            urls.append(contentsOf: Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? [])
        }
        return urls
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
            .map { url in
                let file = url.lastPathComponent
                let title = url.deletingPathExtension().lastPathComponent
                return AiLandSoundRow(
                    id: "res:\(file)",
                    title: title,
                    section: "项目 music 文件夹"
                )
            }
    }

    private static func systemSoundRows() -> [AiLandSoundRow] {
        let dir = URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { name in
                AiLandSoundRow(id: "sys:\(name)", title: name, section: "macOS 系统音效")
            }
    }
}
