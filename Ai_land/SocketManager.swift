//
//  SocketManager.swift
//  Ai_land
//
//  Unix 套接字 `/tmp/ai-land.sock`：按行 JSON，驱动 `ai-land://`（及历史 `code-island://`）分发。
//  示例：`{"op":"url","u":"ai-land://task?assistant=claude&state=running&task_id=x&title=T"}`
//

import Foundation

final class SocketManager {
    static let shared = SocketManager()
    
    private let socketPath = "/tmp/ai-land.sock"
    private var serverSocket: Int32 = -1
    private var clientSockets: [Int32] = []
    private var isRunning = false
    private let queue = DispatchQueue(label: "com.xiaoo.ai-land.socket", qos: .userInitiated)
    /// 单连接行缓冲上限（UTF-8 字节）
    private let maxLineBytes = 65_536
    
    private init() {
        setupSocket()
    }
    
    private func setupSocket() {
        queue.async {
            if FileManager.default.fileExists(atPath: self.socketPath) {
                try? FileManager.default.removeItem(atPath: self.socketPath)
            }
            
            self.serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
            guard self.serverSocket != -1 else {
                print("Failed to create socket: \(errno)")
                return
            }
            
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            strlcpy(&addr.sun_path, self.socketPath, MemoryLayout.size(ofValue: addr.sun_path))
            
            let addrLen = socklen_t(MemoryLayout.size(ofValue: addr))
            if bind(self.serverSocket, self.sockaddr_cast(&addr), addrLen) == -1 {
                print("Failed to bind socket: \(errno)")
                close(self.serverSocket)
                return
            }
            
            if listen(self.serverSocket, SOMAXCONN) == -1 {
                print("Failed to listen on socket: \(errno)")
                close(self.serverSocket)
                return
            }
            
            self.isRunning = true
            self.acceptConnections()
        }
    }
    
    private func acceptConnections() {
        queue.async {
            while self.isRunning {
                let clientSocket = accept(self.serverSocket, nil, nil)
                guard clientSocket != -1 else {
                    if errno != EINTR {
                        print("Failed to accept connection: \(errno)")
                    }
                    continue
                }
                
                self.clientSockets.append(clientSocket)
                self.handleConnection(clientSocket)
            }
        }
    }
    
    private func handleConnection(_ clientSocket: Int32) {
        queue.async {
            var buffer = [UInt8](repeating: 0, count: 4096)
            var lineBuf = Data()
            
            while true {
                let bytesRead = read(clientSocket, &buffer, buffer.count)
                guard bytesRead > 0 else {
                    if bytesRead == 0 {
                        print("Client disconnected")
                    } else {
                        print("Failed to read from socket: \(errno)")
                    }
                    break
                }
                
                lineBuf.append(buffer, count: bytesRead)
                if lineBuf.count > self.maxLineBytes * 4 {
                    lineBuf.removeAll(keepingCapacity: false)
                    continue
                }
                
                let nl = UInt8(ascii: "\n")
                while let idx = lineBuf.firstIndex(of: nl) {
                    let piece = lineBuf.subdata(in: lineBuf.startIndex..<idx)
                    lineBuf.removeSubrange(...idx)
                    if piece.count <= self.maxLineBytes {
                        self.processSocketPayload(piece)
                    }
                }
            }
            
            if let index = self.clientSockets.firstIndex(of: clientSocket) {
                self.clientSockets.remove(at: index)
            }
            close(clientSocket)
        }
    }
    
    private static func looksLikeAppDeepLinkURLString(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.hasPrefix("ai-land://") || lower.hasPrefix("code-island://")
    }
    
    /// 单行：UTF-8 文本；优先解析 JSON `{"op":"url","u":"..."}` 或 `{"url":"..."}`。
    private func processSocketPayload(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        if let d = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            let op = (obj["op"] as? String)?.lowercased()
            let urlString = (obj["u"] as? String) ?? (obj["url"] as? String)
            if op == "permission_request" {
                sendResponse("{\"ok\":true,\"permission\":\"granted\"}")
                return
            }
            if let urlString, let url = URL(string: urlString) {
                AiLandURLRouting.dispatchOnMainActor(url)
                sendResponse("{\"ok\":true}")
                return
            }
            if let urlString, Self.looksLikeAppDeepLinkURLString(urlString), let url = URL(string: urlString) {
                AiLandURLRouting.dispatchOnMainActor(url)
                sendResponse("{\"ok\":true}")
                return
            }
            sendResponse("{\"ok\":false,\"error\":\"missing_url\"}")
            return
        }
        
        if Self.looksLikeAppDeepLinkURLString(trimmed), let url = URL(string: trimmed) {
            AiLandURLRouting.dispatchOnMainActor(url)
            sendResponse("{\"ok\":true}")
        }
    }
    
    func sendResponse(_ response: String) {
        queue.async {
            let payload = (response + "\n").data(using: .utf8) ?? Data()
            for sock in self.clientSockets {
                payload.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    _ = write(sock, base, payload.count)
                }
            }
        }
    }
    
    func sendCommand(to agent: AIAssistantType, command: String) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let message = "{\"agent\":\"\(agent.executableName)\",\"command\":\"\(escaped)\"}"
        sendResponse(message)
    }
    
    deinit {
        isRunning = false
        
        for socket in clientSockets {
            close(socket)
        }
        
        if serverSocket != -1 {
            close(serverSocket)
        }
        
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
        }
    }
    
    private func sockaddr_cast(_ ptr: UnsafePointer<sockaddr_un>) -> UnsafePointer<sockaddr> {
        UnsafePointer<sockaddr>(OpaquePointer(ptr))
    }
}
