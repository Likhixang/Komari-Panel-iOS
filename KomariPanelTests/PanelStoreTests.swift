import XCTest
@testable import KomariPanel

/// Continuations intentionally ignore cancellation: even a late successful transport
/// must not be allowed to publish into a newer request's state.
@MainActor private final class PendingPanelRequests {
    var pending: [CheckedContinuation<BackendSnapshot, Error>] = []
    func next() async throws -> BackendSnapshot {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func waitForCount(_ count: Int) async {
        for _ in 0..<1_000 {
            if pending.count >= count { return }
            await Task.yield()
        }
        XCTFail("Request did not reach its suspension point")
    }
    func finish(_ index: Int, _ result: Result<BackendSnapshot, Error>) {
        pending[index].resume(with: result)
    }
}

final class PanelStoreTests: XCTestCase {
    @MainActor private func makeStore(_ requests: PendingPanelRequests) -> PanelStore {
        let defaults = UserDefaults(suiteName: "PanelStoreTests-" + UUID().uuidString)!
        let store = PanelStore(defaults: defaults, makeConnection: { _ in
            PanelConnection(load: { try await requests.next() }, refresh: { try await requests.next() })
        })
        store.panels = [Panel(id: "A", name: "A", address: "https://a.example"),
                        Panel(id: "B", name: "B", address: "https://b.example")]
        store.selected = "A"
        return store
    }
    private func snapshot(_ value: String) -> BackendSnapshot {
        BackendSnapshot(nodes: [.object(["uuid": .string(value)])], statuses: .object(["value": .string(value)]))
    }

    @MainActor func testAlreadyCancelledConnectDoesNotResetCurrentState() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        store.nodes = snapshot("existing").nodes
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await store.connect()
        }
        await task.value
        XCTAssertNil(store.error)
        XCTAssertEqual(store.nodes.first?["uuid"], .string("existing"))
        XCTAssertTrue(requests.pending.isEmpty)
    }

    @MainActor func testCancelledRefreshLateSuccessCannotReplaceSnapshot() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let connect = Task { await store.connect() }
        await requests.waitForCount(1)
        requests.finish(0, .success(snapshot("good")))
        await connect.value
        let updated = store.updated
        let refresh = Task { await store.refresh() }
        await requests.waitForCount(2)
        refresh.cancel()
        requests.finish(1, .success(snapshot("cancelled")))
        await refresh.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("good"))
        XCTAssertEqual(store.updated, updated)
        XCTAssertNil(store.error)
    }

    @MainActor func testRefreshRecoversCancelledInitialConnectionWithoutDuplicates() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let initial = Task { await store.connect() }
        await requests.waitForCount(1)
        initial.cancel()
        requests.finish(0, .failure(CancellationError()))
        await initial.value
        let recover = Task { await store.refresh() }
        await requests.waitForCount(2)
        await store.refresh() // Active recovery already owns loading; do not reconnect.
        XCTAssertEqual(requests.pending.count, 2)
        requests.finish(1, .success(snapshot("recovered")))
        await recover.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("recovered"))
        XCTAssertFalse(store.loading)
        XCTAssertNil(store.error)
    }

    @MainActor func testCancelledReconnectRetainsLastGoodConnectionAndSnapshot() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let initial = Task { await store.connect() }
        await requests.waitForCount(1)
        requests.finish(0, .success(snapshot("good")))
        await initial.value
        let updated = store.updated
        let reconnect = Task { await store.connect() }
        await requests.waitForCount(2)
        XCTAssertEqual(store.nodes.first?["uuid"], .string("good"))
        await store.refresh() // A poll cannot compete with the reconnect.
        XCTAssertEqual(requests.pending.count, 2)
        reconnect.cancel()
        requests.finish(1, .failure(CancellationError()))
        await reconnect.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("good"))
        XCTAssertEqual(store.updated, updated)
        XCTAssertNil(store.error)
        let refresh = Task { await store.refresh() }
        await requests.waitForCount(3)
        requests.finish(2, .success(snapshot("refreshed")))
        await refresh.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("refreshed"))
    }

    @MainActor func testCancelledConnectDoesNotPublishSuccessOrError() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let task = Task { await store.connect() }
        await requests.waitForCount(1)
        task.cancel()
        requests.finish(0, .success(snapshot("cancelled")))
        await task.value
        XCTAssertNil(store.error)
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertNil(store.updated)
        XCTAssertFalse(store.loading)
    }

    @MainActor func testCancellationErrorsAreNotDisplayedButRealErrorsAre() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let errors: [Error] = [CancellationError(), URLError(.cancelled), KomariAPIError.httpStatus(401), KomariAPIError.timedOut]
        for (index, error) in errors.enumerated() {
            let task = Task { await store.connect() }
            await requests.waitForCount(index + 1)
            requests.finish(index, .failure(error))
            await task.value
            if index < 2 { XCTAssertNil(store.error) }
            else { XCTAssertEqual(store.error, error.localizedDescription) }
            XCTAssertFalse(store.loading)
        }
    }

    @MainActor func testOlderSamePanelConnectCannotClearLoadingOrPublishError() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let old = Task { await store.connect() }
        await requests.waitForCount(1)
        let new = Task { await store.connect() }
        await requests.waitForCount(2)
        requests.finish(0, .failure(KomariAPIError.httpStatus(500)))
        await old.value
        XCTAssertTrue(store.loading)
        XCTAssertNil(store.error)
        requests.finish(1, .success(snapshot("new")))
        await new.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("new"))
        XCTAssertFalse(store.loading)
    }

    @MainActor func testSamePanelLateSuccessCannotOverwriteNewConnection() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let old = Task { await store.connect() }
        await requests.waitForCount(1)
        let new = Task { await store.connect() }
        await requests.waitForCount(2)
        requests.finish(1, .success(snapshot("new")))
        await new.value
        let updated = store.updated
        requests.finish(0, .success(snapshot("old")))
        await old.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("new"))
        XCTAssertEqual(store.updated, updated)
    }

    @MainActor func testPanelRoundTripInvalidatesBeforeNextConnectStarts() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let old = Task { await store.connect() }
        await requests.waitForCount(1)
        store.selected = "B"
        store.selected = "A"
        requests.finish(0, .success(snapshot("old-A")))
        await old.value
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertNil(store.updated)
        XCTAssertFalse(store.loading)
    }

    @MainActor func testEditingSelectedPanelInvalidatesInFlightConnection() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let task = Task { await store.connect() }
        await requests.waitForCount(1)
        store.panels[0].address = "https://changed.example"
        requests.finish(0, .success(snapshot("old-address")))
        await task.value
        XCTAssertTrue(store.nodes.isEmpty)
        XCTAssertNil(store.updated)
    }

    @MainActor func testCancelledRefreshPreservesLastGoodSnapshotAndTimestamp() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let connect = Task { await store.connect() }
        await requests.waitForCount(1)
        requests.finish(0, .success(snapshot("good")))
        await connect.value
        let updated = store.updated
        let refresh = Task { await store.refresh() }
        await requests.waitForCount(2)
        refresh.cancel()
        requests.finish(1, .failure(CancellationError()))
        await refresh.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("good"))
        XCTAssertEqual(store.updated, updated)
        XCTAssertNil(store.error)
    }

    @MainActor func testRefreshOrderingAndGenuineFailure() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let connect = Task { await store.connect() }
        await requests.waitForCount(1)
        requests.finish(0, .success(snapshot("initial")))
        await connect.value
        let old = Task { await store.refresh() }
        await requests.waitForCount(2)
        let new = Task { await store.refresh() }
        await requests.waitForCount(3)
        requests.finish(2, .success(snapshot("new")))
        await new.value
        requests.finish(1, .failure(KomariAPIError.transport))
        await old.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("new"))
        XCTAssertNil(store.error)
        XCTAssertNotNil(store.updated)
        let failed = Task { await store.refresh() }
        await requests.waitForCount(4)
        requests.finish(3, .failure(KomariAPIError.httpStatus(503)))
        await failed.value
        XCTAssertEqual(store.error, KomariAPIError.httpStatus(503).localizedDescription)
        XCTAssertNil(store.updated)
    }

    @MainActor func testReconnectInvalidatesPendingRefresh() async {
        let requests = PendingPanelRequests(), store = makeStore(requests)
        let connect = Task { await store.connect() }
        await requests.waitForCount(1)
        requests.finish(0, .success(snapshot("initial")))
        await connect.value
        let refresh = Task { await store.refresh() }
        await requests.waitForCount(2)
        let reconnect = Task { await store.connect() }
        await requests.waitForCount(3)
        requests.finish(2, .success(snapshot("reconnected")))
        await reconnect.value
        requests.finish(1, .success(snapshot("old-refresh")))
        await refresh.value
        XCTAssertEqual(store.nodes.first?["uuid"], .string("reconnected"))
    }
}
