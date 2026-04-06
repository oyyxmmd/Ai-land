//
//  IslandChromeViews.swift
//  Ai_land
//
//  Dynamic Island 风格：活动任务条 + 交互选项面板（Command Palette 式）
//

import SwiftUI

enum IslandTheme {
    /// 用户可见应用名（菜单栏、窗口标题、岛上文案等）
    static let appDisplayName = "Ai-land"
    static let teal = Color(red: 0.32, green: 0.82, blue: 0.76)
    static let tealMuted = Color(red: 0.28, green: 0.55, blue: 0.52)
    /// 权限 / 审阅请求强调色（参考橙色标题条）
    static let permissionOrange = Color(red: 0.98, green: 0.52, blue: 0.20)
    static let cardFill = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let rowHover = Color(red: 0.12, green: 0.22, blue: 0.22)
    static let strokeSubtle = Color.white.opacity(0.09)
    static let strokeStrong = Color.white.opacity(0.14)
}

// MARK: - Pills

struct IslandPill: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.11))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - 交互面板（克劳德问道 + ⌘1…）

struct IslandInteractionPaletteView: View {
    let request: InteractionRequest
    @ObservedObject var interactionManager: InteractionManager
    @State private var hoveredIndex: Int? = nil
    
    /// 大标题：使用 CLI / 产品名（如 Claude Code），不用钩子里的泛化词「操作」等。
    private var cliMainTitle: String {
        request.agent.rawValue
    }
    
    /// 说明文案：优先模型/工具传来的 prompt，其次非泛化的 title。
    private var detailSubline: String? {
        let p = request.prompt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let t = request.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !p.isEmpty { return p }
        if !t.isEmpty, !Self.isGenericHookTitle(t) { return t }
        return nil
    }
    
    /// 两项且文案像「工具 / 权限 / 允许 / 拒绝」时，用大按钮「允许」「拒绝」映射回原始选项字符串回传钩子。
    private var toolPermissionPair: (allow: String, deny: String)? {
        Self.resolveToolPermissionAllowDeny(in: request)
    }
    
    private static func isGenericHookTitle(_ s: String) -> Bool {
        let u = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["操作", "operation", "action", "actions", "选择", "choose", "option", "options", "确认", "confirm"].contains(u)
    }
    
    /// 标题/问题/选项里出现工具权限相关词，且恰好两项。
    private static func resolveToolPermissionAllowDeny(in request: InteractionRequest) -> (allow: String, deny: String)? {
        guard request.options.count == 2 else { return nil }
        let a = request.options[0]
        let b = request.options[1]
        let blob = "\(request.title ?? "") \(request.prompt ?? "") \(a) \(b)".lowercased()
        let contextKeys = [
            "permission", "tool", "pretool", "bash", "shell", "command", "execute", "run ", "run\n",
            "allow", "deny", "approve", "reject", "工具", "权限", "执行", "命令", "允许", "拒绝", "批准", "否决", "运行"
        ]
        let hasContext = contextKeys.contains { blob.contains($0) }
        let sa = permissionSideScore(a)
        let sb = permissionSideScore(b)
        let clearPair = (sa > 0 && sb < 0) || (sb > 0 && sa < 0)
        guard hasContext || clearPair else { return nil }
        if sa > 0 && sb < 0 { return (allow: a, deny: b) }
        if sb > 0 && sa < 0 { return (allow: b, deny: a) }
        // 仅有上下文但选项未带 allow/deny 字样时，默认第一项为允许侧（常见「Yes / No」顺序）
        return sa >= sb ? (allow: a, deny: b) : (allow: b, deny: a)
    }
    
    private static func permissionSideScore(_ s: String) -> Int {
        let u = s.lowercased()
        var n = 0
        for w in ["allow", "yes", "approve", "continue", "ok", "accept", "grant", "允许", "批准", "继续", "是", "同意", "启用"] {
            if u.contains(w) { n += 4 }
        }
        for w in ["deny", "no", "reject", "cancel", "abort", "stop", "decline", "拒绝", "否", "取消", "否决", "禁用"] {
            if u.contains(w) { n -= 4 }
        }
        return n
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: toolPermissionPair != nil ? "lock.shield.fill" : "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(toolPermissionPair != nil ? IslandTheme.permissionOrange : IslandTheme.teal)
                        .symbolRenderingMode(.hierarchical)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.fmt(
                            "interaction_title_format",
                            request.agent.rawValue,
                            toolPermissionPair != nil ? L10n.str("interaction_tool_permissions") : L10n.str("interaction_ask_user")
                        ))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle((toolPermissionPair != nil ? IslandTheme.permissionOrange : IslandTheme.teal).opacity(0.95))
                        Text(cliMainTitle)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                
                Spacer(minLength: 8)
                
                Button(action: { interactionManager.dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
                .help("interaction_close_means_deny")
            }
            
            if toolPermissionPair != nil {
                Text("interaction_tool_perm_explain")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let detailSubline {
                Text(detailSubline)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.52))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            if let pair = toolPermissionPair {
                toolPermissionAllowDenyButtons(allowChoice: pair.allow, denyChoice: pair.deny)
            } else {
                // 由内容撑开窗高；极长列表在接近屏高上限时由外层 maxExpandedIslandHeight 约束，内层可滚动
                ViewThatFits(in: .vertical) {
                    VStack(spacing: 6) {
                        ForEach(Array(request.options.enumerated()), id: \.offset) { index, option in
                            optionButton(index: index, option: option)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(request.options.enumerated()), id: \.offset) { index, option in
                                optionButton(index: index, option: option)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                }
                .frame(minHeight: 44)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(IslandTheme.cardFill)
                .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(IslandTheme.strokeStrong, lineWidth: 1)
        )
        .onExitCommand {
            interactionManager.dismiss()
        }
    }
    
    @ViewBuilder
    private func toolPermissionAllowDenyButtons(allowChoice: String, denyChoice: String) -> some View {
        HStack(spacing: 12) {
            Button {
                interactionManager.complete(choice: denyChoice)
            } label: {
                HStack(spacing: 8) {
                    Text("deny")
                        .font(.system(size: 14, weight: .semibold))
                    Text("⌘N")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.42))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(IslandTheme.strokeSubtle, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help(L10n.fmt("deny_help_format", denyChoice))
            
            Button {
                interactionManager.complete(choice: allowChoice)
            } label: {
                HStack(spacing: 8) {
                    Text("allow")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black.opacity(0.88))
                    Text("⌘Y")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.black.opacity(0.42))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(white: 0.93))
                )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("y", modifiers: .command)
            .help(L10n.fmt("allow_help_format", allowChoice))
        }
        .accessibilityElement(children: .contain)
    }
    
    @ViewBuilder
    private func optionButton(index: Int, option: String) -> some View {
        let isHover = hoveredIndex == index
        Button {
            interactionManager.complete(choice: option)
        } label: {
            HStack(spacing: 12) {
                Text(index < 9 ? "⌘\(index + 1)" : "—")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(IslandTheme.teal)
                    .frame(minWidth: 34)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                    )
                    .opacity(index < 9 ? 1 : 0.35)
                
                Text(option)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHover ? IslandTheme.rowHover.opacity(0.85) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHover ? IslandTheme.teal.opacity(0.35) : IslandTheme.strokeSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredIndex = hovering ? index : (hoveredIndex == index ? nil : hoveredIndex)
        }
        .modifier(IslandOptionShortcutModifier(index: index))
    }
    
    /// 与面板副标题一致：产品名（六款编码代理）· 问道。
    static func agentAsksLabel(_ agent: AIAssistantType) -> String {
        L10n.fmt("interaction_title_format", agent.rawValue, L10n.str("interaction_ask_user"))
    }
}

private struct IslandOptionShortcutModifier: ViewModifier {
    let index: Int
    
    private static let digitKeys: [Character] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if index < 9 {
            content.keyboardShortcut(
                KeyEquivalent(Self.digitKeys[index]),
                modifiers: .command
            )
        } else {
            content
        }
    }
}

// MARK: - 活动任务行（展开 / 紧凑）

struct IslandExpandedActivityRow: View {
    let iconSystemName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badges: [String]
    let timeLabel: String
    var statusLine: String? = nil
    var statusColor: Color = .green
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconColor.opacity(0.22))
                        .frame(width: 40, height: 40)
                    Image(systemName: iconSystemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.45))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let statusLine, !statusLine.isEmpty {
                        Text(statusLine)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                }
                
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Array(badges.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, b in
                            IslandPill(text: b)
                        }
                    }
                    if !timeLabel.isEmpty {
                        Text(timeLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.35))
                    }
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(IslandTheme.strokeSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct IslandCompactActivityRow: View {
    let dotColor: Color
    let title: String
    let badges: [String]
    let timeLabel: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                    .padding(.top, 2)
                
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.92))
                    .lineLimit(1)
                
                Spacer(minLength: 8)
                
                HStack(spacing: 6) {
                    ForEach(Array(badges.filter { !$0.isEmpty }.enumerated()), id: \.offset) { _, b in
                        IslandPill(text: b)
                    }
                }
                
                if !timeLabel.isEmpty {
                    Text(timeLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.32))
                        .frame(width: 36, alignment: .trailing)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 权限请求 + Diff（计划审阅）

struct IslandDiffRow: Identifiable {
    enum Kind {
        case context
        case removed
        case added
    }
    
    let id = UUID()
    let kind: Kind
    let lineNumber: Int
    let text: String
    
    static func from(plan: Plan) -> [IslandDiffRow] {
        let normalized = plan.content.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.isEmpty {
            return [IslandDiffRow(kind: .context, lineNumber: 12, text: L10n.str("plan_diff_empty_placeholder"))]
        }
        var out: [IslandDiffRow] = []
        var n = 12
        out.append(IslandDiffRow(kind: .context, lineNumber: n, text: lines[0]))
        n += 1
        if lines.count >= 2 {
            out.append(IslandDiffRow(kind: .removed, lineNumber: n, text: lines[1]))
            n += 1
        }
        let end = min(lines.count, 8)
        for i in 2..<end {
            out.append(IslandDiffRow(kind: .added, lineNumber: n, text: lines[i]))
            n += 1
        }
        return out
    }
    
    static func changeStats(for rows: [IslandDiffRow]) -> (added: Int, removed: Int) {
        var a = 0
        var r = 0
        for row in rows {
            switch row.kind {
            case .added: a += 1
            case .removed: r += 1
            case .context: break
            }
        }
        return (a, r)
    }
}

extension Plan {
    /// 用于权限卡片展示的伪文件路径
    var islandPermissionFilePath: String {
        let slug = title
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let safe = String(slug.prefix(42))
        return "src/plans/\(safe).md"
    }
}

struct IslandPermissionDiffCard: View {
    let filePath: String
    let rows: [IslandDiffRow]
    let onAllow: () -> Void
    let onReject: () -> Void
    
    private var stats: (added: Int, removed: Int) { IslandDiffRow.changeStats(for: rows) }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Circle()
                    .fill(IslandTheme.permissionOrange)
                    .frame(width: 6, height: 6)
                Text("plan_permission_request")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(IslandTheme.permissionOrange)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(IslandTheme.permissionOrange)
                Text("edit")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(IslandTheme.permissionOrange)
                Text(filePath)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.88))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        diffLine(row)
                    }
                }
            }
            .frame(maxHeight: 240)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(IslandTheme.strokeSubtle, lineWidth: 1)
            )
            
            Text("+\(stats.added) -\(stats.removed)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.38))
            
            HStack(spacing: 12) {
                Button(action: onReject) {
                    HStack(spacing: 8) {
                        Text("deny")
                            .font(.system(size: 14, weight: .semibold))
                        Text("⌘N")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.42))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(IslandTheme.strokeSubtle, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
                
                Button(action: onAllow) {
                    HStack(spacing: 8) {
                        Text("allow")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black.opacity(0.88))
                        Text("⌘Y")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.black.opacity(0.42))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(white: 0.93))
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("y", modifiers: .command)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(IslandTheme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(IslandTheme.strokeStrong, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
    }
    
    @ViewBuilder
    private func diffLine(_ row: IslandDiffRow) -> some View {
        let mono = Font.system(size: 11, design: .monospaced)
        HStack(alignment: .top, spacing: 8) {
            Text("\(row.lineNumber)")
                .font(mono)
                .foregroundColor(.white.opacity(0.28))
                .frame(width: 24, alignment: .trailing)
            switch row.kind {
            case .context:
                Text(row.text)
                    .font(mono)
                    .foregroundColor(.white.opacity(0.42))
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .removed:
                HStack(spacing: 6) {
                    Text("−")
                    Text(row.text)
                }
                .font(mono)
                .foregroundColor(.white.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(Color.red.opacity(0.30))
            case .added:
                HStack(spacing: 6) {
                    Text("+")
                    Text(row.text)
                }
                .font(mono)
                .foregroundColor(.white.opacity(0.92))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
                .padding(.horizontal, 6)
                .background(Color.green.opacity(0.28))
            }
        }
        .padding(.vertical, 2)
    }
}

/// 计划点击后：独立 Sheet 内嵌权限 + diff 卡片
struct IslandPlanPermissionSheet: View {
    let plan: Plan
    let onAllow: () -> Void
    let onReject: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(plan.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.45))
                    .lineLimit(1)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            
            IslandPermissionDiffCard(
                filePath: plan.islandPermissionFilePath,
                rows: IslandDiffRow.from(plan: plan),
                onAllow: onAllow,
                onReject: onReject
            )
        }
        .padding(20)
        .frame(minWidth: 460)
        .background(Color.black.opacity(0.97))
    }
}
