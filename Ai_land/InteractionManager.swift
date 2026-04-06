//
//  InteractionManager.swift
//  Ai_land
//
//  Created by oyyx on 2026/4/3.
//

import Foundation
import Darwin
import CoreServices
import AppKit
import os.log

private enum InteractLog {
    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "xiaoo.ai-land",
        category: "interact"
    )
}

private struct InteractInboxPayload: Decodable {
    let agent: String?
    let id: String?
    let title: String?
    let prompt: String?
    let options: [String]?
}

struct InteractionRequest: Identifiable, Equatable {
    let id: String
    let agent: AIAssistantType
    let title: String?
    let prompt: String?
    let options: [String]
    let receivedAt: Date
}

final class InteractionManager: ObservableObject {
    static let shared = InteractionManager()
    
    private static let primaryDataDir = ".ai-land"
    private static let legacyDataDir = ".code-island"
    
    private static func allInteractInboxDirectoryURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("\(primaryDataDir)/interact-inbox", isDirectory: true),
            home.appendingPathComponent("\(legacyDataDir)/interact-inbox", isDirectory: true)
        ]
    }
    
    private static func interactionsOutputDirectoryPath() -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent("\(primaryDataDir)/interactions")
    }
    
    @Published private(set) var current: InteractionRequest? = nil
    
    private var inboxWatchSource: DispatchSourceFileSystemObject?
    private var inboxDebounceWorkItem: DispatchWorkItem?
    private var inboxWatchStartAttempts = 0
    private var fsEventStream: FSEventStreamRef?
    private var didBecomeActiveObserver: NSObjectProtocol?
    
    private init() {
        InteractLog.logger.info("InteractionManager init; home=\(NSHomeDirectory(), privacy: .public)")
        startInteractInboxWatcher()
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            InteractLog.logger.debug("app didBecomeActive → poll inbox")
            self?.pollInteractInboxIfNeeded()
        }
    }
    
    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
        stopFSEventStream()
        inboxDebounceWorkItem?.cancel()
        inboxWatchSource?.cancel()
    }
    
    private func stopFSEventStream() {
        guard let stream = fsEventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsEventStream = nil
    }
    
    /// 用 FSEventStream 监听 `interact-inbox`（比单纯 vnode 更可靠）；失败时再回退到 DispatchSource，并在回调里读取 `data` 以重新挂接 kqueue。
    private func startInteractInboxWatcher() {
        let fm = FileManager.default
        let inboxes = Self.allInteractInboxDirectoryURLs()
        for inbox in inboxes {
            do {
                try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            } catch {
                InteractLog.logger.error("create interact-inbox failed: \(String(describing: error), privacy: .public)")
            }
        }
        
        let inboxPaths = inboxes.map(\.path) as NSArray
        InteractLog.logger.info("watching inbox paths count=\(inboxes.count)")
        stopFSEventStream()
        inboxWatchSource?.cancel()
        inboxWatchSource = nil
        
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, _, _, _ in
            guard numEvents > 0, let clientCallBackInfo else { return }
            InteractLog.logger.debug("FSEventStream fired numEvents=\(numEvents)")
            let manager = Unmanaged<InteractionManager>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            manager.scheduleInteractInboxProcessing()
        }
        
        let sinceWhen = FSEventStreamEventId(kFSEventStreamEventIdSinceNow)
        let flags = FSEventStreamCreateFlags(
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        
        if let stream = FSEventStreamCreate(nil, callback, &context, inboxPaths, sinceWhen, 0.2, flags) {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            if FSEventStreamStart(stream) {
                fsEventStream = stream
                inboxWatchStartAttempts = 0
                InteractLog.logger.info("FSEventStream started OK")
            } else {
                InteractLog.logger.warning("FSEventStreamStart failed → DispatchSource fallback")
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                startDispatchInboxFallback(path: inboxes[0].path)
            }
        } else {
            InteractLog.logger.warning("FSEventStreamCreate failed → DispatchSource fallback")
            startDispatchInboxFallback(path: inboxes[0].path)
        }
        
        pollInteractInboxIfNeeded()
    }
    
    private func startDispatchInboxFallback(path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            InteractLog.logger.error("open(O_EVTONLY) failed errno=\(errno) path=\(path, privacy: .public)")
            inboxWatchStartAttempts += 1
            if inboxWatchStartAttempts < 4 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.startInteractInboxWatcher()
                }
            }
            return
        }
        inboxWatchStartAttempts = 0
        InteractLog.logger.info("DispatchSource vnode watcher active (fallback)")
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .attrib, .link, .revoke, .delete],
            queue: .main
        )
        source.setCancelHandler {
            close(fd)
        }
        inboxWatchSource = source
        source.setEventHandler { [weak self] in
            guard let self, let s = self.inboxWatchSource else { return }
            _ = s.data
            InteractLog.logger.debug("DispatchSource vnode event → schedule poll")
            self.scheduleInteractInboxProcessing()
        }
        source.resume()
    }
    
    private func scheduleInteractInboxProcessing() {
        inboxDebounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.pollInteractInboxIfNeeded()
        }
        inboxDebounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
    
    func handleInteractURL(_ url: URL) {
        guard AiLandURLRouting.isAppURLScheme(url.scheme) else { return }
        let host = url.host?.lowercased()
        let path = url.path.lowercased()
        let isInteract = (host == "interact") || path == "/interact" || path.hasSuffix("/interact")
        guard isInteract else { return }
        
        InteractLog.logger.info("handleInteractURL absoluteString=\(url.absoluteString, privacy: .public)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            InteractLog.logger.error("URLComponents failed for interact URL")
            return
        }
        let items = components.queryItems ?? []
        
        let agentValue = items.first(where: { $0.name == "agent" })?.value
        let agent = Self.resolveAssistant(from: agentValue)
        
        let idRaw = items.first(where: { $0.name == "id" })?.value ?? UUID().uuidString
        let id = AiLandURLRouting.clampField(idRaw, maxChars: AiLandPayloadLimits.interactId) ?? idRaw
        let title = items.first(where: { $0.name == "title" })?.value
            .flatMap { AiLandURLRouting.clampField($0, maxChars: AiLandPayloadLimits.interactTitle) }
        let prompt = items.first(where: { $0.name == "prompt" })?.value
            .flatMap { AiLandURLRouting.clampField($0, maxChars: AiLandPayloadLimits.interactPrompt) }
        let optionsRaw = items.first(where: { $0.name == "options" })?.value ?? ""
        let options = optionsRaw
            .split(separator: "|")
            .map { String($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(AiLandPayloadLimits.interactMaxOptions)
            .map { opt in
                if opt.count > AiLandPayloadLimits.interactOptionChars {
                    return String(opt.prefix(AiLandPayloadLimits.interactOptionChars))
                }
                return opt
            }
        
        let finalOptions = options.isEmpty ? ["确定"] : Array(options)
        InteractLog.logger.info("interact URL parsed agent=\(agent.rawValue, privacy: .public) id=\(id, privacy: .public) optionsCount=\(finalOptions.count)")
        
        DispatchQueue.main.async {
            Task { @MainActor in
                SoundManager.shared.playInteractionIfEnabled()
                self.current = InteractionRequest(
                    id: id,
                    agent: agent,
                    title: title,
                    prompt: prompt,
                    options: finalOptions,
                    receivedAt: Date()
                )
                Self.removeInboxJSONFileIfPresent(requestId: id)
                InteractLog.logger.info("interact request set → current populated (UI should expand)")
            }
        }
    }
    
    /// 钩子可能同时写 inbox JSON 并 `open` URL；去掉 inbox 残留，避免选完后再次 poll 到同一条。
    private static func removeInboxJSONFileIfPresent(requestId: String) {
        let fm = FileManager.default
        for inbox in allInteractInboxDirectoryURLs() {
            let file = inbox.appendingPathComponent("\(requestId).json")
            try? fm.removeItem(at: file)
        }
    }
    
    /// 处理 `~/.ai-land/interact-inbox/*.json`（及历史 `~/.code-island/...`）。效果与 `ai-land://interact?...` 相同。
    func pollInteractInboxIfNeeded() {
        if !Thread.isMainThread {
            DispatchQueue.main.async { self.pollInteractInboxIfNeeded() }
            return
        }
        guard current == nil else {
            InteractLog.logger.debug("poll inbox skipped: already presenting interaction")
            return
        }
        
        let fm = FileManager.default
        for inbox in Self.allInteractInboxDirectoryURLs() {
            do {
                try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            } catch {
                InteractLog.logger.error("poll: createDirectory failed \(String(describing: error), privacy: .public)")
                continue
            }
            
            guard let urls = try? fm.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                InteractLog.logger.error("poll: contentsOfDirectory failed for inbox")
                continue
            }
            let jsonURLs = urls
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            
            if !jsonURLs.isEmpty {
                InteractLog.logger.info("poll: found \(jsonURLs.count) json file(s) in \(inbox.lastPathComponent, privacy: .public)")
            }
            
            for fileURL in jsonURLs {
                let data: Data
                do {
                    data = try Data(contentsOf: fileURL)
                } catch {
                    InteractLog.logger.error("read \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                    continue
                }
                let payload: InteractInboxPayload
                do {
                    payload = try JSONDecoder().decode(InteractInboxPayload.self, from: data)
                } catch {
                    InteractLog.logger.error("JSON decode \(fileURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public) bytes=\(data.count)")
                    continue
                }
                
                let trimmedOptions = (payload.options ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                let options = trimmedOptions.isEmpty ? ["确定"] : trimmedOptions
                
                let idRaw = payload.id?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let id = idRaw.isEmpty ? UUID().uuidString : idRaw
                
                let agent = Self.resolveAssistant(from: payload.agent)
                
                Task { @MainActor in
                    SoundManager.shared.playInteractionIfEnabled()
                    self.current = InteractionRequest(
                        id: id,
                        agent: agent,
                        title: payload.title,
                        prompt: payload.prompt,
                        options: options,
                        receivedAt: Date()
                    )
                    InteractLog.logger.info("inbox consumed \(fileURL.lastPathComponent, privacy: .public) id=\(id, privacy: .public) options=\(options.count)")
                    try? fm.removeItem(at: fileURL)
                }
                return
            }
        }
    }
    
    private static func resolveAssistant(from raw: String?) -> AIAssistantType {
        let s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if s.isEmpty { return .claudeCode }
        if let a = AIAssistantType.allCases.first(where: { $0.executableName.lowercased() == s }) { return a }
        if let a = assistantAliasMap[s] { return a }
        if let a = AIAssistantType.allCases.first(where: { $0.rawValue.lowercased() == s }) { return a }
        return .claudeCode
    }
    
    /// 兼容历史简称、文档与口语（与 `executableName` 及完整 `rawValue` 并列）。
    private static let assistantAliasMap: [String: AIAssistantType] = {
        var m: [String: AIAssistantType] = [:]
        func add(_ keys: [String], _ type: AIAssistantType) {
            for k in keys { m[k.lowercased()] = type }
        }
        add(["claude code", "claude"], .claudeCode)
        add(["codex", "openai codex", "openai codex cli"], .codex)
        add(["gemini", "gemini cli", "google gemini", "google gemini cli"], .geminiCLI)
        add(["cursor", "cursor agent"], .cursor)
        add(["opencode", "open code"], .openCode)
        add(["droid", "factory droid"], .droid)
        return m
    }()
    
    func complete(choice: String) {
        guard let request = current else { return }
        persistResult(requestId: request.id, agent: request.agent.executableName, choice: choice)
        DispatchQueue.main.async {
            self.current = nil
            self.pollInteractInboxIfNeeded()
        }
    }
    
    func dismiss() {
        guard let request = current else {
            DispatchQueue.main.async {
                self.current = nil
                self.pollInteractInboxIfNeeded()
            }
            return
        }
        persistCancellation(requestId: request.id, agent: request.agent.executableName)
        DispatchQueue.main.async {
            self.current = nil
            self.pollInteractInboxIfNeeded()
        }
    }
    
    private func persistResult(requestId: String, agent: String, choice: String) {
        writeInteractionResult(requestId: requestId, agent: agent, payload: [
            "id": requestId,
            "agent": agent,
            "choice": choice,
            "chosenAt": Int(Date().timeIntervalSince1970)
        ])
    }
    
    /// PreToolUse 钩子阻塞等待；用户点 ✕ 关闭卡片时需写入取消，否则 claude 进程会一直卡住。
    private func persistCancellation(requestId: String, agent: String) {
        writeInteractionResult(requestId: requestId, agent: agent, payload: [
            "id": requestId,
            "agent": agent,
            "cancelled": true,
            "chosenAt": Int(Date().timeIntervalSince1970)
        ])
    }
    
    private func writeInteractionResult(requestId: String, agent: String, payload: [String: Any]) {
        let fm = FileManager.default
        let baseDir = Self.interactionsOutputDirectoryPath()
        do {
            try fm.createDirectory(atPath: baseDir, withIntermediateDirectories: true)
            let path = (baseDir as NSString).appendingPathComponent("\(requestId).json")
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        } catch {
            InteractLog.logger.error("write interactions/\(requestId, privacy: .public).json failed")
        }
    }
}

