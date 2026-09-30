import Foundation
import Security

/// A lossless JSON shape (numbers use the API's Double precision).
indirect enum JSON: Codable, Sendable, Hashable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let decoded = try? value.decode(Bool.self) { self = .bool(decoded) }
        else if let decoded = try? value.decode(Double.self) { self = .number(decoded) }
        else if let decoded = try? value.decode(String.self) { self = .string(decoded) }
        else if let decoded = try? value.decode([JSON].self) { self = .array(decoded) }
        else { self = .object(try value.decode([String: JSON].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }

    subscript(_ key: String) -> JSON { object[key] ?? .null }
    var string: String { if case .string(let v) = self { return v }; return "" }
    var number: Double { if case .number(let v) = self { return v }; return 0 }
    var bool: Bool { if case .bool(let v) = self { return v }; return false }
    var array: [JSON] { if case .array(let v) = self { return v }; return [] }
    var object: [String: JSON] { if case .object(let v) = self { return v }; return [:] }
    static func from(_ string: String) -> JSON? {
        try? JSONDecoder().decode(JSON.self, from: Data(string.utf8))
    }
}

/// Deliberately does not surface server text, response bodies, URLs or headers:
/// errors are safe for UI display even if a proxy echoes a credential.
enum KomariAPIError: Error, LocalizedError, Equatable {
    case invalidURL, insecureURL, invalidAPIKey, invalidMethod, invalidParams
    case transport, timedOut, httpStatus(Int), invalidResponse, mismatchedID, rpc(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "请输入完整面板 URL，不允许包含账号密码、查询参数或片段。"
        case .insecureURL: return "默认要求 HTTPS。仅在受信任网络明确开启不安全 HTTP。"
        case .invalidAPIKey: return "API key 为空或包含不支持的字符。"
        case .invalidMethod: return "RPC 方法无效。"
        case .invalidParams: return "RPC 参数必须为对象或数组。"
        case .transport: return "无法安全连接服务器，请检查地址、网络与证书。"
        case .timedOut: return "服务器响应超时。"
        case .httpStatus(let code): return "服务器返回 HTTP \(code)."
        case .invalidResponse: return "服务器返回了无效响应。"
        case .mismatchedID: return "RPC 响应与请求不匹配。"
        case .rpc(let code): return "RPC 请求失败（错误码 \(code))."
        }
    }
}

/// Cancellation is control flow, not a user-facing transport failure.
/// Classify the error itself; callers separately gate cancelled/stale tasks.
enum RequestFailure {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    static func safeTransportError(_ error: Error) -> Error {
        if isCancellation(error) { return CancellationError() }
        if let error = error as? KomariAPIError { return error }
        if (error as? URLError)?.code == .timedOut { return KomariAPIError.timedOut }
        return KomariAPIError.transport
    }
}

/// Refuse ALL redirects, including same-origin: credentials never reach a redirect target.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class APITransport: @unchecked Sendable {
    let session: URLSession
    init(configuration: URLSessionConfiguration) {
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
}

struct KomariAPI: Sendable {
    private let baseURL: URL
    private let apiKey: String
    private let transport: APITransport
    private static let responseLimit = 8 * 1024 * 1024

    init(baseURL: String, apiKey: String, allowHTTP: Bool = false) throws {
        try self.init(baseURL: baseURL, apiKey: apiKey, allowHTTP: allowHTTP,
                      configuration: .ephemeral)
    }

    /// Internal configuration injection permits URLProtocol testing. Production uses ephemeral only.
    init(baseURL: String, apiKey: String, allowHTTP: Bool = false,
         configuration: URLSessionConfiguration) throws {
        self.baseURL = try Self.validatedURL(baseURL, allowHTTP: allowHTTP)
        guard apiKey.unicodeScalars.allSatisfy({ $0.value >= 0x21 && $0.value <= 0x7e }) else {
            throw KomariAPIError.invalidAPIKey
        }
        self.apiKey = apiKey
        self.transport = APITransport(configuration: configuration)
    }

    static func validatedURL(_ raw: String, allowHTTP: Bool = false) throws -> URL {
        guard !raw.isEmpty,
              !raw.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }),
              !raw.contains("\\"),
              var components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else {
            throw KomariAPIError.invalidURL
        }
        guard scheme == "https" || scheme == "http" else { throw KomariAPIError.invalidURL }
        guard scheme == "https" || allowHTTP else { throw KomariAPIError.insecureURL }
        // Reject path traversal and encoded separators rather than silently changing deployment paths.
        let encodedPath = components.percentEncodedPath.lowercased()
        guard !encodedPath.contains("%2f"), !encodedPath.contains("%5c"),
              let decodedPath = components.percentEncodedPath.removingPercentEncoding,
              !decodedPath.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == "." || $0 == ".." }),
              !decodedPath.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw KomariAPIError.invalidURL
        }
        components.scheme = scheme
        guard let url = components.url else { throw KomariAPIError.invalidURL }
        return url
    }

    /// Append relative to the deployment prefix, never replace it with a root-relative path.
    func endpoint(_ path: String, webSocket: Bool = false) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        var prefix = components.percentEncodedPath
        while prefix.hasSuffix("/") { prefix.removeLast() }
        components.percentEncodedPath = prefix + "/" + path
        if webSocket { components.scheme = components.scheme == "https" ? "wss" : "ws" }
        return components.url!
    }

    private func request(_ path: String, webSocket: Bool = false) -> URLRequest {
        var request = URLRequest(url: endpoint(path, webSocket: webSocket),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        if !apiKey.isEmpty { request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization") }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func rpc(_ method: String, params: JSON = .object([:])) async throws -> JSON {
        guard !method.isEmpty, !method.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw KomariAPIError.invalidMethod
        }
        switch params { case .object, .array: break; default: throw KomariAPIError.invalidParams }
        let id = UUID().uuidString
        var request = request("api/rpc2")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(JSON.object([
            "jsonrpc": .string("2.0"), "id": .string(id), "method": .string(method), "params": params
        ]))
        let data: Data
        let response: URLResponse
        do { (data, response) = try await transport.session.data(for: request) }
        catch { throw RequestFailure.safeTransportError(error) }
        guard let http = response as? HTTPURLResponse else { throw KomariAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw KomariAPIError.httpStatus(http.statusCode) }
        guard data.count <= Self.responseLimit,
              let decoded = try? JSONDecoder().decode(JSON.self, from: data) else { throw KomariAPIError.invalidResponse }
        return try Self.rpcResult(decoded, expectedID: id)
    }

    static func rpcResult(_ envelope: JSON, expectedID: String) throws -> JSON {
        guard case .object(let object) = envelope, object["jsonrpc"] == .string("2.0") else {
            throw KomariAPIError.invalidResponse
        }
        guard object["id"] == .string(expectedID) else { throw KomariAPIError.mismatchedID }
        // Some upstream Go versions serialize error:null beside result; tolerate that, not two outcomes.
        if let error = object["error"], error != .null {
            guard object["result"] == nil || object["result"] == .null,
                  case .object(let fields) = error,
                  case .number(let code)? = fields["code"], code.isFinite,
                  code.rounded() == code, code >= Double(Int32.min), code <= Double(Int32.max),
                  case .string? = fields["message"] else { throw KomariAPIError.invalidResponse }
            throw KomariAPIError.rpc(Int(code))
        }
        guard let result = object["result"] else { throw KomariAPIError.invalidResponse }
        return result // Explicit JSON null is a valid RPC result, unlike a missing result.
    }

    func liveSnapshot() async throws -> JSON {
        let socket = transport.session.webSocketTask(with: request("api/clients", webSocket: true))
        socket.maximumMessageSize = Self.responseLimit
        socket.resume()
        defer { socket.cancel(with: .normalClosure, reason: nil) }
        do {
            return try await withTaskCancellationHandler {
                try await withThrowingTaskGroup(of: JSON.self) { group in
                    group.addTask {
                        try await socket.send(.string("get"))
                        let message = try await socket.receive()
                        let data: Data
                        switch message {
                        case .string(let text): data = Data(text.utf8)
                        case .data(let bytes): data = bytes
                        @unknown default: throw KomariAPIError.invalidResponse
                        }
                        guard data.count <= Self.responseLimit,
                              let decoded = try? JSONDecoder().decode(JSON.self, from: data) else {
                            throw KomariAPIError.invalidResponse
                        }
                        return try Self.snapshotData(decoded)
                    }
                    group.addTask {
                        try await Task.sleep(for: .seconds(20))
                        throw KomariAPIError.timedOut
                    }
                    // Cancel the socket only after the winning result/error is chosen;
                    // otherwise a timeout can race its own URLError.cancelled.
                    defer { group.cancelAll(); socket.cancel(with: .goingAway, reason: nil) }
                    guard let result = try await group.next() else { throw KomariAPIError.invalidResponse }
                    return result
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        } catch {
            if let error = error as? KomariAPIError { throw error }
            throw RequestFailure.safeTransportError(error)
        }
    }

    static func snapshotData(_ envelope: JSON) throws -> JSON {
        guard envelope["status"] == .string("success"),
              case .object(let fields) = envelope["data"],
              case .array(let online)? = fields["online"],
              online.allSatisfy({ if case .string = $0 { return true }; return false }),
              case .object? = fields["data"] else { throw KomariAPIError.invalidResponse }
        return .object(fields) // Preserve each nested v2 report; do not flatten CPU/memory/etc.
    }

}

/// Keys are local-only and inaccessible while the device is locked. No UserDefaults fallback.
enum Keychain {
    private static let service = "KomariPanel.APIKey"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    static func save(_ key: String, account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addStatus = SecItemAdd(query(account).merging(attributes, uniquingKeysWith: { _, new in new }) as CFDictionary, nil)
            // Resolve a concurrent first-save without deleting an existing key.
            if addStatus == errSecDuplicateItem {
                try check(SecItemUpdate(query(account) as CFDictionary, attributes as CFDictionary))
            } else { try check(addStatus) }
        } else { try check(status) }
    }

    static func load(account: String) throws -> String {
        var request = query(account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        try check(status)
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainError(status: errSecDecode)
        }
        return value
    }

    static func delete(account: String) throws {
        let status = SecItemDelete(query(account) as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private static func check(_ status: OSStatus) throws {
        if status != errSecSuccess { throw KeychainError(status: status) }
    }
}

struct KeychainError: Error, LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "安全凭据存储失败（错误码 \(status))." }
}
