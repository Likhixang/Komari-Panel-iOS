import XCTest
import Foundation
@testable import KomariPanel

final class TransportCancellationTests: XCTestCase {
    func testCancellationClassifierDoesNotHideOtherErrors() {
        XCTAssertTrue(RequestFailure.isCancellation(CancellationError()))
        XCTAssertTrue(RequestFailure.isCancellation(URLError(.cancelled)))
        XCTAssertTrue(RequestFailure.isCancellation(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)))
        XCTAssertFalse(RequestFailure.isCancellation(NSError(domain: "Other", code: NSURLErrorCancelled)))
        XCTAssertFalse(RequestFailure.isCancellation(KomariAPIError.timedOut))
        XCTAssertEqual(RequestFailure.safeTransportError(URLError(.timedOut)) as? KomariAPIError, .timedOut)
        XCTAssertEqual(RequestFailure.safeTransportError(URLError(.cannotConnectToHost)) as? KomariAPIError, .transport)
        XCTAssertEqual(RequestFailure.safeTransportError(KomariAPIError.httpStatus(401)) as? KomariAPIError, .httpStatus(401))
    }

    func testCancelledTaskDoesNotReclassifyKnownFailure() async {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return RequestFailure.safeTransportError(KomariAPIError.httpStatus(403)) as? KomariAPIError
        }
        let result = await task.value
        XCTAssertEqual(result, .httpStatus(403))
    }

    func testKomariTransportPreservesCancellationAndTimeout() async throws {
        for (host, expected) in [("cancel.example", nil), ("timeout.example", KomariAPIError.timedOut), ("offline.example", .transport)] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FailureURLProtocol.self]
            let api = try KomariAPI(baseURL: "https://" + host, apiKey: "", configuration: configuration)
            do {
                _ = try await api.rpc("admin:listClients")
                XCTFail("Expected injected transport failure")
            } catch {
                if let expected { XCTAssertEqual(error as? KomariAPIError, expected) }
                else { XCTAssertTrue(error is CancellationError) }
            }
        }
    }

    func testMonitorTransportPreservesCancellationAndTimeout() async throws {
        for (host, expected) in [("cancel.example", nil), ("timeout.example", KomariAPIError.timedOut), ("offline.example", .transport)] {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FailureURLProtocol.self]
            let api = try MonitorAPI(kind: .dstatus, address: "https://" + host, key: "", allowHTTP: false, configuration: configuration)
            do {
                _ = try await api.get("api/servers")
                XCTFail("Expected injected transport failure")
            } catch {
                if let expected { XCTAssertEqual(error as? KomariAPIError, expected) }
                else { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
}

private final class FailureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let code: URLError.Code
        switch request.url?.host {
        case "cancel.example": code = .cancelled
        case "timeout.example": code = .timedOut
        default: code = .cannotConnectToHost
        }
        client?.urlProtocol(self, didFailWithError: URLError(code))
    }
    override func stopLoading() {}
}
