//
//  TerminalManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import Foundation
import AppKit
import CoreGraphics

// Terminal application types
enum TerminalType: String, CaseIterable {
    case iterm2 = "iTerm2"
    case ghostty = "Ghostty"
    /// [cmux](https://github.com/manaflow-ai/cmux)：独立 App，与 Ghostty 不同 Bundle；需单独枚举/激活窗口。
    case cmux = "cmux"
    case warp = "Warp"
    case terminalApp = "Terminal.app"
    case vsCode = "VS Code"
    case cursor = "Cursor"
    case hyper = "Hyper"
    case alacritty = "Alacritty"
    case kitty = "Kitty"
    case tmux = "tmux"
    case zsh = "zsh"
    case bash = "bash"
    case fish = "fish"
    case windsurf = "Windsurf"
    
    var bundleIdentifier: String {
        switch self {
        case .iterm2: return "com.googlecode.iterm2"
        case .ghostty: return "com.ghostty.Ghostty"
        case .cmux: return "ai.manaflow.cmuxterm"
        case .warp: return "dev.warp.Warp-Stable"
        case .terminalApp: return "com.apple.Terminal"
        case .vsCode: return "com.microsoft.VSCode"
        case .cursor: return "com.cursor.sh"
        case .hyper: return "co.zeit.hyper"
        case .alacritty: return "io.alacritty"
        case .kitty: return "net.kovidgoyal.kitty"
        case .windsurf: return "com.windsurf.app"
        case .tmux: return "tmux"
        case .zsh: return "zsh"
        case .bash: return "bash"
        case .fish: return "fish"
        }
    }
    
    /// 不同安装渠道的 Bundle ID（用于识别运行中 App、Spotlight 检测已安装）。
    var knownBundleIdentifiers: [String] {
        switch self {
        case .ghostty:
            return ["com.ghostty.Ghostty", "com.mitchellh.ghostty"]
        case .warp:
            return ["dev.warp.Warp-Stable", "dev.warp.Warp"]
        case .alacritty:
            return ["io.alacritty", "org.alacritty.Alacritty"]
        default:
            return [bundleIdentifier]
        }
    }
    
    var executableName: String {
        switch self {
        case .iterm2: return "iTerm"
        case .ghostty: return "Ghostty"
        case .cmux: return "cmux"
        case .warp: return "Warp"
        case .terminalApp: return "Terminal"
        case .vsCode: return "Code"
        case .cursor: return "Cursor"
        case .hyper: return "Hyper"
        case .alacritty: return "alacritty"
        case .kitty: return "kitty"
        case .windsurf: return "Windsurf"
        case .tmux: return "tmux"
        case .zsh: return "zsh"
        case .bash: return "bash"
        case .fish: return "fish"
        }
    }
    
    var isGUIApp: Bool {
        switch self {
        case .tmux, .zsh, .bash, .fish:
            return false
        default:
            return true
        }
    }
    
    /// Cursor / VS Code / Windsurf。
    var isIDEApp: Bool {
        switch self {
        case .vsCode, .cursor, .windsurf: return true
        default: return false
        }
    }
    
    /// 精确跳转：与捆绑 VSIX 协同，支持 iTerm2（含 tmux -CC）、Ghostty 1.3+、cmux、Terminal.app、Warp、VS Code / Cursor / Windsurf 集成终端。
    var supportsPreciseJumping: Bool {
        switch self {
        case .iterm2, .terminalApp, .ghostty, .cmux, .warp, .vsCode, .cursor, .windsurf:
            return true
        default:
            return false
        }
    }
    
    /// 无 VSIX 深度集成时：尽力用 AppleScript 按窗口标题匹配并前置；失败则仅 `activate` 应用（Alacritty / Kitty / Hyper）。
    var supportsBestEffortWindowMatching: Bool {
        appleScriptNameForBestEffortWindows != nil
    }
    
    /// `tell application "…"` 中的名称，用于枚举窗口与按标题激活。
    var appleScriptNameForBestEffortWindows: String? {
        switch self {
        case .alacritty: return "Alacritty"
        case .kitty: return "kitty"
        case .hyper: return "Hyper"
        default: return nil
        }
    }
    
    /// 仅列出 AppleScript 枚举的窗口行，不展示 NSRunningApplication 主进程行（Terminal / iTerm2 / Ghostty / cmux / Warp）。
    var enumeratesWindowsViaAppleScript: Bool {
        switch self {
        case .iterm2, .terminalApp, .ghostty, .cmux, .warp: return true
        default: return false
        }
    }
}

// Terminal status
enum TerminalStatus {
    case notInstalled
    case installed
    case running
    case error(String)
    
    var description: String {
        switch self {
        case .notInstalled: return "Not Installed"
        case .installed: return "Installed"
        case .running: return "Running"
        case .error(let message): return "Error: \(message)"
        }
    }
}

// Terminal instance model
class TerminalInstance: Identifiable, Hashable {
    let id = UUID()
    let type: TerminalType
    let pid: Int32
    /// AppleScript 枚举行无独立进程 PID 时，填终端主应用 PID，便于用 `host_tty` 反查 shell 祖先链匹配到正确窗口。
    let ownerApplicationPID: Int32?
    let windowTitle: String?
    let workingDirectory: String?
    let activeCommand: String?
    let isRunning: Bool
    let windowId: String? // For precise jumping (e.g. iTerm2)
    
    init(type: TerminalType, pid: Int32, ownerApplicationPID: Int32? = nil, windowTitle: String? = nil, workingDirectory: String? = nil, activeCommand: String? = nil, isRunning: Bool = true, windowId: String? = nil) {
        self.type = type
        self.pid = pid
        self.ownerApplicationPID = ownerApplicationPID
        self.windowTitle = windowTitle
        self.workingDirectory = workingDirectory
        self.activeCommand = activeCommand
        self.isRunning = isRunning
        self.windowId = windowId
    }
    
    static func == (lhs: TerminalInstance, rhs: TerminalInstance) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// Terminal manager class
class TerminalManager {
    static let shared = TerminalManager()
    
    // Cache for terminal instances with expiration
    private var instanceCache: [TerminalInstance] = []
    private var lastCacheUpdate: Date = Date.distantPast
    private let cacheExpirationInterval: TimeInterval = 5 // 5 seconds cache
    
    private init() {}
    
    // Check if terminal is running using NSWorkspace
    func checkTerminalRunning(_ type: TerminalType) -> TerminalStatus {
        if type.isGUIApp {
            // Use NSWorkspace to check for running applications
            let runningApps = NSWorkspace.shared.runningApplications
            
            for app in runningApps {
                if let bundleIdentifier = app.bundleIdentifier {
                    if type.knownBundleIdentifiers.contains(bundleIdentifier) {
                        return .running
                    }
                }
                
                // Also check by executable name
                if let appName = app.localizedName {
                    if appName.contains(type.executableName) || type.executableName.contains(appName) {
                        return .running
                    }
                }
            }
            
            return checkTerminal(type)
        } else {
            // For CLI tools, use ps command
            let task = Process()
            task.launchPath = "/bin/ps"
            task.arguments = ["-c"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                if output.contains(type.executableName) {
                    return .running
                } else {
                    return checkTerminal(type)
                }
            } catch {
                return .error(error.localizedDescription)
            }
        }
    }
    
    // Check if terminal is installed
    func checkTerminal(_ type: TerminalType) -> TerminalStatus {
        if type.isGUIApp {
            // Check for GUI apps using mdfind
            let task = Process()
            task.launchPath = "/usr/bin/mdfind"
            let query = type.knownBundleIdentifiers
                .map { "kMDItemCFBundleIdentifier == '\($0)'" }
                .joined(separator: " || ")
            task.arguments = [query]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if output?.isEmpty == false {
                    return .installed
                } else {
                    return .notInstalled
                }
            } catch {
                return .error(error.localizedDescription)
            }
        } else {
            // Check for command-line tools
            let task = Process()
            task.launchPath = "/usr/bin/which"
            task.arguments = [type.executableName]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    return .installed
                } else {
                    return .notInstalled
                }
            } catch {
                return .error(error.localizedDescription)
            }
        }
    }
    
    // Open terminal with command
    func openTerminal(_ type: TerminalType, command: String, tab: Int = 0, split: Int = 0) -> Bool {
        if type.isGUIApp {
            // Open GUI terminal
            let task = Process()
            task.launchPath = "/usr/bin/open"
            
            switch type {
            case .iterm2:
                task.arguments = ["-a", type.executableName, "--args", "-e", command]
            case .terminalApp:
                task.arguments = ["-a", type.executableName, "--args", "-e", command]
            default:
                task.arguments = ["-a", type.executableName]
            }
            
            do {
                try task.run()
                return true
            } catch {
                return false
            }
        } else {
            // Open CLI terminal (not implemented for now)
            return false
        }
    }
    
    // Get status for all terminals
    func getStatusForAll() -> [TerminalType: TerminalStatus] {
        var results: [TerminalType: TerminalStatus] = [:]
        
        for terminal in TerminalType.allCases {
            results[terminal] = checkTerminalRunning(terminal)
        }
        
        return results
    }
    
    // Get installed terminals
    func getInstalledTerminals() -> [TerminalType] {
        var installed: [TerminalType] = []
        
        for terminal in TerminalType.allCases {
            let status = checkTerminal(terminal)
            if case .installed = status {
                installed.append(terminal)
            }
        }
        
        return installed
    }
    
    // Get running terminals
    func getRunningTerminals() -> [TerminalType] {
        var running: [TerminalType] = []
        
        for terminal in TerminalType.allCases {
            let status = checkTerminalRunning(terminal)
            if case .running = status {
                running.append(terminal)
            }
        }
        
        return running
    }
    
    // Get all terminal instances with window information
    func getAllTerminalInstances() -> [TerminalInstance] {
        // Check if cache is still valid
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < cacheExpirationInterval && !instanceCache.isEmpty {
            return instanceCache
        }
        
        var instances: [TerminalInstance] = []
        var seenPIDs: Set<Int32> = []
        
        // Get all running applications from NSWorkspace
        let runningApps = NSWorkspace.shared.runningApplications
        
        for app in runningApps {
            let pid = app.processIdentifier
            
            // Skip if we've already processed this PID
            if seenPIDs.contains(pid) { continue }
            seenPIDs.insert(pid)
            
            // Check if this is a terminal app by bundle identifier or name
            if let terminalType = getTerminalTypeForApp(app) {
                if terminalType.enumeratesWindowsViaAppleScript {
                    // 只展示各窗口行，不展示应用主进程汇总行
                    let additionalWindows = getAdditionalWindows(for: terminalType, mainPID: pid, seenPIDs: &seenPIDs)
                    instances.append(contentsOf: additionalWindows)
                } else {
                    let windowTitle = app.localizedName
                    let workingDirectory = getWorkingDirectory(for: pid)
                    let activeCommand = getActiveCommand(for: pid)
                    let windowId = getWindowId(for: pid, type: terminalType)
                    
                    let instance = TerminalInstance(
                        type: terminalType,
                        pid: pid,
                        ownerApplicationPID: nil,
                        windowTitle: windowTitle,
                        workingDirectory: workingDirectory,
                        activeCommand: activeCommand,
                        windowId: windowId
                    )
                    instances.append(instance)
                    
                    if terminalType.supportsPreciseJumping || terminalType.supportsBestEffortWindowMatching {
                        let more = getAdditionalWindows(for: terminalType, mainPID: pid, seenPIDs: &seenPIDs)
                        instances.append(contentsOf: more)
                    }
                }
            }
        }
        
        // NOTE:
        // We intentionally do NOT append CLI process entries (zsh/bash/fish/tmux) here.
        // They are often shell subprocesses without a stable, clickable window target,
        // which creates "fake rows" that cannot be activated from UI.
        
        // Update cache
        instanceCache = instances
        lastCacheUpdate = now
        
        return instances
    }
    
    // Clear cache to force refresh
    func clearCache() {
        instanceCache.removeAll()
        lastCacheUpdate = Date.distantPast
    }
    
    // Get terminal type for a running application
    private func getTerminalTypeForApp(_ app: NSRunningApplication) -> TerminalType? {
        // Check by bundle identifier
        if let bundleIdentifier = app.bundleIdentifier {
            return TerminalType.allCases.first(where: { $0.knownBundleIdentifiers.contains(bundleIdentifier) })
        }
        
        // Check by application name
        if let appName = app.localizedName {
            return TerminalType.allCases.first(where: { type in
                type.isGUIApp && (appName.contains(type.executableName) || type.executableName.contains(appName))
            })
        }
        
        return nil
    }
    
    // Get additional windows for supported terminals
    private func getAdditionalWindows(for type: TerminalType, mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        switch type {
        case .iterm2:
            instances.append(contentsOf: getITerm2Windows(mainPID: mainPID, seenPIDs: &seenPIDs))
        case .terminalApp:
            instances.append(contentsOf: getTerminalAppWindows(mainPID: mainPID, seenPIDs: &seenPIDs))
        case .ghostty:
            instances.append(contentsOf: getGhosttyWindows(mainPID: mainPID, seenPIDs: &seenPIDs))
        case .cmux:
            instances.append(contentsOf: getCmuxWindows(mainPID: mainPID, seenPIDs: &seenPIDs))
        case .warp:
            instances.append(contentsOf: getWarpWindows(mainPID: mainPID, seenPIDs: &seenPIDs))
        case .alacritty, .kitty, .hyper:
            if let appName = type.appleScriptNameForBestEffortWindows {
                instances.append(contentsOf: getBestEffortGUIWindows(applicationAppleScriptName: appName, type: type, mainPID: mainPID))
            }
        default:
            break
        }
        
        return instances
    }
    
    /// Alacritty / Kitty / Hyper：若应用实现标准窗口 AppleScript，则列出各窗口标题行（尽力而为，失败则返回空）。
    private func getBestEffortGUIWindows(applicationAppleScriptName: String, type: TerminalType, mainPID: Int32) -> [TerminalInstance] {
        let titles = windowTitlesViaStandardAppleScript(applicationName: applicationAppleScriptName)
        return titles.map { t in
            TerminalInstance(type: type, pid: 0, ownerApplicationPID: mainPID, windowTitle: t)
        }
    }
    
    private func windowTitlesViaStandardAppleScript(applicationName: String) -> [String] {
        let safe = appleScriptEscaped(applicationName)
        let script = """
        tell application "\(safe)"
            set rs to ASCII character 30
            set out to ""
            repeat with i from 1 to count of windows
                set windowName to name of window i
                set out to out & windowName & rs
            end repeat
            return out
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            return output.components(separatedBy: rs).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
    
    // Get iTerm2 windows
    private func getITerm2Windows(mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        // RS between records; US between window id and title (titles may contain commas or "|||")
        let script = """
        tell application "iTerm2"
            set rs to ASCII character 30
            set us to ASCII character 31
            set out to ""
            repeat with w in windows
                set wid to id of w as text
                set windowName to name of w
                set out to out & wid & us & windowName & rs
            end repeat
            return out
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            let us = "\u{1F}"
            
            for record in output.components(separatedBy: rs) where !record.isEmpty {
                let parts = record.split(separator: Character(us), maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2 else { continue }
                let windowId = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let windowTitle = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if windowId.isEmpty || windowTitle.isEmpty { continue }
                let instance = TerminalInstance(
                    type: .iterm2,
                    pid: 0,
                    ownerApplicationPID: mainPID,
                    windowTitle: windowTitle,
                    windowId: windowId
                )
                instances.append(instance)
            }
        } catch {
            // Ignore errors
        }
        
        return instances
    }
    
    // Get Terminal.app windows
    private func getTerminalAppWindows(mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        // RS (ASCII 30) between window titles only — activation matches by title at click time (no stale index).
        let script = """
        tell application "Terminal"
            set rs to ASCII character 30
            set out to ""
            repeat with i from 1 to count of windows
                set windowName to name of window i
                set out to out & windowName & rs
            end repeat
            return out
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            
            for windowTitle in output.components(separatedBy: rs) {
                let t = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                instances.append(TerminalInstance(type: .terminalApp, pid: 0, ownerApplicationPID: mainPID, windowTitle: t))
            }
        } catch {
            // Ignore errors
        }
        
        return instances
    }
    
    // Get Ghostty windows
    private func getGhosttyWindows(mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        let script = """
        tell application "Ghostty"
            set rs to ASCII character 30
            set out to ""
            repeat with i from 1 to count of windows
                set windowName to name of window i
                set out to out & windowName & rs
            end repeat
            return out
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            
            for windowTitle in output.components(separatedBy: rs) {
                let t = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                instances.append(TerminalInstance(type: .ghostty, pid: 0, ownerApplicationPID: mainPID, windowTitle: t))
            }
        } catch {
            // Ignore errors
        }
        
        return instances
    }
    
    /// cmux 与 Ghostty 为不同应用；用 `tell application id` 避免与 Ghostty 的脚本命名冲突。
    private func getCmuxWindows(mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        let titles = windowTitlesViaAppleScriptApplicationId(TerminalType.cmux.bundleIdentifier)
        return titles.map { t in
            TerminalInstance(type: .cmux, pid: 0, ownerApplicationPID: mainPID, windowTitle: t)
        }
    }
    
    private func windowTitlesViaAppleScriptApplicationId(_ bundleIdentifier: String) -> [String] {
        let safeId = appleScriptEscaped(bundleIdentifier)
        let script = """
        tell application id "\(safeId)"
            set rs to ASCII character 30
            set out to ""
            repeat with i from 1 to count of windows
                set windowName to name of window i
                set out to out & windowName & rs
            end repeat
            return out
        end tell
        """
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            return output.components(separatedBy: rs).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        } catch {
            return []
        }
    }
    
    // Get Warp windows
    private func getWarpWindows(mainPID: Int32, seenPIDs: inout Set<Int32>) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        let script = """
        tell application "Warp"
            set rs to ASCII character 30
            set out to ""
            repeat with i from 1 to count of windows
                set windowName to name of window i
                set out to out & windowName & rs
            end repeat
            return out
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let rs = "\u{1E}"
            
            for windowTitle in output.components(separatedBy: rs) {
                let t = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.isEmpty { continue }
                instances.append(TerminalInstance(type: .warp, pid: 0, ownerApplicationPID: mainPID, windowTitle: t))
            }
        } catch {
            // Ignore errors
        }
        
        return instances
    }
    
    // Get window ID for precise jumping
    private func getWindowId(for pid: Int32, type: TerminalType) -> String? {
        switch type {
        case .iterm2:
            return getITerm2WindowId(for: pid)
        case .terminalApp:
            return getTerminalAppWindowId(for: pid)
        default:
            return nil
        }
    }
    
    // Get iTerm2 window ID
    private func getITerm2WindowId(for pid: Int32) -> String? {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                if id of w is \(pid) then
                    return id of w as string
                end if
            end repeat
            return ""
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let windowId = output, !windowId.isEmpty {
                return windowId
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // Get Terminal.app window ID
    private func getTerminalAppWindowId(for pid: Int32) -> String? {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                if id of w is \(pid) then
                    return name of w
                end if
            end repeat
            return ""
        end tell
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let windowName = output, !windowName.isEmpty {
                return windowName
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // Get working directory for a process
    private func getWorkingDirectory(for pid: Int32) -> String? {
        let task = Process()
        task.launchPath = "/usr/bin/lsof"
        task.arguments = ["-p", String(pid), "-Fn"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            // Parse lsof output to find cwd
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                if line.hasPrefix("nc") && line.count > 2 {
                    let path = String(line.dropFirst(2))
                    if !path.isEmpty && path != "/" {
                        return path
                    }
                }
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // Get active command for a process
    private func getActiveCommand(for pid: Int32) -> String? {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-p", String(pid), "-o", "command="]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if let command = output, !command.isEmpty {
                return command
            }
        } catch {
            // Ignore errors
        }
        
        return nil
    }
    
    // Get CLI terminal instances
    private func getCLIInstances(for type: TerminalType) -> [TerminalInstance] {
        var instances: [TerminalInstance] = []
        
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-c"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            let lines = output.components(separatedBy: "\n")
            for line in lines {
                if line.contains(type.executableName) {
                    let components = line.split(separator: " ").map(String.init)
                    if let pidStr = components.first, let pid = Int32(pidStr) {
                        let instance = TerminalInstance(
                            type: type,
                            pid: pid,
                            activeCommand: type.executableName
                        )
                        instances.append(instance)
                    }
                }
            }
        } catch {
            // Ignore errors
        }
        
        return instances
    }
    
    /// CLI 任务点击跳转：与侧栏「终端列表」同一套 `activateInstance` 路径；不调用 `cursor -r` / `code -r`。
    ///
    /// **精确跳转**（捆绑 VSIX 协同）：iTerm2（含 tmux -CC）、Ghostty 1.3+、cmux、Terminal.app、Warp、VS Code / Cursor / Windsurf 集成终端。
    ///
    /// **尽力匹配**：Alacritty、Kitty、Hyper 等——有窗口 AppleScript 时按标题前置窗口，否则仅激活应用。
    ///
    /// - iTerm：优先 `iterm_sid` / `host_tty` 会话级 AppleScript。
    /// - 候选按 `workspaceMatchScore` 降序依次 `activateInstance`，直到成功。
    /// - `titleHint`：钩子未带 `cwd` 时，用任务标题里「项目名 · …」等片段与窗口标题做尽力匹配。
    @discardableResult
    func activateBestWindow(forWorkspacePath workspace: String, hints: CLITaskWindowHints = CLITaskWindowHints(), titleHint: String? = nil) -> Bool {
        let trimmed = workspace.trimmingCharacters(in: .whitespacesAndNewlines)
        let ttyPids: Set<Int32> = {
            guard let tty = hints.hostTTY?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil else { return [] }
            return Set(pidsUsingTTYDevice(normalizeTTYPath(tty)))
        }()
        let ttyAncestors: [Int32: Set<Int32>] = Dictionary(uniqueKeysWithValues: ttyPids.map { ($0, ancestorPIDSet(of: $0)) })
        
        if let sid = hints.itermSessionID?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
           activateITerm2SessionByUniqueID(sid) {
            handOffKeyboardAfterActivating(targetType: .iterm2)
            return true
        }
        if let tty = hints.hostTTY?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
           activateITerm2SessionByTTYPath(normalizeTTYPath(tty)) {
            handOffKeyboardAfterActivating(targetType: .iterm2)
            return true
        }
        
        clearCache()
        let target = trimmed.isEmpty ? "" : normalizePathForWorkspaceMatch(trimmed)
        let instances = getAllTerminalInstances()
        let expandedPath = (trimmed as NSString).expandingTildeInPath
        let workspaceLeaf = (expandedPath as NSString).lastPathComponent
        
        let ranked = instances
            .map { ($0, workspaceMatchScore(instance: $0, targetPath: target, rawWorkspace: trimmed, ttyPids: ttyPids, ttyAncestors: ttyAncestors, hints: hints)) }
            .filter { $0.1 > 0 }
            .sorted { a, b in
                if a.1 != b.1 { return a.1 > b.1 }
                let ta = windowTitleTieBreakScore(title: a.0.windowTitle, workspacePath: expandedPath, leaf: workspaceLeaf)
                let tb = windowTitleTieBreakScore(title: b.0.windowTitle, workspacePath: expandedPath, leaf: workspaceLeaf)
                if ta != tb { return ta > tb }
                return (a.0.windowTitle ?? "") < (b.0.windowTitle ?? "")
            }
        
        for (inst, _) in ranked {
            if activateInstance(inst) { return true }
        }
        
        if !trimmed.isEmpty, activateTerminalWindowByTitleHeuristic(instances: instances, workspace: trimmed) {
            return true
        }
        
        if let hint = titleHint?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
           activateInstancesByTaskTitleHints(instances: instances, titleHint: hint) {
            return true
        }
        
        if activateByTermProgramHint(hints: hints, instances: instances) {
            return true
        }
        
        if let raw = hints.termProgram?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
           let appName = appleScriptApplicationNameForTermProgram(raw),
           tellApplicationToActivate(named: appName) {
            handOffKeyboardAfterActivating(targetType: terminalTypeForHandoffFromTermProgram(raw))
            return true
        }
        
        if activateAnyRunningTerminalAppLastResort(preferTypes: termProgramPreferredTypes(hints.termProgram)) {
            return true
        }
        
        return false
    }
    
    /// 同分时优先标题里含工程目录名 / 父目录名的窗口，减少「跳到第一个 Terminal 标签」的随机性。
    private func windowTitleTieBreakScore(title: String?, workspacePath: String, leaf: String) -> Int {
        guard let t = title, !t.isEmpty else { return 0 }
        var s = 0
        if leaf.count >= 2, leaf != "/", t.localizedCaseInsensitiveContains(leaf) { s += 50 }
        let parent = (workspacePath as NSString).deletingLastPathComponent
        let parentLeaf = (parent as NSString).lastPathComponent
        if parentLeaf.count >= 2, t.localizedCaseInsensitiveContains(parentLeaf) { s += 20 }
        return s
    }
    
    /// `TERM_PROGRAM` → AppleScript `tell application "…"` 显示名（与「访达 / 脚本编辑器」里一致）。
    private func appleScriptApplicationNameForTermProgram(_ raw: String) -> String? {
        let t = raw.lowercased()
        if t.isEmpty { return nil }
        if t.contains("apple_terminal") || t == "terminal" { return "Terminal" }
        if t.contains("iterm") { return "iTerm2" }
        if t.contains("ghostty") { return "Ghostty" }
        if t.contains("cmux") { return "cmux" }
        if t.contains("warp") { return "Warp" }
        if t.contains("kitty") { return "kitty" }
        if t.contains("alacritty") { return "Alacritty" }
        if t.contains("hyper") { return "Hyper" }
        if t.contains("cursor") { return "Cursor" }
        if t.contains("vscode") || t.contains("code") { return "Visual Studio Code" }
        if t.contains("windsurf") { return "Windsurf" }
        return nil
    }
    
    private func tellApplicationToActivate(named displayName: String) -> Bool {
        let safe = appleScriptEscaped(displayName)
        let script = """
        tell application "\(safe)"
            activate
        end tell
        return true
        """
        return runAppleScriptReturningBool(script)
    }
    
    private func terminalTypeForHandoffFromTermProgram(_ raw: String) -> TerminalType {
        termProgramPreferredTypes(raw).first ?? .terminalApp
    }
    
    /// `TERM_PROGRAM=Apple_Terminal` 等与 `TerminalType` 对齐，用于最后兜底时的顺序。
    private func termProgramPreferredTypes(_ raw: String?) -> [TerminalType] {
        let tp = (raw ?? "").lowercased()
        if tp.isEmpty { return [] }
        if tp.contains("apple_terminal") || tp == "terminal" { return [.terminalApp] }
        if tp.contains("iterm") { return [.iterm2] }
        if tp.contains("ghostty") { return [.ghostty] }
        if tp.contains("cmux") { return [.cmux] }
        if tp.contains("warp") { return [.warp] }
        if tp.contains("kitty") { return [.kitty] }
        if tp.contains("alacritty") { return [.alacritty] }
        if tp.contains("hyper") { return [.hyper] }
        if tp.contains("cursor") { return [.cursor] }
        if tp.contains("vscode") || tp.contains("code") { return [.vsCode] }
        if tp.contains("windsurf") { return [.windsurf] }
        return []
    }
    
    /// 钩子已标明宿主终端类型时，对该类型窗口逐个点一遍；再 `tell application … to activate`。
    private func activateByTermProgramHint(hints: CLITaskWindowHints, instances: [TerminalInstance]) -> Bool {
        let prefs = termProgramPreferredTypes(hints.termProgram)
        guard !prefs.isEmpty else { return false }
        for t in prefs {
            let rows = instances.filter { $0.type == t }
            for inst in rows {
                if activateInstance(inst) { return true }
            }
            if let app = findRunningGUIApp(for: t), activateRunningApplicationFrontmost(app, terminalType: t) {
                return true
            }
        }
        return false
    }
    
    /// 匹配全失败时仍尝试把「正在跑的终端/IDE」拉到前台（`activate([])` 从 Accessory 应用调用常无效）。
    private func activateAnyRunningTerminalAppLastResort(preferTypes: [TerminalType] = []) -> Bool {
        // 外置终端优先于 IDE：多数 CLI 钩子跑在 iTerm/Ghostty/cmux 等；全失败时再试 Cursor/VS Code。
        let defaultOrder: [TerminalType] = [
            .iterm2, .ghostty, .cmux, .warp, .terminalApp,
            .kitty, .alacritty, .hyper,
            .cursor, .vsCode, .windsurf
        ]
        var order = preferTypes
        for t in defaultOrder where !order.contains(t) {
            order.append(t)
        }
        for type in order {
            guard let app = findRunningGUIApp(for: type) else { continue }
            if activateRunningApplicationFrontmost(app, terminalType: type) {
                return true
            }
        }
        return false
    }
    
    private func activateRunningApplicationFrontmost(_ app: NSRunningApplication, terminalType: TerminalType) -> Bool {
        if app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows]) {
            handOffKeyboardAfterActivating(targetType: terminalType)
            return true
        }
        if let bid = app.bundleIdentifier, activateApplicationByAppleScript(bundleIdentifier: bid) {
            handOffKeyboardAfterActivating(targetType: terminalType)
            return true
        }
        return false
    }
    
    /// iTerm2：按会话唯一 id（环境变量 `ITERM_SESSION_ID`）选中标签。
    private func activateITerm2SessionByUniqueID(_ sessionID: String) -> Bool {
        let safe = appleScriptEscaped(sessionID)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (id of s as text) is "\(safe)" then
                                select s
                                set frontmost of w to true
                                activate
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }
    
    /// iTerm2：按伪终端设备路径匹配会话（与钩子 `host_tty` 一致）。
    private func activateITerm2SessionByTTYPath(_ ttyPath: String) -> Bool {
        let safe = appleScriptEscaped(ttyPath)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        try
                            if (tty of s as text) is "\(safe)" then
                                select s
                                set frontmost of w to true
                                activate
                                return true
                            end if
                        end try
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }
    
    private func normalizeTTYPath(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return t }
        if t.hasPrefix("/dev/") { return t }
        if t.hasPrefix("tty") { return "/dev/" + t }
        return t
    }
    
    /// `lsof -t` 列出占用该 TTY 设备的进程（shell、node 等）。
    private func pidsUsingTTYDevice(_ ttyPath: String) -> [Int32] {
        let path = normalizeTTYPath(ttyPath)
        guard path.hasPrefix("/dev/"), FileManager.default.fileExists(atPath: path) else { return [] }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-t", path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return text.components(separatedBy: .newlines).compactMap { line in
                let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return t.isEmpty ? nil : Int32(t)
            }
        } catch {
            return []
        }
    }
    
    private func anchorPID(for instance: TerminalInstance) -> Int32? {
        if instance.pid != 0 { return instance.pid }
        if let o = instance.ownerApplicationPID, o > 0 { return o }
        return nil
    }
    
    private func parentPID(of pid: Int32) -> Int32? {
        guard pid > 0 else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-o", "ppid=", "-p", String(pid)]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard let pp = Int32(s), pp > 0 else { return nil }
            return pp
        } catch {
            return nil
        }
    }
    
    private func ancestorPIDSet(of pid: Int32, maxDepth: Int = 48) -> Set<Int32> {
        var set = Set<Int32>()
        var cur: Int32? = pid
        var depth = 0
        while let p = cur, p > 1, depth < maxDepth {
            set.insert(p)
            cur = parentPID(of: p)
            depth += 1
        }
        return set
    }
    
    /// 从钩子侧 `host_ppid`（多为 Claude/shell 的父进程）沿 `ppid` 链向上，是否经过该终端窗口所属 App 主进程（AppleScript 行 `pid==0` 时只靠此项命中）。
    private func hostParentChainContainsOwner(hostStart: Int32, ownerPID: Int32) -> Bool {
        guard hostStart > 1, ownerPID > 1 else { return false }
        var cur: Int32? = hostStart
        var depth = 0
        while let p = cur, p > 1, depth < 64 {
            if p == ownerPID { return true }
            cur = parentPID(of: p)
            depth += 1
        }
        return false
    }
    
    private func normalizePathForWorkspaceMatch(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            return url.resolvingSymlinksInPath().standardizedFileURL.path
        }
        return url.standardizedFileURL.path
    }
    
    /// 分越高越优先：TTY 直配 → 宿主 ppid → TTY 祖先链 ∩ 终端主进程 → 路径 → 标题含目录名。
    /// IDE 行仅在 `term_program` 等表明**集成终端**时才参与 TTY 祖先链加分，避免外置终端误匹配 Electron。
    private func workspaceMatchScore(instance: TerminalInstance, targetPath: String, rawWorkspace: String, ttyPids: Set<Int32>, ttyAncestors: [Int32: Set<Int32>], hints: CLITaskWindowHints) -> Int {
        var score = 0
        if instance.pid != 0, ttyPids.contains(instance.pid) {
            score = max(score, 2600)
        }
        if let ppid = hints.hostParentPID, instance.pid != 0, instance.pid == ppid {
            score = max(score, 2400)
        }
        if let ppid = hints.hostParentPID, ppid > 1, let owner = instance.ownerApplicationPID, owner > 1,
           hostParentChainContainsOwner(hostStart: ppid, ownerPID: owner) {
            score = max(score, 2380)
        }
        if let ppid = hints.hostParentPID, ppid > 1, instance.pid > 1,
           hostParentChainContainsOwner(hostStart: ppid, ownerPID: instance.pid) {
            score = max(score, 2370)
        }
        let allowIDEttyAnchor = !instance.type.isIDEApp || hintsSuggestIDEIntegratedTerminal(hints)
        if allowIDEttyAnchor, let anchor = anchorPID(for: instance), anchor > 0 {
            for tp in ttyPids {
                if ttyAncestors[tp]?.contains(anchor) == true {
                    score = max(score, 2300)
                    break
                }
            }
        }
        if !targetPath.isEmpty, let cwd = instance.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines), !cwd.isEmpty {
            let inst = normalizePathForWorkspaceMatch(cwd)
            if inst == targetPath {
                score = max(score, 1000)
            } else if targetPath.hasPrefix(inst + "/") || inst.hasPrefix(targetPath + "/") {
                score = max(score, 500)
            } else if targetPath.hasPrefix(inst) || inst.hasPrefix(targetPath) {
                score = max(score, 300)
            }
        }
        let base = (rawWorkspace as NSString).expandingTildeInPath
        let leaf = (base as NSString).lastPathComponent
        if !leaf.isEmpty, leaf != "/", let title = instance.windowTitle, title.contains(leaf) {
            score = max(score, score >= 300 ? score : 110)
        }
        // 无 cwd/标题路径片段时，ranked 可能全为空，只能 `activate` 到 app；用 TERM_PROGRAM 与实例类型对齐给出最低分，让 `activateTerminalAppWindow` 等按窗口执行。
        if let tp = hints.termProgram?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil,
           termProgramMatchesTerminalType(tp, instance.type) {
            score = max(score, 75)
        }
        return score
    }
    
    private func termProgramMatchesTerminalType(_ termProgram: String, _ type: TerminalType) -> Bool {
        let t = termProgram.lowercased()
        switch type {
        case .terminalApp: return t.contains("apple_terminal") || t == "terminal"
        case .iterm2: return t.contains("iterm")
        case .ghostty: return t.contains("ghostty")
        case .cmux: return t.contains("cmux")
        case .warp: return t.contains("warp")
        case .kitty: return t.contains("kitty")
        case .alacritty: return t.contains("alacritty")
        case .hyper: return t.contains("hyper")
        case .cursor: return t.contains("cursor")
        case .vsCode: return t.contains("vscode") || t.contains("code")
        case .windsurf: return t.contains("windsurf")
        case .tmux, .zsh, .bash, .fish: return false
        }
    }
    
    private func hintsSuggestIDEIntegratedTerminal(_ hints: CLITaskWindowHints) -> Bool {
        let tp = (hints.termProgram ?? "").lowercased()
        if tp.isEmpty { return false }
        if tp.contains("vscode") { return true }
        if tp.contains("cursor") { return true }
        if tp.contains("code-helper") { return true }
        if tp.contains("windsurf") { return true }
        if tp.contains("electron") && (tp.contains("cursor") || tp.contains("code")) { return true }
        return false
    }
    
    /// `cwd` 未采集到时的补救：窗口标题含项目目录名（含 IDE 集成终端行）。
    private func activateTerminalWindowByTitleHeuristic(instances: [TerminalInstance], workspace: String) -> Bool {
        let expanded = (workspace as NSString).expandingTildeInPath
        let leaf = (expanded as NSString).lastPathComponent
        guard leaf.count >= 2, leaf != "/" else { return false }
        let candidates = instances.filter { inst in
            guard isLikelyCLISurface(inst.type), let title = inst.windowTitle, !title.isEmpty else { return false }
            return title.localizedCaseInsensitiveContains(leaf)
        }
        for pick in candidates {
            if activateInstance(pick) { return true }
        }
        return false
    }
    
    /// 任务标题常见形如 `myapp · 会话 abc…` 或与路径无关的说明；拆出可匹配的片段与终端/IDE 窗口标题对齐。
    private func activateInstancesByTaskTitleHints(instances: [TerminalInstance], titleHint: String) -> Bool {
        let segments = titleHintSegments(from: titleHint)
        guard !segments.isEmpty else { return false }
        for segment in segments {
            let candidates = instances.filter { inst in
                guard isLikelyCLISurface(inst.type), let title = inst.windowTitle, !title.isEmpty else { return false }
                return title.localizedCaseInsensitiveContains(segment)
            }
            for pick in candidates {
                if activateInstance(pick) { return true }
            }
        }
        return false
    }
    
    private func titleHintSegments(from raw: String) -> [String] {
        var parts: [String] = []
        let splitters: [Character] = ["·", "—", "-", "|", "•"]
        var current = ""
        for ch in raw {
            if splitters.contains(ch) {
                let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.count >= 2 { parts.append(t) }
                current = ""
            } else {
                current.append(ch)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.count >= 2 { parts.append(tail) }
        if parts.isEmpty, raw.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
            return [raw.trimmingCharacters(in: .whitespacesAndNewlines)]
        }
        var seen = Set<String>()
        return parts.filter { seen.insert($0).inserted }
    }
    
    private func isLikelyCLISurface(_ type: TerminalType) -> Bool {
        switch type {
        case .iterm2, .terminalApp, .ghostty, .cmux, .warp, .hyper, .alacritty, .kitty,
             .vsCode, .cursor, .windsurf:
            return true
        case .tmux, .zsh, .bash, .fish:
            return false
        }
    }
    
    // Activate terminal instance with precise jumping
    func activateInstance(_ instance: TerminalInstance) -> Bool {
        let ok: Bool
        if instance.type.supportsPreciseJumping {
            if activateWithPreciseJumping(instance) {
                ok = true
            } else if instance.type.isGUIApp {
                // Main-process rows use localized app name as windowTitle (e.g. "终端"), which never
                // matches Terminal.app window titles — precise AppleScript then fails with no recovery.
                ok = activateWithFallback(instance)
            } else {
                ok = false
            }
        } else if instance.type.supportsBestEffortWindowMatching {
            if activateBestEffortTerminalWindow(instance) {
                ok = true
            } else {
                ok = activateWithFallback(instance)
            }
        } else {
            ok = activateWithFallback(instance)
        }
        if ok {
            handOffKeyboardAfterActivating(targetType: instance.type)
        }
        return ok
    }
    
    /// 仅对集成终端 IDE：`NSApp.deactivate()` 曾导致外置 Terminal 激活后焦点仍被 Accessory 岛抢回；纯终端路径不再 deactivate。
    private func handOffKeyboardAfterActivating(targetType: TerminalType) {
        switch targetType {
        case .vsCode, .cursor, .windsurf:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                NSApp.deactivate()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.postControlGraveForElectronTerminal()
            }
        default:
            break
        }
    }
    
    /// 发送 Control+`（ANSI Grave），与 VS Code / Cursor 默认「切换终端」一致；非美式键盘布局可能不同。
    private func postControlGraveForElectronTerminal() {
        let keyCode: CGKeyCode = 0x32 // kVK_ANSI_Grave
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        let flags = CGEventFlags.maskControl
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false) else { return }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
    
    // Activate terminal with precise jumping
    private func activateWithPreciseJumping(_ instance: TerminalInstance) -> Bool {
        switch instance.type {
        case .iterm2:
            return activateITerm2Window(instance)
        case .terminalApp:
            return activateTerminalAppWindow(instance)
        case .ghostty:
            return activateGhosttyWindow(instance)
        case .cmux:
            return activateCmuxWindow(instance)
        case .warp:
            return activateWarpWindow(instance)
        case .vsCode, .cursor, .windsurf:
            return activateIDEWindow(instance)
        default:
            return false
        }
    }
    
    // Activate iTerm2 window
    private func activateITerm2Window(_ instance: TerminalInstance) -> Bool {
        guard let windowId = instance.windowId else { return false }
        let safe = appleScriptEscaped(windowId)
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                if (id of w as text) is "\(safe)" then
                    set frontmost of w to true
                    activate
                    return true
                end if
            end repeat
            return false
        end tell
        """
        
        return runAppleScriptReturningBool(script)
    }
    
    private func runAppleScriptReturningBool(_ script: String) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return false }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return output == "true"
        } catch {
            return false
        }
    }
    
    /// Escape for embedding in AppleScript double-quoted string literals.
    private func appleScriptEscaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    /// 标准 `tell application` + 按窗口名称前置（Ghostty / Warp / Alacritty / Kitty / Hyper 共用）。
    private func activateFrontWindowByTitleAppleScript(applicationName: String, windowTitle: String) -> Bool {
        let safeApp = appleScriptEscaped(applicationName)
        let safeTitle = appleScriptEscaped(windowTitle)
        let script = """
        tell application "\(safeApp)"
            repeat with i from 1 to count of windows
                if name of window i is "\(safeTitle)" then
                    set frontmost of window i to true
                    activate
                    return true
                end if
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }
    
    private func activateBestEffortTerminalWindow(_ instance: TerminalInstance) -> Bool {
        guard let appName = instance.type.appleScriptNameForBestEffortWindows,
              let title = instance.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return false
        }
        return activateFrontWindowByTitleAppleScript(applicationName: appName, windowTitle: title)
    }
    
    // Activate Terminal.app window
    private func activateTerminalAppWindow(_ instance: TerminalInstance) -> Bool {
        guard let windowName = instance.windowTitle else { return false }
        let safe = appleScriptEscaped(windowName)
        // 按点击时刻的窗口顺序用标题匹配，避免缓存 window index 与堆叠顺序不一致导致跳错窗
        let script = """
        tell application "Terminal"
            repeat with i from 1 to count of windows
                if name of window i is "\(safe)" then
                    set frontmost of window i to true
                    activate
                    return true
                end if
            end repeat
            return false
        end tell
        """
        
        return runAppleScriptReturningBool(script)
    }
    
    // Activate Ghostty window
    private func activateGhosttyWindow(_ instance: TerminalInstance) -> Bool {
        guard let windowName = instance.windowTitle else { return false }
        return activateFrontWindowByTitleAppleScript(applicationName: "Ghostty", windowTitle: windowName)
    }
    
    private func activateCmuxWindow(_ instance: TerminalInstance) -> Bool {
        guard let windowName = instance.windowTitle else { return false }
        return activateFrontWindowByTitleAppleScriptApplicationId(
            bundleIdentifier: TerminalType.cmux.bundleIdentifier,
            windowTitle: windowName
        )
    }
    
    /// 按 Bundle ID 定位窗口（cmux 等与 Ghostty 脚本接口相似但应用名不同）。
    private func activateFrontWindowByTitleAppleScriptApplicationId(bundleIdentifier: String, windowTitle: String) -> Bool {
        let safeId = appleScriptEscaped(bundleIdentifier)
        let safeTitle = appleScriptEscaped(windowTitle)
        let script = """
        tell application id "\(safeId)"
            repeat with i from 1 to count of windows
                if name of window i is "\(safeTitle)" then
                    set frontmost of window i to true
                    activate
                    return true
                end if
            end repeat
            return false
        end tell
        """
        return runAppleScriptReturningBool(script)
    }
    
    // Activate Warp window
    private func activateWarpWindow(_ instance: TerminalInstance) -> Bool {
        guard let windowName = instance.windowTitle else { return false }
        return activateFrontWindowByTitleAppleScript(applicationName: "Warp", windowTitle: windowName)
    }
    
    // Activate IDE window
    private func activateIDEWindow(_ instance: TerminalInstance) -> Bool {
        // Resolve from running apps first. Some distributions (e.g. Cursor) use
        // dynamic bundle identifiers that differ from hardcoded defaults.
        if let app = findRunningGUIApp(for: instance.type),
           let dynamicBundleId = app.bundleIdentifier,
           activateApplicationByAppleScript(bundleIdentifier: dynamicBundleId) {
            return true
        }
        
        // Fallback to static bundle id.
        if activateApplicationByAppleScript(bundleIdentifier: instance.type.bundleIdentifier) {
            return true
        }

        // Fallback for environments where AppleScript activation is unavailable.
        if let app = findRunningGUIApp(for: instance.type) {
            _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            return true
        }
        return false
    }
    
    // Activate terminal with fallback (for terminals that don't support precise jumping)
    private func activateWithFallback(_ instance: TerminalInstance) -> Bool {
        if instance.type.isGUIApp {
            if let app = findRunningGUIApp(for: instance.type),
               let dynamicBundleId = app.bundleIdentifier,
               activateApplicationByAppleScript(bundleIdentifier: dynamicBundleId) {
                return true
            }
            
            if activateApplicationByAppleScript(bundleIdentifier: instance.type.bundleIdentifier) {
                return true
            }

            if let app = findRunningGUIApp(for: instance.type) {
                _ = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
                return true
            }
        }
        return false
    }

    // Find a running app by bundle identifier or by localized name fallback.
    private func findRunningGUIApp(for type: TerminalType) -> NSRunningApplication? {
        let runningApps = NSWorkspace.shared.runningApplications

        if let appByBundle = runningApps.first(where: { app in
            guard let bid = app.bundleIdentifier else { return false }
            return type.knownBundleIdentifiers.contains(bid)
        }) {
            return appByBundle
        }

        return runningApps.first(where: { app in
            guard let name = app.localizedName else { return false }
            return name.localizedCaseInsensitiveContains(type.executableName)
                || type.executableName.localizedCaseInsensitiveContains(name)
        })
    }
    
    // Activate an app using AppleScript by bundle identifier.
    private func activateApplicationByAppleScript(bundleIdentifier: String) -> Bool {
        let script = """
        tell application id "\(bundleIdentifier)"
            activate
        end tell
        return true
        """
        
        let task = Process()
        task.launchPath = "/usr/bin/osascript"
        task.arguments = ["-e", script]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus != 0 {
                return false
            }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return output == "true"
        } catch {
            return false
        }
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
