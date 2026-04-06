//
//  TaskActivityManager.swift
//  Ai_land
//
//  CLI / 钩子通过 ai-land://task 上报「运行中」「已完成」（兼容 code-island）。
//  支持六款编码代理：Claude Code、OpenAI Codex CLI、Google Gemini CLI、Cursor Agent、OpenCode、Factory Droid（assistant 参数为各 CLI 可执行名，如 claude / codex / gemini）。
//

import Foundation
import Combine
import UserNotifications
import os.log

extension Notification.Name {
    /// 用户在岛上对 `waiting_confirm` 任务按下 Y/N。userInfo: `taskId` String, `approved` Bool
    static let aiLandTaskUserConfirmation = Notification.Name("aiLandTaskUserConfirmation")
}

private enum TaskActivityLog {
    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "xiaoo.ai-land", category: "taskActivity")
}

/// 钩子从环境附加的宿主信息，用于在多 iTerm 标签、多 Cursor 窗口时聚焦正确目标。
struct CLITaskWindowHints: Equatable {
    var itermSessionID: String?
    var hostTTY: String?
    var hostParentPID: Int32?
    var termProgram: String?
    
    var hasUsableSignal: Bool {
        if let s = itermSessionID, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if let t = hostTTY, !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if hostParentPID != nil { return true }
        if let tp = termProgram, !tp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return false
    }
    
    mutating func mergeFromURLQuery(
        itermSid: String?,
        hostTTY: String?,
        hostPpidString: String?,
        termProgram: String?
    ) {
        if let s = itermSid?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil {
            itermSessionID = s
        }
        if let t = hostTTY?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil {
            self.hostTTY = t
        }
        if let raw = hostPpidString?.trimmingCharacters(in: .whitespacesAndNewlines), let v = Int32(raw), v > 1 {
            hostParentPID = v
        }
        if let tp = termProgram?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil {
            self.termProgram = tp
        }
    }
}

/// 单次 CLI / 会话任务（Claude Code 等终端会话用 session_id 作 id，非 Claude 桌面 App）
struct AgentCLITask: Identifiable, Equatable {
    enum Phase: Equatable {
        case running
        /// 钩子 `state=waiting_confirm`：等待用户在终端/岛上确认
        case waitingConfirm
        case completed(success: Bool)
    }
    
    let id: String
    let assistantExecutable: String
    var title: String
    var phase: Phase
    let startedAt: Date
    var completedAt: Date?
    var detail: String?
    /// 钩子 JSON 里的 cwd，标识具体工程目录
    var workspacePath: String?
    /// 用于 Hash-Color 的稳定路径（`abs_path` 查询参数，缺省同 cwd）
    var identityPath: String
    /// 展示用项目名（`project_name`）；缺省由路径推导
    var projectName: String?
    /// 悬停 Popover：最近至多 3 轮文本（`chat_r0`…`chat_r2` 或 `chat_preview` 以 `|||` 分隔）
    var chatPreviewTurns: [String]
    /// Git 分支（`branch` / `git_branch`）
    var branchName: String? = nil
    /// 0…100：头像外圈进度；`nil` 为不确定进度（旋转扫弧）
    var progressPercent: Int? = nil
    /// 流式生成中（`generating` / `streaming`），对话预览旁显示闪烁省略号
    var isGenerating: Bool = false
    /// 例如 claude-code，用于区分「终端里的 Code」与别的入口
    var surface: String?
    /// 钩子 `host_context_params()`：`iterm_sid` / `host_tty` / `host_ppid` / `term_program`
    var windowHints: CLITaskWindowHints = CLITaskWindowHints()
    
    var statusLabel: String {
        switch phase {
        case .running: return L10n.str("status_running")
        case .waitingConfirm: return L10n.str("status_waiting_confirm")
        case .completed(let ok):
            return ok ? L10n.str("status_completed") : L10n.str("status_completed_fail")
        }
    }
    
    var assistantDisplayName: String {
        if surface == "claude-code" {
            return L10n.str("assist_claude_code_terminal")
        }
        if let t = AIAssistantType.allCases.first(where: { $0.executableName == assistantExecutable }) {
            return t.rawValue
        }
        return assistantExecutable
    }
}

/// 收起/展开态顶部小条：提示刚结束的 CLI 任务，点击后跳转列表
struct CLITaskCompletionToast: Equatable {
    let taskId: String
    let title: String
    let assistantLabel: String
    let success: Bool
    /// 来自 `chat_r0…` / `detail` 的短摘要，供完成条展示
    let dialogSnippet: String
}

@MainActor
final class TaskActivityManager: ObservableObject {
    static let shared = TaskActivityManager()
    
    /// 最新在前；保留最近条数上限
    @Published private(set) var tasks: [AgentCLITask] = []
    
    /// 收起态图标「完成」高亮截止时间；到期后由定时任务置 nil。
    @Published private(set) var compactCompletedGlowDeadline: Date?
    
    /// 任务刚完成时的应用内小窗提示（与系统通知独立；`silent=1` 时仍显示，便于在岛上查看）
    @Published private(set) var completionToast: CLITaskCompletionToast?
    
    private let maxTasks = 40
    private var legacyCompleteWorkItems: [String: DispatchWorkItem] = [:]
    private var compactGlowResetWorkItem: DispatchWorkItem?
    private var toastDismissWorkItem: DispatchWorkItem?
    private var notificationDelegate = TaskNotificationDelegate()
    
    private init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        requestNotificationAuthorizationIfNeeded()
    }
    
    /// `ai-land://task?assistant=claude&state=running|completed&task_id=…&title=…&ok=1`（兼容 code-island）
    func handleTaskURL(_ url: URL) {
        guard AiLandURLRouting.isAppURLScheme(url.scheme) else { return }
        guard url.host?.lowercased() == "task" else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        func val(_ name: String) -> String? {
            items.first { $0.name.lowercased() == name }?.value
        }
        guard let assistantRaw = val("assistant"),
              let assistantClamped = AiLandURLRouting.clampField(assistantRaw, maxChars: AiLandPayloadLimits.assistant),
              !assistantClamped.isEmpty else { return }
        let assistant = AIAssistantType.canonicalExecutable(from: assistantClamped)
        let state = (val("state") ?? "").lowercased()
        let taskId = {
            let raw = val("task_id")?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmptyOrNil
            let base = raw ?? UUID().uuidString
            return AiLandURLRouting.clampField(base, maxChars: AiLandPayloadLimits.taskId) ?? base
        }()
        let title: String = {
            let t = val("title").map { $0.removingPercentEncoding ?? $0 } ?? "CLI 任务"
            return AiLandURLRouting.clampField(t, maxChars: AiLandPayloadLimits.title) ?? "CLI 任务"
        }()
        let ok = truthy(val("ok") ?? val("success"))
        let suppressNotification = truthy(val("silent"))
        let cwdDecoded = val("cwd").map { $0.removingPercentEncoding ?? $0 }
            .flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.cwd) }
        let detailDecoded = val("detail").map { $0.removingPercentEncoding ?? $0 }
            .flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.detail) }
        let surface = val("surface").flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.surface) }
        let itermSidDecoded = val("iterm_sid").map { $0.removingPercentEncoding ?? $0 }.flatMap { AiLandURLRouting.clampField($0, maxChars: 512) }
        let hostTTYDecoded = val("host_tty").map { $0.removingPercentEncoding ?? $0 }.flatMap { AiLandURLRouting.clampField($0, maxChars: 512) }
        let hostPpidDecoded = val("host_ppid").map { $0.removingPercentEncoding ?? $0 }.flatMap { AiLandURLRouting.clampField($0, maxChars: 32) }
        let termProgDecoded = val("term_program").map { $0.removingPercentEncoding ?? $0 }.flatMap { AiLandURLRouting.clampField($0, maxChars: 256) }
        let absDecoded = val("abs_path").map { $0.removingPercentEncoding ?? $0 }
            .flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.cwd) }
        let projectNameDecoded = val("project_name").map { $0.removingPercentEncoding ?? $0 }
            .flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.projectName) }
        let chatTurnsDecoded = Self.chatPreviewTurns(from: val)
        let branchRaw = val("branch") ?? val("git_branch")
        let branchKeyPresent = branchRaw != nil
        let branchDecoded = branchRaw.map { $0.removingPercentEncoding ?? $0 }
            .flatMap { AiLandURLRouting.clampField($0.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.branch) }
        let progressRaw = val("progress")
        let progressKeyPresent = progressRaw != nil
        let progressParsed: Int? = progressRaw.flatMap { r in
            let t = r.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let p = Int(t) else { return nil }
            return min(100, max(0, p))
        }
        let generating = explicitOnFlag(val("generating")) || explicitOnFlag(val("streaming"))
        var hintMerge = CLITaskWindowHints()
        hintMerge.mergeFromURLQuery(
            itermSid: itermSidDecoded,
            hostTTY: hostTTYDecoded,
            hostPpidString: hostPpidDecoded,
            termProgram: termProgDecoded
        )
        
        TaskActivityLog.logger.info("task URL assistant=\(assistant, privacy: .public) state=\(state, privacy: .public) id=\(taskId, privacy: .public)")
        
        switch state {
        case "running", "start", "1":
            upsertActive(
                taskId: taskId,
                assistant: assistant,
                title: title,
                phase: .running,
                workspacePath: cwdDecoded,
                absPath: absDecoded,
                projectName: projectNameDecoded,
                chatTurns: chatTurnsDecoded,
                detail: detailDecoded,
                surface: surface,
                hintPatch: hintMerge,
                branchKeyPresent: branchKeyPresent,
                branch: branchDecoded,
                progressKeyPresent: progressKeyPresent,
                progress: progressParsed,
                isGenerating: generating
            )
        case "waiting_confirm", "waiting-confirm", "confirm_wait", "pending_confirm":
            upsertActive(
                taskId: taskId,
                assistant: assistant,
                title: title,
                phase: .waitingConfirm,
                workspacePath: cwdDecoded,
                absPath: absDecoded,
                projectName: projectNameDecoded,
                chatTurns: chatTurnsDecoded,
                detail: detailDecoded,
                surface: surface,
                hintPatch: hintMerge,
                branchKeyPresent: branchKeyPresent,
                branch: branchDecoded,
                progressKeyPresent: progressKeyPresent,
                progress: progressParsed,
                isGenerating: generating
            )
        case "completed", "done", "finish", "end", "stopped":
            complete(
                taskId: taskId,
                assistant: assistant,
                title: title,
                success: ok,
                workspacePath: cwdDecoded,
                absPath: absDecoded,
                projectName: projectNameDecoded,
                chatTurns: chatTurnsDecoded,
                detail: detailDecoded,
                surface: surface,
                hintPatch: hintMerge,
                notify: !suppressNotification,
                branchKeyPresent: branchKeyPresent,
                branch: branchDecoded,
                progressKeyPresent: progressKeyPresent,
                progress: progressParsed,
                isGenerating: generating
            )
        case "failed", "error":
            complete(
                taskId: taskId,
                assistant: assistant,
                title: title,
                success: false,
                workspacePath: cwdDecoded,
                absPath: absDecoded,
                projectName: projectNameDecoded,
                chatTurns: chatTurnsDecoded,
                detail: detailDecoded,
                surface: surface,
                hintPatch: hintMerge,
                notify: !suppressNotification,
                branchKeyPresent: branchKeyPresent,
                branch: branchDecoded,
                progressKeyPresent: progressKeyPresent,
                progress: progressParsed,
                isGenerating: generating
            )
        default:
            TaskActivityLog.logger.debug("task URL ignored unknown state=\(state, privacy: .public)")
        }
    }
    
    /// 兼容旧版 hook URL（`code-island` / `ai-land`）：视为活动脉冲，长时间无新脉冲则自动标记完成。
    func recordLegacyHook(assistant: AIAssistantType) {
        let key = assistant.executableName
        legacyCompleteWorkItems[key]?.cancel()
        let taskId = "legacy-\(key)"
        upsertActive(
            taskId: taskId,
            assistant: key,
            title: "CLI 活动",
            phase: .running,
            workspacePath: nil,
            absPath: nil,
            projectName: nil,
            chatTurns: [],
            detail: nil,
            surface: nil,
            hintPatch: CLITaskWindowHints(),
            branchKeyPresent: false,
            branch: nil,
            progressKeyPresent: false,
            progress: nil,
            isGenerating: false
        )
        
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.complete(
                    taskId: taskId,
                    assistant: key,
                    title: "CLI 活动",
                    success: true,
                    workspacePath: nil,
                    absPath: nil,
                    projectName: nil,
                    chatTurns: [],
                    detail: "未收到明确结束信号，已自动收尾",
                    surface: nil,
                    hintPatch: CLITaskWindowHints(),
                    notify: true,
                    branchKeyPresent: false,
                    branch: nil,
                    progressKeyPresent: false,
                    progress: nil,
                    isGenerating: false
                )
                self.legacyCompleteWorkItems[key] = nil
            }
        }
        legacyCompleteWorkItems[key] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: work)
    }
    
    /// 仍占用「会话槽位」的任务：运行中或待终端/用户确认。
    var runningTasks: [AgentCLITask] {
        tasks.filter {
            switch $0.phase {
            case .running, .waitingConfirm: return true
            default: return false
            }
        }
    }
    
    /// 恰好一条 `waiting_confirm` 时供界面注册全局 Y/N 快捷键（多会话时以列表行内按钮为主）。
    var singleWaitingConfirmTaskId: String? {
        let ids = tasks.compactMap { t -> String? in
            if case .waitingConfirm = t.phase { return t.id }
            return nil
        }
        return ids.count == 1 ? ids[0] : nil
    }
    
    /// 用户在岛上确认/拒绝；终端钩子可订阅 `Notification.Name.aiLandTaskUserConfirmation`。
    func submitTaskUserConfirmation(taskId: String, approved: Bool) {
        NotificationCenter.default.post(
            name: .aiLandTaskUserConfirmation,
            object: nil,
            userInfo: ["taskId": taskId, "approved": approved]
        )
        if let idx = tasks.firstIndex(where: { $0.id == taskId }), case .waitingConfirm = tasks[idx].phase {
            tasks[idx].phase = .running
        }
    }
    
    func clearCompleted() {
        tasks.removeAll { if case .completed = $0.phase { return true }; return false }
    }
    
    /// 清空任务列表（仅本地 UI）；并取消遗留 hook 自动收尾定时器，避免空列表后又被写回。
    func clearAllCliTasks() {
        for (_, work) in legacyCompleteWorkItems { work.cancel() }
        legacyCompleteWorkItems.removeAll()
        tasks.removeAll()
        dismissCompletionToast()
    }
    
    /// 从列表移除一条记录（仅本地 UI，不结束远端 CLI 会话）。
    func removeCliTask(id: String) {
        tasks.removeAll { $0.id == id }
        if completionToast?.taskId == id {
            dismissCompletionToast()
        }
    }
    
    func dismissCompletionToast() {
        toastDismissWorkItem?.cancel()
        toastDismissWorkItem = nil
        completionToast = nil
    }
    
    /// 用户本地重命名列表展示标题；不影响钩子再次上报的 `title`（后续 URL 仍会覆盖）。
    func renameCliTask(id: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let idx = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[idx].title = t
    }
    
    // MARK: - Private
    
    private func explicitOnFlag(_ raw: String?) -> Bool {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return false }
        return ["1", "true", "yes", "ok", "on"].contains(s)
    }
    
    private func applyPresentationFields(
        at idx: Int,
        branchKeyPresent: Bool,
        branch: String?,
        progressKeyPresent: Bool,
        progress: Int?,
        isGenerating: Bool
    ) {
        if branchKeyPresent {
            tasks[idx].branchName = branch.flatMap { $0.isEmpty ? nil : $0 }
        }
        if progressKeyPresent {
            tasks[idx].progressPercent = progress
        }
        tasks[idx].isGenerating = isGenerating
    }
    
    private func mergeWindowHints(into idx: Int, patch: CLITaskWindowHints) {
        guard patch.hasUsableSignal else { return }
        if let s = patch.itermSessionID { tasks[idx].windowHints.itermSessionID = s }
        if let t = patch.hostTTY { tasks[idx].windowHints.hostTTY = t }
        if let p = patch.hostParentPID { tasks[idx].windowHints.hostParentPID = p }
        if let tp = patch.termProgram { tasks[idx].windowHints.termProgram = tp }
    }
    
    private static func chatPreviewTurns(from val: (String) -> String?) -> [String] {
        var list: [String] = []
        for key in ["chat_r0", "chat_r1", "chat_r2"] {
            guard let raw = val(key) else { continue }
            let decoded = raw.removingPercentEncoding ?? raw
            let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let clamped = AiLandURLRouting.clampField(trimmed, maxChars: AiLandPayloadLimits.chatTurn), !clamped.isEmpty else { continue }
            list.append(clamped)
        }
        if list.isEmpty, let blob = val("chat_preview") {
            let decoded = blob.removingPercentEncoding ?? blob
            let clamped = AiLandURLRouting.clampField(decoded.trimmingCharacters(in: .whitespacesAndNewlines), maxChars: AiLandPayloadLimits.chatPreviewBlob) ?? decoded
            let parts = clamped.components(separatedBy: "|||").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            list = Array(parts.prefix(3))
        }
        return Array(list.prefix(3))
    }
    
    private func upsertActive(
        taskId: String,
        assistant: String,
        title: String,
        phase: AgentCLITask.Phase,
        workspacePath: String?,
        absPath: String?,
        projectName: String?,
        chatTurns: [String],
        detail: String?,
        surface: String?,
        hintPatch: CLITaskWindowHints,
        branchKeyPresent: Bool,
        branch: String?,
        progressKeyPresent: Bool,
        progress: Int?,
        isGenerating: Bool
    ) {
        let now = Date()
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            tasks[idx].title = title
            tasks[idx].phase = phase
            tasks[idx].completedAt = nil
            if let detail, !detail.isEmpty { tasks[idx].detail = detail }
            if let workspacePath, !workspacePath.isEmpty { tasks[idx].workspacePath = workspacePath }
            if let surface, !surface.isEmpty { tasks[idx].surface = surface }
            if let projectName, !projectName.isEmpty { tasks[idx].projectName = projectName }
            if !chatTurns.isEmpty { tasks[idx].chatPreviewTurns = chatTurns }
            applyIdentityPath(at: idx, absPath: absPath, workspacePath: workspacePath)
            applyPresentationFields(
                at: idx,
                branchKeyPresent: branchKeyPresent,
                branch: branch,
                progressKeyPresent: progressKeyPresent,
                progress: progress,
                isGenerating: isGenerating
            )
            mergeWindowHints(into: idx, patch: hintPatch)
            moveToFront(idx)
            return
        }
        let ws = workspacePath
        let anchor = CLIWorkspaceIdentity.anchorPath(absPath: absPath, workspacePath: ws, taskId: taskId)
        let row = AgentCLITask(
            id: taskId,
            assistantExecutable: assistant,
            title: title,
            phase: phase,
            startedAt: now,
            completedAt: nil,
            detail: detail,
            workspacePath: ws,
            identityPath: anchor,
            projectName: projectName,
            chatPreviewTurns: chatTurns,
            branchName: branchKeyPresent ? branch.flatMap { $0.isEmpty ? nil : $0 } : nil,
            progressPercent: progressKeyPresent ? progress : nil,
            isGenerating: isGenerating,
            surface: surface,
            windowHints: hintPatch
        )
        tasks.insert(row, at: 0)
        trimIfNeeded()
    }
    
    private func applyIdentityPath(at idx: Int, absPath: String?, workspacePath: String?) {
        let t = tasks[idx]
        let newAbs = absPath.flatMap { s in
            let u = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? nil : u
        }
        let newWs = workspacePath.flatMap { s in
            let u = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return u.isEmpty ? nil : u
        }
        guard newAbs != nil || newWs != nil else { return }
        let ws = newWs ?? t.workspacePath
        tasks[idx].identityPath = CLIWorkspaceIdentity.anchorPath(absPath: newAbs, workspacePath: ws, taskId: t.id)
    }
    
    private func complete(
        taskId: String,
        assistant: String,
        title: String,
        success: Bool,
        workspacePath: String?,
        absPath: String?,
        projectName: String?,
        chatTurns: [String],
        detail: String?,
        surface: String?,
        hintPatch: CLITaskWindowHints,
        notify: Bool = true,
        branchKeyPresent: Bool,
        branch: String?,
        progressKeyPresent: Bool,
        progress: Int?,
        isGenerating: Bool
    ) {
        let now = Date()
        if let idx = tasks.firstIndex(where: { $0.id == taskId }) {
            let wasAlreadyCompleted: Bool
            if case .completed = tasks[idx].phase { wasAlreadyCompleted = true } else { wasAlreadyCompleted = false }
            tasks[idx].phase = .completed(success: success)
            tasks[idx].completedAt = now
            if let detail, !detail.isEmpty { tasks[idx].detail = detail }
            if !title.isEmpty { tasks[idx].title = title }
            if let workspacePath, !workspacePath.isEmpty { tasks[idx].workspacePath = workspacePath }
            if let surface, !surface.isEmpty { tasks[idx].surface = surface }
            if let projectName, !projectName.isEmpty { tasks[idx].projectName = projectName }
            if !chatTurns.isEmpty { tasks[idx].chatPreviewTurns = chatTurns }
            applyIdentityPath(at: idx, absPath: absPath, workspacePath: workspacePath)
            applyPresentationFields(
                at: idx,
                branchKeyPresent: branchKeyPresent,
                branch: branch,
                progressKeyPresent: progressKeyPresent,
                progress: progress,
                isGenerating: isGenerating
            )
            mergeWindowHints(into: idx, patch: hintPatch)
            moveToFront(idx)
            let shouldNotify = notify && !wasAlreadyCompleted
            if shouldNotify {
                let row = tasks.first(where: { $0.id == taskId })
                let label = row?.assistantDisplayName ?? (AIAssistantType.allCases.first { $0.executableName == assistant }?.rawValue ?? assistant)
                postCompletionNotification(assistantLabel: label, title: title, workspacePath: row?.workspacePath, success: success)
            }
            if !wasAlreadyCompleted {
                SoundManager.shared.playTaskCompletionIfEnabled(success: success)
                scheduleCompactCompletedGlow()
                presentCompletionToast(taskId: taskId, success: success)
            }
            return
        } else {
            let ws = workspacePath
            let anchor = CLIWorkspaceIdentity.anchorPath(absPath: absPath, workspacePath: ws, taskId: taskId)
            let row = AgentCLITask(
                id: taskId,
                assistantExecutable: assistant,
                title: title,
                phase: .completed(success: success),
                startedAt: now,
                completedAt: now,
                detail: detail,
                workspacePath: ws,
                identityPath: anchor,
                projectName: projectName,
                chatPreviewTurns: chatTurns,
                branchName: branchKeyPresent ? branch.flatMap { $0.isEmpty ? nil : $0 } : nil,
                progressPercent: progressKeyPresent ? progress : nil,
                isGenerating: isGenerating,
                surface: surface,
                windowHints: hintPatch
            )
            tasks.insert(row, at: 0)
            trimIfNeeded()
            if notify {
                let row = tasks.first(where: { $0.id == taskId })
                let label = row?.assistantDisplayName ?? (AIAssistantType.allCases.first { $0.executableName == assistant }?.rawValue ?? assistant)
                postCompletionNotification(assistantLabel: label, title: title, workspacePath: row?.workspacePath, success: success)
            }
            SoundManager.shared.playTaskCompletionIfEnabled(success: success)
            scheduleCompactCompletedGlow()
            presentCompletionToast(taskId: taskId, success: success)
        }
    }
    
    private func presentCompletionToast(taskId: String, success: Bool) {
        guard !IslandWindowChromeController.shared.isIslandWindowKey else { return }
        guard let row = tasks.first(where: { $0.id == taskId }) else { return }
        toastDismissWorkItem?.cancel()
        let toast = CLITaskCompletionToast(
            taskId: taskId,
            title: row.title,
            assistantLabel: row.assistantDisplayName,
            success: success,
            dialogSnippet: CLITaskRowFormatting.completionToastDialogSnippet(from: row)
        )
        completionToast = toast
        let capturedId = taskId
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.completionToast?.taskId == capturedId {
                self.completionToast = nil
            }
            self.toastDismissWorkItem = nil
        }
        toastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 14, execute: work)
    }
    
    private func scheduleCompactCompletedGlow() {
        compactGlowResetWorkItem?.cancel()
        compactCompletedGlowDeadline = Date().addingTimeInterval(2.35)
        let work = DispatchWorkItem { [weak self] in
            self?.compactCompletedGlowDeadline = nil
            self?.compactGlowResetWorkItem = nil
        }
        compactGlowResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.35, execute: work)
    }
    
    private func moveToFront(_ index: Int) {
        guard index > 0, index < tasks.count else { return }
        let item = tasks.remove(at: index)
        tasks.insert(item, at: 0)
    }
    
    private func trimIfNeeded() {
        if tasks.count > maxTasks {
            tasks = Array(tasks.prefix(maxTasks))
        }
    }
    
    private func requestNotificationAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                if let error {
                    TaskActivityLog.logger.error("notification auth: \(String(describing: error), privacy: .public)")
                } else {
                    TaskActivityLog.logger.info("notification auth granted=\(granted, privacy: .public)")
                }
            }
        }
    }
    
    private func postCompletionNotification(assistantLabel: String, title: String, workspacePath: String?, success: Bool) {
        guard AiLandPreferences.shared.systemNotificationOnTaskCompletion else { return }
        let content = UNMutableNotificationContent()
        content.title = success ? "会话已结束" : "会话已结束（异常）"
        content.subtitle = assistantLabel
        if let path = workspacePath, !path.isEmpty {
            content.body = title + "\n" + path
        } else {
            content.body = title
        }
        content.sound = AiLandPreferences.shared.soundOnTaskCompletion ? .default : nil
        let id = UUID().uuidString
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                TaskActivityLog.logger.error("post notification: \(String(describing: error), privacy: .public)")
            }
        }
    }
    
    private func truthy(_ s: String?) -> Bool {
        guard let s = s?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else { return true }
        return ["1", "true", "yes", "ok"].contains(s)
    }
}

private extension String {
    var nonEmptyOrNil: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - UNUserNotificationCenterDelegate

private final class TaskNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        DispatchQueue.main.async {
            let p = AiLandPreferences.shared
            guard p.systemNotificationOnTaskCompletion else {
                completionHandler([])
                return
            }
            if IslandWindowChromeController.shared.isIslandWindowKey {
                completionHandler([])
                return
            }
            var opts: UNNotificationPresentationOptions = [.banner]
            if p.soundOnTaskCompletion {
                opts.insert(.sound)
            }
            completionHandler(opts)
        }
    }
}
