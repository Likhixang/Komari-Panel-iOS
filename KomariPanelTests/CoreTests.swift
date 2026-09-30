import XCTest
import Foundation
@testable import KomariPanel

final class CoreTests: XCTestCase {
    func testJSONRoundTripAndTypedDefaults() throws {
        let original: JSON = .object([
            "text": .string("服务器"), "number": .number(12.5), "flag": .bool(true),
            "items": .array([.null, .bool(false), .number(0), .object(["nested": .string("yes")])])
        ])
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(JSON.self, from: data), original)
        XCTAssertEqual(original["text"].string, "服务器")
        XCTAssertEqual(original["number"].number, 12.5)
        XCTAssertTrue(original["flag"].bool)
        XCTAssertEqual(original["items"].array.count, 4)
        XCTAssertEqual(original["missing"], .null)
        XCTAssertEqual(JSON.null.string, "")
        XCTAssertEqual(JSON.null.number, 0)
        XCTAssertFalse(JSON.null.bool)
        XCTAssertTrue(JSON.null.array.isEmpty)
        XCTAssertTrue(JSON.null.object.isEmpty)
        XCTAssertEqual(JSON.from("true"), .bool(true))
        XCTAssertEqual(JSON.from("1"), .number(1))
        XCTAssertEqual(JSON.from("null"), .null)
        XCTAssertNil(JSON.from("{broken"))
    }

    func testHTTPSAndExplicitHTTPOptIn() throws {
        XCTAssertNoThrow(try KomariAPI(baseURL: "https://example.com", apiKey: ""))
        XCTAssertThrowsError(try KomariAPI(baseURL: "http://example.com", apiKey: "")) {
            XCTAssertEqual($0 as? KomariAPIError, .insecureURL)
        }
        XCTAssertNoThrow(try KomariAPI(baseURL: "http://localhost:8080/panel", apiKey: "", allowHTTP: true))
    }

    func testRejectUnsafeURLsAndHeaderInjection() {
        for url in ["", "example.com", "//example.com", "file:///etc/passwd", "wss://example.com",
                    "https://user:secret@example.com", "https://@example.com", "https://example.com?",
                    "https://example.com?key=secret", "https://example.com#", "https://example.com#fragment",
                    "https://example.com:0", "https://example.com:65536", " https://example.com",
                    "https://example.com\n", "https://example.com/../other", "https://example.com/%2e%2e/other",
                    "https://example.com/a%2fb", "https://example.com/a%5cb", "https://example.com/a%0ab"] {
            XCTAssertThrowsError(try KomariAPI(baseURL: url, apiKey: ""), url)
        }
        for key in ["key\r\nInjected: yes", "key with space", "密钥", "\u{7f}"] {
            XCTAssertThrowsError(try KomariAPI(baseURL: "https://example.com", apiKey: key)) {
                XCTAssertEqual($0 as? KomariAPIError, .invalidAPIKey)
            }
        }
    }

    func testEndpointsPreserveBasePathAndPort() throws {
        let api = try KomariAPI(baseURL: "https://example.com:8443/a%20b/panel///", apiKey: "")
        XCTAssertEqual(api.endpoint("api/rpc2").absoluteString, "https://example.com:8443/a%20b/panel/api/rpc2")
        XCTAssertEqual(api.endpoint("api/clients", webSocket: true).absoluteString,
                       "wss://example.com:8443/a%20b/panel/api/clients")
        let http = try KomariAPI(baseURL: "http://localhost/prefix", apiKey: "", allowHTTP: true)
        XCTAssertEqual(http.endpoint("api/clients", webSocket: true).scheme, "ws")
    }

    func testRPCEnvelopeValidationAndNullResult() throws {
        let valid = JSON.object(["jsonrpc": .string("2.0"), "id": .string("test"), "result": .null])
        XCTAssertEqual(try KomariAPI.rpcResult(valid, expectedID: "test"), .null)
        XCTAssertThrowsError(try KomariAPI.rpcResult(valid, expectedID: "other")) {
            XCTAssertEqual($0 as? KomariAPIError, .mismatchedID)
        }
        let missing = JSON.object(["jsonrpc": .string("2.0"), "id": .string("test")])
        XCTAssertThrowsError(try KomariAPI.rpcResult(missing, expectedID: "test"))
        let failed = JSON.object(["jsonrpc": .string("2.0"), "id": .string("test"),
                                  "error": .object(["code": .number(-32601), "message": .string("secret")])])
        XCTAssertThrowsError(try KomariAPI.rpcResult(failed, expectedID: "test")) {
            XCTAssertEqual($0 as? KomariAPIError, .rpc(-32601))
            XCTAssertFalse($0.localizedDescription.contains("secret"))
        }
        var fields = failed.object
        fields["result"] = .string("ambiguous")
        XCTAssertThrowsError(try KomariAPI.rpcResult(.object(fields), expectedID: "test"))
        fields = valid.object
        fields["error"] = .null
        XCTAssertEqual(try KomariAPI.rpcResult(.object(fields), expectedID: "test"), .null)
        fields["jsonrpc"] = .string("1.0")
        XCTAssertThrowsError(try KomariAPI.rpcResult(.object(fields), expectedID: "test"))
    }

    func testSnapshotUnwrapsEnvelopeWithoutFlatteningReport() throws {
        let report: JSON = .object(["cpu": .object(["usage": .number(42)]), "memory": .object(["used": .number(1024)])])
        let payload: JSON = .object(["online": .array([.string("node")]), "data": .object(["node": report])])
        let envelope: JSON = .object(["status": .string("success"), "data": payload])
        XCTAssertEqual(try KomariAPI.snapshotData(envelope), payload)
        XCTAssertEqual(try KomariAPI.snapshotData(envelope)["data"]["node"]["cpu"]["usage"].number, 42)
        XCTAssertThrowsError(try KomariAPI.snapshotData(.object(["status": .string("error"), "data": payload])))
        XCTAssertThrowsError(try KomariAPI.snapshotData(.object(["status": .string("success"), "data": .object([:])])) )
    }

    func testMockedRPCRequestAndResponse() async throws {
        let api = try mockedAPI()
        RPCMockProtocol.state.set { request in
            guard request.url?.absoluteString == "https://example.com/prefix/api/rpc2",
                  request.httpMethod == "POST",
                  request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key",
                  request.value(forHTTPHeaderField: "Content-Type") == "application/json" else {
                throw URLError(.badURL)
            }
            let body = try Self.requestJSON(request)
            guard body["jsonrpc"] == .string("2.0"), body["method"] == .string("public:getVersion"),
                  body["params"] == .object([:]), !body["id"].string.isEmpty else { throw URLError(.badServerResponse) }
            return (200, try JSONEncoder().encode(JSON.object([
                "jsonrpc": .string("2.0"), "id": body["id"], "result": .object(["version": .string("tested")])
            ])))
        }
        defer { RPCMockProtocol.state.set(nil) }
        let result = try await api.rpc("public:getVersion")
        XCTAssertEqual(result["version"].string, "tested")
    }

    func testMockedRPCNullHTTPAndMismatchedID() async throws {
        let api = try mockedAPI()
        defer { RPCMockProtocol.state.set(nil) }
        RPCMockProtocol.state.set { request in
            let body = try Self.requestJSON(request)
            return (200, try JSONEncoder().encode(JSON.object([
                "jsonrpc": .string("2.0"), "id": body["id"], "result": .null
            ])))
        }
        let result = try await api.rpc("public:getVersion")
        XCTAssertEqual(result, .null)
        RPCMockProtocol.state.set { _ in (401, Data("credential echo".utf8)) }
        do { _ = try await api.rpc("public:getVersion"); XCTFail("Expected HTTP error") }
        catch { XCTAssertEqual(error as? KomariAPIError, .httpStatus(401)) }
        RPCMockProtocol.state.set { _ in
            (200, Data(#"{"jsonrpc":"2.0","id":"wrong","result":null}"#.utf8))
        }
        do { _ = try await api.rpc("public:getVersion"); XCTFail("Expected ID error") }
        catch { XCTAssertEqual(error as? KomariAPIError, .mismatchedID) }
        RPCMockProtocol.state.set { _ in (200, Data("not JSON".utf8)) }
        do { _ = try await api.rpc("public:getVersion"); XCTFail("Expected parsing error") }
        catch { XCTAssertEqual(error as? KomariAPIError, .invalidResponse) }
    }

    func testRedirectDelegateRefusesCredentialForwarding() throws {
        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://example.com")!
        let response = HTTPURLResponse(url: original, statusCode: 302, httpVersion: nil,
                                       headerFields: ["Location": "https://attacker.example"])!
        let task = session.dataTask(with: original)
        var redirected = URLRequest(url: URL(string: "https://attacker.example")!)
        redirected.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        let completed = expectation(description: "Redirect refused")
        delegate.urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: redirected) {
            XCTAssertNil($0)
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
    }

    func testKeychainRoundTripUpdateAndDelete() throws {
        let account = "unit-test-" + UUID().uuidString
        defer { try? Keychain.delete(account: account) }
        XCTAssertEqual(try Keychain.load(account: account), "")
        try Keychain.save("first", account: account)
        XCTAssertEqual(try Keychain.load(account: account), "first")
        try Keychain.save("second", account: account)
        XCTAssertEqual(try Keychain.load(account: account), "second")
        try Keychain.delete(account: account)
        XCTAssertEqual(try Keychain.load(account: account), "")
        XCTAssertNoThrow(try Keychain.delete(account: account))
    }

    private func mockedAPI() throws -> KomariAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RPCMockProtocol.self]
        return try KomariAPI(baseURL: "https://example.com/prefix", apiKey: "test-key", configuration: configuration)
    }

    private static func requestJSON(_ request: URLRequest) throws -> JSON {
        if let body = request.httpBody { return try JSONDecoder().decode(JSON.self, from: body) }
        guard let stream = request.httpBodyStream else { throw URLError(.badServerResponse) }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 { throw URLError(.cannotDecodeContentData) }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return try JSONDecoder().decode(JSON.self, from: data)
    }
}

private final class MockState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private let lock = NSLock()
    private var handler: Handler?
    func set(_ handler: Handler?) { lock.lock(); defer { lock.unlock() }; self.handler = handler }
    func get() -> Handler? { lock.lock(); defer { lock.unlock() }; return handler }
}

private final class RPCMockProtocol: URLProtocol, @unchecked Sendable {
    static let state = MockState()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "example.com" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.state.get(), let url = request.url else { throw URLError(.unsupportedURL) }
            let (status, data) = try handler(request)
            guard let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1",
                                                 headerFields: ["Content-Type": "application/json"]) else {
                throw URLError(.badServerResponse)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
