//
//  ConfigurationManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/2.
//

import Foundation
import os.log

private enum ConfigLog {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xiaoo.ai-land", category: "configure")
}

/// 支持的 6 款 AI 编码代理（CLI / 终端侧）：Claude Code、OpenAI Codex CLI、Google Gemini CLI、Cursor Agent、OpenCode、Factory Droid。
enum AIAssistantType: String, CaseIterable {
    case claudeCode = "Claude Code"
    case codex = "OpenAI Codex CLI"
    case geminiCLI = "Google Gemini CLI"
    case cursor = "Cursor Agent"
    case openCode = "OpenCode"
    case droid = "Factory Droid"
    
    var executableName: String {
        switch self {
        case .claudeCode: return "claude"
        case .codex: return "codex"
        case .geminiCLI: return "gemini"
        case .cursor: return "cursor"
        case .openCode: return "opencode"
        case .droid: return "droid"
        }
    }
    
    var hookPath: String {
        switch self {
        case .claudeCode: return "~/.claude/hooks"
        case .codex: return "~/.codex/hooks"
        case .geminiCLI: return "~/.gemini/hooks"
        case .cursor: return "~/.cursor/hooks"
        case .openCode: return "~/.opencode/hooks"
        case .droid: return "~/.droid/hooks"
        }
    }
}

extension AIAssistantType {
    /// 口语/文档/大小写与可执行名混用时映射到枚举（含 OpenCode / `opencode`）。
    private static let aliasMap: [String: AIAssistantType] = {
        var m: [String: AIAssistantType] = [:]
        func add(_ keys: [String], _ type: AIAssistantType) {
            for k in keys { m[k.lowercased()] = type }
        }
        add(["claude code", "claude"], .claudeCode)
        add(["codex", "openai codex", "openai codex cli"], .codex)
        add(["gemini", "gemini cli", "google gemini", "google gemini cli"], .geminiCLI)
        add(["cursor", "cursor agent"], .cursor)
        add(["opencode", "open code", "open-code", "opencodes", "open-code cli"], .openCode)
        add(["droid", "factory droid"], .droid)
        return m
    }()
    
    /// 将 `assistant` / `agent` 查询参数或钩子字段解析为枚举。
    static func resolve(from raw: String?) -> AIAssistantType? {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return nil }
        if let a = allCases.first(where: { $0.executableName == s }) { return a }
        if let a = allCases.first(where: { $0.rawValue.lowercased() == s }) { return a }
        return aliasMap[s]
    }
    
    /// 规范为可执行名（小写），便于任务列表与 hook 去重；未知 CLI 则退回原串小写。
    static func canonicalExecutable(from raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let a = resolve(from: t) { return a.executableName }
        return t.lowercased()
    }
}

// Configuration status
enum ConfigurationStatus {
    case notDetected
    case detected
    case configured
    case error(String)
    
    var description: String {
        switch self {
        case .notDetected: return L10n.str("cfg_not_detected")
        case .detected: return L10n.str("cfg_detected")
        case .configured: return L10n.str("cfg_configured")
        case .error(let message): return L10n.fmt("cfg_error_format", message)
        }
    }
}

// Configuration manager class
class ConfigurationManager {
    static let shared = ConfigurationManager()
    
    private init() {}
    
    /// 在 GUI 环境下补齐常见 PATH，避免 Finder 启动时 `which` 找不到 npm/homebrew 安装的 CLI。
    private var fallbackSearchPaths: [String] {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var paths = envPath.split(separator: ":").map(String.init)
        paths.append(contentsOf: [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "~/.npm/bin",
            "~/.local/bin",
            "~/.cargo/bin"
        ])
        // 去重并展开 ~
        var seen = Set<String>()
        return paths
            .map { ($0 as NSString).expandingTildeInPath }
            .filter { seen.insert($0).inserted }
    }
    
    private func executablePath(for command: String) -> String? {
        let fm = FileManager.default
        for base in fallbackSearchPaths {
            let candidate = (base as NSString).appendingPathComponent(command)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
    
    /// Hook 脚本路径（与 `configureAssistant` 写入的文件一致）
    func hookFilePath(for type: AIAssistantType) -> String {
        let expanded = (type.hookPath as NSString).expandingTildeInPath
        return (expanded as NSString).appendingPathComponent("ai_land_hook.sh")
    }
    
    /// `AskUserQuestion`（终端里 Choose / 多选列表）→ 灵动岛 的 PreToolUse 钩子（Python）
    func claudeAskUserQuestionHookPath() -> String {
        let expanded = (AIAssistantType.claudeCode.hookPath as NSString).expandingTildeInPath
        return (expanded as NSString).appendingPathComponent("ai_land_ask_user_question_hook.py")
    }
    
    func isHookInstalled(_ type: AIAssistantType) -> Bool {
        FileManager.default.fileExists(atPath: hookFilePath(for: type))
    }
    
    /// 综合状态：已安装 CLI 且 hook 已落盘 → configured；仅 CLI → detected
    func configurationStatus(for type: AIAssistantType) -> ConfigurationStatus {
        let detection = checkAssistant(type)
        switch detection {
        case .notDetected, .error:
            return detection
        case .detected, .configured:
            return isHookInstalled(type) ? .configured : .detected
        }
    }
    
    // Check if assistant is installed
    func checkAssistant(_ type: AIAssistantType) -> ConfigurationStatus {
        return executablePath(for: type.executableName) == nil ? .notDetected : .detected
    }
    
    // Configure assistant hooks
    func configureAssistant(_ type: AIAssistantType) -> ConfigurationStatus {
        // 已配置则不再覆盖（策略 B）；Claude 另需同步 AskUserQuestion 桥接（可重复调用、幂等）
        if isHookInstalled(type) {
            if type == .claudeCode {
                installClaudeAskUserQuestionBridgeIfNeeded()
            }
            return .configured
        }
        
        // Check if assistant is installed
        let detectionStatus = checkAssistant(type)
        if case .notDetected = detectionStatus {
            return .notDetected
        }
        
        // Create hooks directory if it doesn't exist
        let expandedPath = (type.hookPath as NSString).expandingTildeInPath
        let fileManager = FileManager.default
        
        do {
            if !fileManager.fileExists(atPath: expandedPath) {
                try fileManager.createDirectory(atPath: expandedPath, withIntermediateDirectories: true)
            }
            
            // Create hook file
            let hookFile = "\(expandedPath)/ai_land_hook.sh"
            // 注意：从 CLI 触发时可能带空格参数，这里先只保证 assistant 回调可靠。
            // args 作为可选信息，若包含空格可能导致 URL 不合法，因此暂不拼接。
            let hookContent = "#!/bin/bash\n# Ai-land Hook for \(type.rawValue)\n\nopen -g \"ai-land://hook?assistant=\(type.executableName)\"\n"
            
            try hookContent.write(toFile: hookFile, atomically: true, encoding: String.Encoding.utf8)
            
            // Make hook executable
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookFile)
            
            if type == .claudeCode {
                installClaudeAskUserQuestionBridgeIfNeeded()
            }
            return .configured
        } catch {
            return .error(error.localizedDescription)
        }
    }
    
    /// 安装 `AskUserQuestion` → 灵动岛 的 Python 钩子，并把 `PreToolUse` 条目合并进 `~/.claude/settings.json`（若存在 `settings.local.json` 则优先改它，规避与 `permissions` 同文件的加载问题）。
    func installClaudeAskUserQuestionBridgeIfNeeded() {
        let fm = FileManager.default
        let hooksDir = (AIAssistantType.claudeCode.hookPath as NSString).expandingTildeInPath
        let pyPath = claudeAskUserQuestionHookPath()
        do {
            if !fm.fileExists(atPath: hooksDir) {
                try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
            }
            try AiLandEmbeddedScripts.claudeAskUserQuestionHookPython.write(toFile: pyPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pyPath)
        } catch {
            ConfigLog.logger.error("write ask hook py failed: \(String(describing: error), privacy: .public)")
            return
        }
        mergeClaudePreToolUseAskUserQuestionEntry(commandPath: pyPath)
        installClaudeTaskLifecycleHookIfNeeded()
    }
    
    /// 任务进度 → `ai-land://task`：仅 UserPromptSubmit 标运行中；Stop / StopFailure / PostToolUseFailure(中断) / SessionEnd 收尾。不再挂 SessionStart（避免刚进 CLI 未提问就「进行中」）。
    func installClaudeTaskLifecycleHookIfNeeded() {
        let fm = FileManager.default
        let hooksDir = (AIAssistantType.claudeCode.hookPath as NSString).expandingTildeInPath
        let pyPath = (hooksDir as NSString).appendingPathComponent("ai_land_task_lifecycle_hook.py")
        do {
            if !fm.fileExists(atPath: hooksDir) {
                try fm.createDirectory(atPath: hooksDir, withIntermediateDirectories: true)
            }
            try AiLandEmbeddedScripts.claudeTaskLifecycleHookPython.write(toFile: pyPath, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pyPath)
        } catch {
            ConfigLog.logger.error("write task lifecycle hook py failed: \(String(describing: error), privacy: .public)")
            return
        }
        mergeClaudeTaskLifecycleHookEntry(commandPath: pyPath)
    }
    
    private func claudeSettingsFileURL() -> URL {
        let claude = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent(".claude", isDirectory: true)
        let local = claude.appendingPathComponent("settings.local.json")
        let regular = claude.appendingPathComponent("settings.json")
        if fm.fileExists(atPath: local.path) { return local }
        return regular
    }
    
    private var fm: FileManager { FileManager.default }
    
    private func mergeClaudePreToolUseAskUserQuestionEntry(commandPath: String) {
        let settingsURL = claudeSettingsFileURL()
        let marker = "ai_land_ask_user_question_hook.py"
        let legacyAskMarker = "code_island_ask_user_question_hook.py"
        
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        var preGroups = hooks["PreToolUse"] as? [[String: Any]] ?? []
        
        if preToolUseGroups(preGroups, containsCommandSubstring: marker)
            || preToolUseGroups(preGroups, containsCommandSubstring: legacyAskMarker) {
            ConfigLog.logger.debug("Claude PreToolUse already has Ai-land AskUserQuestion hook")
            return
        }
        
        let newGroup: [String: Any] = [
            "matcher": "AskUserQuestion",
            "hooks": [
                [
                    "type": "command",
                    "command": commandPath
                ] as [String: Any]
            ]
        ]
        preGroups.append(newGroup)
        hooks["PreToolUse"] = preGroups
        root["hooks"] = hooks
        
        do {
            let claudeDir = settingsURL.deletingLastPathComponent()
            try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsURL, options: .atomic)
            ConfigLog.logger.info("merged AskUserQuestion PreToolUse into \(settingsURL.lastPathComponent, privacy: .public)")
        } catch {
            ConfigLog.logger.error("merge Claude settings failed: \(String(describing: error), privacy: .public). 请手动在 hooks.PreToolUse 中加入 matcher AskUserQuestion → \(commandPath, privacy: .public)")
        }
    }
    
    private func preToolUseGroups(_ groups: [[String: Any]], containsCommandSubstring needle: String) -> Bool {
        for g in groups {
            let inner = g["hooks"] as? [[String: Any]] ?? []
            for h in inner {
                if let cmd = h["command"] as? String, cmd.contains(needle) { return true }
            }
        }
        return false
    }
    
    private func mergeClaudeTaskLifecycleHookEntry(commandPath: String) {
        let settingsURL = claudeSettingsFileURL()
        let marker = "ai_land_task_lifecycle_hook.py"
        let legacyLifecycleMarker = "code_island_task_lifecycle_hook.py"
        
        var root: [String: Any] = [:]
        if fm.fileExists(atPath: settingsURL.path),
           let data = try? Data(contentsOf: settingsURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = obj
        }
        
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let group: [String: Any] = [
            "hooks": [
                [
                    "type": "command",
                    "command": commandPath
                ] as [String: Any]
            ]
        ]
        
        // Stop = 正常结束本轮；StopFailure = API/回合异常结束（用户取消时 Stop 常不触发）；PostToolUseFailure+is_interrupt = 工具执行中被中断。
        // UserPromptSubmit = 提交提示后标运行中。不挂 SessionStart。
        for key in ["SessionEnd", "Stop", "UserPromptSubmit", "StopFailure", "PostToolUseFailure"] {
            var arr = hooks[key] as? [[String: Any]] ?? []
            if preToolUseGroups(arr, containsCommandSubstring: marker)
                || preToolUseGroups(arr, containsCommandSubstring: legacyLifecycleMarker) {
                ConfigLog.logger.debug("Claude \(key) already has Ai-land task lifecycle hook")
                continue
            }
            arr.append(group)
            hooks[key] = arr
        }
        root["hooks"] = hooks
        
        do {
            let claudeDir = settingsURL.deletingLastPathComponent()
            try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try out.write(to: settingsURL, options: .atomic)
            ConfigLog.logger.info("merged task lifecycle hooks into \(settingsURL.lastPathComponent, privacy: .public)")
        } catch {
            ConfigLog.logger.error("merge Claude task lifecycle hooks failed: \(String(describing: error), privacy: .public)")
        }
    }
    
    // Auto-configure all assistants
    func autoConfigureAll() -> [AIAssistantType: ConfigurationStatus] {
        var results: [AIAssistantType: ConfigurationStatus] = [:]
        
        for assistant in AIAssistantType.allCases {
            results[assistant] = configureAssistant(assistant)
        }
        
        return results
    }
    
    // Get configuration status for all assistants
    func getStatusForAll() -> [AIAssistantType: ConfigurationStatus] {
        var results: [AIAssistantType: ConfigurationStatus] = [:]
        
        for assistant in AIAssistantType.allCases {
            results[assistant] = configurationStatus(for: assistant)
        }
        
        return results
    }
    
    /// 从 UI 一键安装/更新 Ai-land 钩子：`ai_land_hook.sh`；Claude Code 另幂等同步 AskUserQuestion、任务生命周期 Python 与 `settings` 合并项。
    func quickConfigureHooks(for type: AIAssistantType) -> (success: Bool, message: String) {
        switch checkAssistant(type) {
        case .notDetected:
            return (false, L10n.fmt("hook_err_not_in_path", type.executableName))
        case .error(let msg):
            return (false, msg)
        case .detected, .configured:
            break
        }
        
        let hadHook = isHookInstalled(type)
        let status = configureAssistant(type)
        
        switch status {
        case .configured:
            let path = hookFilePath(for: type)
            if type == .claudeCode {
                if hadHook {
                    return (true, L10n.fmt("hook_claude_resync", path))
                }
                return (true, L10n.fmt("hook_claude_new", path))
            }
            if hadHook {
                return (true, L10n.fmt("hook_exists_format", type.rawValue, path))
            }
            return (true, L10n.fmt("hook_installed_format", type.rawValue, path))
        case .notDetected:
            return (false, L10n.str("hook_err_no_cli"))
        case .error(let msg):
            return (false, L10n.fmt("hook_err_install_failed", msg))
        case .detected:
            return (false, L10n.fmt("hook_err_incomplete", type.hookPath))
        }
    }
}

// MARK: - Embedded Claude hook (AskUserQuestion → 灵动岛)

private enum AiLandEmbeddedScripts {
    /// 任务进度：UserPromptSubmit→运行中；Stop→本轮结束；StopFailure / 工具中断→结束；SessionEnd→静默完成。SessionStart 不回调。
    static let claudeTaskLifecycleHookPython = #"""
#!/usr/bin/env python3
# Ai-land — Claude Code 钩子 → 灵动岛任务（按 session_id）
import json, os, sys, uuid, urllib.parse, subprocess

def open_task_url(params):
    clean = {k: v for k, v in params.items() if v not in (None, "")}
    q = urllib.parse.urlencode(clean, quote_via=urllib.parse.quote)
    subprocess.run(["open", "-g", "ai-land://task?" + q], check=False)

def session_key(data):
    s = (data.get("session_id") or "").strip()
    return s if s else str(uuid.uuid4())

def human_title(data):
    cwd = (data.get("cwd") or "").strip()
    sid = (data.get("session_id") or "").strip()
    proj = os.path.basename(cwd) if cwd else "Claude Code"
    if sid:
        suf = (sid[:12] + "…") if len(sid) > 14 else sid
        return proj + " · 会话 " + suf
    return proj

def host_context_params():
    """从钩子进程环境推断宿主终端 / 集成终端，便于 App 在多标签、多 Cursor 窗口时聚焦正确表面。"""
    p = {}
    sid = (os.environ.get("ITERM_SESSION_ID") or "").strip()
    if sid:
        p["iterm_sid"] = sid
    tty = (os.environ.get("TTY") or "").strip()
    if not tty:
        for fd in (2, 1, 0):
            try:
                t = os.ttyname(fd)
                if t:
                    tty = t
                    break
            except OSError:
                pass
    if tty:
        p["host_tty"] = tty
    try:
        ppid = os.getppid()
        if ppid and ppid > 1:
            p["host_ppid"] = str(ppid)
    except Exception:
        pass
    tp = (os.environ.get("TERM_PROGRAM") or os.environ.get("LC_TERMINAL") or "").strip()
    if tp:
        p["term_program"] = tp
    return p

def clip_text(s, n):
    s = (s or "").strip()
    if len(s) > n:
        return s[:n] + "…"
    return s

def assistant_reply_text(data):
    """Stop / SubagentStop：官方字段 last_assistant_message。"""
    for key in ("last_assistant_message", "last_message", "assistant_message"):
        v = (data.get(key) or "").strip()
        if v:
            return v
    return ""

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    ev = (data.get("hook_event_name") or "").replace("_", "").lower()
    cwd = (data.get("cwd") or "").strip()
    tid = session_key(data)
    title = human_title(data)
    base = {"assistant": "claude", "task_id": tid, "title": title, "surface": "claude-code", "cwd": cwd}
    base.update(host_context_params())
    if cwd:
        bn = os.path.basename(cwd.rstrip("/")) or ""
        if bn:
            base["project_name"] = bn

    if ev == "userpromptsubmit":
        p = dict(base)
        p["state"] = "running"
        p["detail"] = "等待模型输出…"
        p["generating"] = "1"
        up = (data.get("prompt") or "").strip()
        if up:
            p["chat_r0"] = clip_text(up, 800)
        open_task_url(p)
        return 0
    if ev == "stop":
        p = dict(base)
        p["state"] = "completed"
        p["ok"] = "1"
        reply = assistant_reply_text(data)
        if reply:
            p["chat_r0"] = clip_text(reply, 800)
            p["detail"] = clip_text(reply, 240)
        else:
            p["detail"] = "本轮输出已结束"
        open_task_url(p)
        return 0
    if ev == "stopfailure":
        # 文档：用户中断时 Stop 往往不触发；回合因 API 错误结束时走 StopFailure。
        p = dict(base)
        p["state"] = "completed"
        p["ok"] = "0"
        msg = (data.get("last_assistant_message") or "").strip()
        if not msg:
            msg = str(data.get("error") or "").strip() or "回合异常结束"
        p["chat_r0"] = clip_text(msg, 800)
        p["detail"] = clip_text(msg, 240)
        open_task_url(p)
        return 0
    if ev == "posttoolusefailure":
        if not data.get("is_interrupt"):
            return 0
        p = dict(base)
        p["state"] = "completed"
        p["ok"] = "0"
        p["detail"] = "工具执行被用户中断"
        open_task_url(p)
        return 0
    if ev == "sessionstart":
        # 进入 CLI / 新开会话时不要标 running，否则未发起对话也会一直「进行中」
        return 0
    if ev == "sessionend":
        p = dict(base)
        p["state"] = "completed"
        p["ok"] = "1"
        p["silent"] = "1"
        reason = (data.get("reason") or "").strip()
        if reason:
            p["detail"] = "会话结束: " + reason
        else:
            p["detail"] = "会话已退出"
        open_task_url(p)
        return 0
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"""#

    /// 由 `installClaudeAskUserQuestionBridgeIfNeeded()` 写入 `~/.claude/hooks/`；勿在字符串内使用 `"""`，以免截断 Swift 原始字符串。
    static let claudeAskUserQuestionHookPython = #"""
#!/usr/bin/env python3
# Ai-land — Claude Code AskUserQuestion → 灵动岛；阻塞直到 App 内点选或关闭卡片。
import json, os, sys, time, uuid, urllib.parse, subprocess

# 默认不调用 osascript / System Events，避免 macOS「自动化」权限弹窗。
# 若需要「独立终端在前台时跳过钩子」，请显式开启（会触发系统权限提示）：
#   export AI_LAND_HOOK_CHECK_FRONTMOST=1
# 可选配合：
#   AI_LAND_HOOK_SKIP_WHEN_IDE_FRONTMOST=1
#   AI_LAND_HOOK_SKIP_BUNDLES=com.apple.Terminal,com.foo.bar

DEFAULT_TERMINAL_SKIP_BUNDLES = frozenset({
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "dev.warp.Warp",
    "com.mitchellh.ghostty",
    "org.alacritty.Alacritty",
    "net.kovidgoyal.kitty",
})

IDE_SKIP_BUNDLES = frozenset({"com.microsoft.VSCode"})

def eprint(*a, **k):
    k.setdefault("file", sys.stderr)
    k.setdefault("flush", True)
    print(*a, **k)

def mirror_options_to_terminal(title, prompt, options):
    # PreToolUse 阻塞时原生 AskUserQuestion TUI 不会出现，须把选项打到终端避免「空白等待」
    bar = "─" * 58
    eprint("")
    eprint(bar)
    eprint("Ai-land · 工具权限：灵动岛已展开时点「允许」或「拒绝」，无需离开编辑器；亦可点 ✕ 拒绝，或在此终端用 ↑/↓ 选择。")
    eprint(bar)
    if title:
        eprint("【" + str(title) + "】")
    eprint(str(prompt))
    eprint("")
    for i, opt in enumerate(options, start=1):
        eprint("  {:>2}. {}".format(i, opt))
    eprint("")
    eprint("等待灵动岛或终端…")
    eprint(bar)
    eprint("")

def frontmost_bundle_id():
    script = 'tell application "System Events" to get bundle identifier of first process whose frontmost is true'
    try:
        out = subprocess.check_output(["osascript", "-e", script], text=True, stderr=subprocess.DEVNULL, timeout=6)
        return (out or "").strip()
    except Exception:
        return ""

def extra_skip_bundles():
    raw = os.environ.get("AI_LAND_HOOK_SKIP_BUNDLES", "")
    if not raw.strip():
        return frozenset()
    return frozenset(x.strip() for x in raw.split(",") if x.strip())

def is_cursor_bundle(bid):
    return bid.startswith("com.todesktop.")

def should_skip_hook_for_frontmost(bid):
    if not bid:
        return False
    if bid in (DEFAULT_TERMINAL_SKIP_BUNDLES | extra_skip_bundles()):
        return True
    flag = os.environ.get("AI_LAND_HOOK_SKIP_WHEN_IDE_FRONTMOST", "").strip().lower()
    if flag in ("1", "true", "yes", "on"):
        if bid in IDE_SKIP_BUNDLES or is_cursor_bundle(bid):
            return True
    return False

def env_truthy(name):
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes", "on")

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("hook_event_name") != "PreToolUse":
        return 0
    if data.get("tool_name") != "AskUserQuestion":
        return 0
    inp = data.get("tool_input") or {}
    questions = inp.get("questions") or []
    if not questions:
        return 0
    q0 = questions[0]
    options = []
    for o in q0.get("options") or []:
        lab = (o.get("label") or "").strip()
        if lab:
            options.append(lab)
    if not options:
        return 0
    if env_truthy("AI_LAND_HOOK_CHECK_FRONTMOST"):
        bid = frontmost_bundle_id()
        if should_skip_hook_for_frontmost(bid):
            eprint("")
            eprint("─" * 58)
            eprint("Ai-land：当前前台为终端/IDE（bundle: " + bid + "），跳过灵动岛钩子。")
            eprint("将使用 Claude 原生选择界面（↑/↓ · Enter）。")
            eprint("─" * 58)
            eprint("")
            return 0
    req_id = str(data.get("tool_use_id") or uuid.uuid4())
    title = (q0.get("header") or "").strip() or "选择"
    prompt = (q0.get("question") or "").strip() or "请选择一个选项"
    home = os.path.expanduser("~")
    inbox = os.path.join(home, ".ai-land", "interact-inbox")
    os.makedirs(inbox, exist_ok=True)
    payload = {"agent": "claude", "id": req_id, "title": title, "prompt": prompt, "options": options}
    with open(os.path.join(inbox, req_id + ".json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    q_title = urllib.parse.quote(title, safe="")
    q_prompt = urllib.parse.quote(prompt, safe="")
    q_opts = urllib.parse.quote("|".join(options), safe="")
    rid_q = urllib.parse.quote(req_id, safe="")
    open_url = "ai-land://interact?agent=claude&id=" + rid_q + "&title=" + q_title + "&prompt=" + q_prompt + "&options=" + q_opts
    subprocess.run(["open", "-g", open_url], check=False)
    mirror_options_to_terminal(title, prompt, options)
    out_dir = os.path.join(home, ".ai-land", "interactions")
    os.makedirs(out_dir, exist_ok=True)
    result_path = os.path.join(out_dir, req_id + ".json")
    deadline = time.time() + 900.0
    while time.time() < deadline:
        if os.path.exists(result_path):
            try:
                with open(result_path, encoding="utf-8") as f:
                    r = json.load(f)
                if r.get("cancelled"):
                    try:
                        os.remove(result_path)
                    except OSError:
                        pass
                    # 必须向 stdout 输出 deny，否则 PreToolUse 无有效决策，CLI 会一直阻塞或行为未定义
                    deny_out = {
                        "hookSpecificOutput": {
                            "hookEventName": "PreToolUse",
                            "permissionDecision": "deny",
                            "permissionDecisionReason": "用户在 Ai-land 灵动岛取消了询问",
                        }
                    }
                    print(json.dumps(deny_out, ensure_ascii=False), flush=True)
                    return 0
                choice = r.get("choice")
                if isinstance(choice, str) and choice.strip():
                    qtext = (q0.get("question") or "").strip()
                    updated = dict(inp)
                    updated["questions"] = questions
                    updated["answers"] = {qtext: choice.strip()}
                    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "updatedInput": updated}}
                    print(json.dumps(out, ensure_ascii=False), flush=True)
                    try:
                        os.remove(result_path)
                    except OSError:
                        pass
                    return 0
            except (json.JSONDecodeError, OSError):
                pass
        time.sleep(0.15)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
"""#
}
