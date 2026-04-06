//
//  CLITaskListRowViews.swift
//  Ai_land
//
//  CLI 任务列表 F 型三层错落布局：主行项目/分支、对话预览、辅助元信息；左侧呼吸条与头像进度环。
//

import SwiftUI

// MARK: - 文案与截断

enum CLITaskRowFormatting {
    static let previewCharacterCap = 20

    static func previewSource(from task: AgentCLITask) -> String {
        if let first = task.chatPreviewTurns.first, !first.isEmpty { return first }
        if let d = task.detail, !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return d }
        let t = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "暂无预览" : t
    }

    static func truncatedPreview(_ raw: String) -> String {
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let t = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count <= previewCharacterCap { return t.isEmpty ? "暂无预览" : t }
        let head = 8
        let tail = 6
        if t.count >= head + tail + 1 {
            let si = t.index(t.startIndex, offsetBy: head)
            let ei = t.index(t.endIndex, offsetBy: -tail)
            if si < ei {
                return String(t[..<si]) + "…" + String(t[ei...])
            }
        }
        return String(t.prefix(previewCharacterCap - 1)) + "…"
    }
    
    /// 完成 Peek 条：优先多轮 `chat_r0…`；忽略钩子占位 `detail`（如「本轮输出已结束」）。
    static func completionToastDialogSnippet(from task: AgentCLITask) -> String {
        let boringExact: Set<String> = [
            "本轮输出已结束",
            "等待模型输出…",
            "等待模型输出...",
            "会话已退出",
            "CLI 任务",
        ]
        func isBoringDetail(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return true }
            if boringExact.contains(t) { return true }
            if t.hasPrefix("会话结束:"), t.count < 48 { return true }
            return false
        }
        func collapseLine(_ s: String) -> String {
            s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        func clampMultiline(_ text: String, maxChars: Int) -> String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count <= maxChars { return t }
            let end = t.index(t.startIndex, offsetBy: maxChars - 1)
            let slice = t[..<end]
            if let nl = slice.lastIndex(of: "\n") {
                return String(slice[..<nl]).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
            }
            return String(slice) + "…"
        }
        func isNoiseSnippetLine(_ s: String) -> Bool {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return true }
            if t.count <= 4, t.allSatisfy(\.isNumber) { return true }
            return false
        }
        
        let turns = task.chatPreviewTurns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !isNoiseSnippetLine($0) }
        if !turns.isEmpty {
            let joined = turns.prefix(3).map(collapseLine).joined(separator: "\n")
            return clampMultiline(joined, maxChars: 200)
        }
        if let d = task.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !d.isEmpty, !isBoringDetail(d) {
            let collapsed = collapseLine(d)
            if !isNoiseSnippetLine(collapsed) {
                return clampMultiline(collapsed, maxChars: 200)
            }
        }
        let title = collapseLine(task.title.trimmingCharacters(in: .whitespacesAndNewlines))
        if !title.isEmpty, !isBoringDetail(title), title != task.assistantDisplayName, !isNoiseSnippetLine(title) {
            return clampMultiline(title, maxChars: 160)
        }
        return ""
    }

    static func headlineProject(from task: AgentCLITask) -> String {
        if let p = CLIWorkspaceIdentity.displayProjectName(explicit: task.projectName, workspacePath: task.workspacePath) {
            return p
        }
        let t = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? L10n.str("unnamed_project") : t
    }

    static func branchLabel(from task: AgentCLITask) -> String {
        let b = task.branchName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return b.isEmpty ? "—" : b
    }

    static func ttySnippet(from task: AgentCLITask) -> String? {
        let tty = task.windowHints.hostTTY?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return tty.isEmpty ? nil : tty
    }

    static func relativeShort(since date: Date, now: Date) -> String {
        let sec = max(0, Int(now.timeIntervalSince(date)))
        if sec < 2 { return L10n.str("rel_just_now") }
        if sec < 60 { return L10n.fmt("rel_secs_ago", sec) }
        let m = sec / 60
        if m < 60 { return L10n.fmt("rel_mins_ago", m) }
        let h = m / 60
        if h < 24 { return L10n.fmt("rel_hours_ago", h) }
        return L10n.fmt("rel_days_ago", h / 24)
    }
}

// MARK: - 左侧呼吸条（进行中叠绿色呼吸）

struct CLIBreathingStripe: View {
    let hashColor: Color
    let active: Bool
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(hashColor)
            if active {
                Group {
                    if reduceMotion {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.green.opacity(0.42))
                    } else {
                        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: false)) { ctx in
                            let phase = ctx.date.timeIntervalSinceReferenceDate * (2 * .pi / 2.35)
                            let breathe = 0.5 + 0.5 * sin(phase)
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.green.opacity(0.22 + 0.38 * breathe))
                        }
                    }
                }
            }
        }
        .frame(width: 4)
        .padding(.vertical, 8)
        .padding(.leading, 2)
    }
}

// MARK: - 流式生成省略号闪烁

struct CLIGeneratingEllipsis: View {
    var reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Text("…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
                let o = 0.35 + 0.5 * (0.5 + 0.5 * sin(ctx.date.timeIntervalSinceReferenceDate * 5.5))
                Text("…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(o))
            }
        }
    }
}

// MARK: - 头像 + 圆环进度

struct CLITaskAvatarWithProgressRing: View {
    let task: AgentCLITask
    let hashColor: Color
    let ident: String
    var reduceMotion: Bool

    private let avatarDiameter: CGFloat = 28
    private let ringPadding: CGFloat = 3
    private let ringLine: CGFloat = 2.5

    private var ringDiameter: CGFloat { avatarDiameter + ringPadding * 2 }

    private var isActive: Bool {
        switch task.phase {
        case .running, .waitingConfirm: return true
        default: return false
        }
    }

    private var ringColor: Color {
        switch task.phase {
        case .waitingConfirm: return Color.orange.opacity(0.95)
        case .completed(let ok): return ok ? Color.green.opacity(0.9) : Color.red.opacity(0.88)
        default: return IslandTheme.teal
        }
    }

    var body: some View {
        Group {
            if case .completed = task.phase {
                ZStack {
                    Circle()
                        .fill(hashColor.opacity(0.92))
                        .frame(width: avatarDiameter, height: avatarDiameter)
                    avatarInnerContent
                }
                .frame(width: avatarDiameter + 2, height: avatarDiameter + 2)
            } else {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.12), lineWidth: ringLine)
                        .frame(width: ringDiameter, height: ringDiameter)

                    progressRingLayer

                    Circle()
                        .fill(hashColor.opacity(0.92))
                        .frame(width: avatarDiameter, height: avatarDiameter)

                    avatarInnerContent
                }
                .frame(width: ringDiameter + 2, height: ringDiameter + 2)
            }
        }
    }

    @ViewBuilder
    private var progressRingLayer: some View {
        switch task.phase {
        case .completed:
            EmptyView()
        case .running, .waitingConfirm:
            if let p = task.progressPercent {
                Circle()
                    .trim(from: 0, to: CGFloat(p) / 100)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: ringDiameter, height: ringDiameter)
            } else if isActive {
                indeterminateRing
            }
        }
    }

    @ViewBuilder
    private var indeterminateRing: some View {
        if reduceMotion {
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(ringColor.opacity(0.85), style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: ringDiameter, height: ringDiameter)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 36.0, paused: false)) { ctx in
                let t = ctx.date.timeIntervalSinceReferenceDate
                let angle = (t.truncatingRemainder(dividingBy: 1.35) / 1.35) * 360
                Circle()
                    .trim(from: 0, to: 0.2)
                    .stroke(ringColor.opacity(0.9), style: StrokeStyle(lineWidth: ringLine, lineCap: .round))
                    .rotationEffect(.degrees(-90 + angle))
                    .frame(width: ringDiameter, height: ringDiameter)
            }
        }
    }

    @ViewBuilder
    private var avatarInnerContent: some View {
        switch task.phase {
        case .completed(let ok):
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    Color.white.opacity(0.95),
                    ok ? Color.green.opacity(0.92) : Color.red.opacity(0.88)
                )
        default:
            Text(ident)
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(task.phase == .running ? 0.42 : 0.96))
        }
    }
}
