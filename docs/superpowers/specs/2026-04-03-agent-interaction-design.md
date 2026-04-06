## 目标

当某个 Agent 需要用户交互（选择/确认）时：

- 灵动岛窗口自动展开（不依赖 hover）
- 在展开态的“列表区域”显示一张对话卡片，提供按钮选项
- 用户点选后，把结果回传给 Agent，并在鼠标移开前保持展开

## 触发协议（Agent → App）

- URL Scheme: `ai-land://interact?...`（历史 `code-island` 仍注册，应用内双兼容）
- Query 参数：
  - `agent`: `claude|codex|gemini|cursor|opencode|droid`
  - `id`: 请求唯一标识（uuid/时间戳）
  - `title`（可选）
  - `prompt`（可选）
  - `options`: `|` 分隔选项（如 `继续|停止|稍后`，需要 URL 编码）

示例：

`ai-land://interact?agent=claude&id=1712131230&title=%E7%A1%AE%E8%AE%A4&prompt=%E6%98%AF%E5%90%A6%E7%BB%A7%E7%BB%AD%EF%BC%9F&options=%E7%BB%A7%E7%BB%AD|%E5%81%9C%E6%AD%A2|%E7%A8%8D%E5%90%8E`

## UI 行为

- 收到 `interact`：
  - 置 `forceExpandedUntilMouseLeaves = true`
  - `isExpanded = true`
  - 在展开态内容区（Tab 下面、列表上方）插入交互卡片
- hover 行为：
  - `forceExpandedUntilMouseLeaves == true` 时：hover 进入保持展开，hover 离开才允许收起并清除强制标记
- 交互卡片：
  - 黑底 + 细描边 + 轻微阴影，与全黑风格一致
  - prompt 文本区域更高（允许多行显示）
  - options 以按钮呈现（自适应换行）

## 回传（App → Agent）

为保证跨进程可靠性，选项点击后将结果写入：

- `~/.ai-land/interactions/<id>.json`（写入）；收件箱同时监听 `~/.ai-land/interact-inbox` 与历史 `~/.code-island/interact-inbox`

字段：

`{ "id": "...", "agent": "...", "choice": "...", "chosenAt": 1712131230 }`

后续如需实时回传再扩展 socket/HTTP。

