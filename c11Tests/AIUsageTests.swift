import XCTest
@testable import c11

private func uniqueKeychainService() -> String {
    "com.stage11.c11.aiusage.tests.\(UUID().uuidString)"
}

private func uniqueIndexKey() -> String {
    "c11.aiusage.tests.\(UUID().uuidString)"
}

private func cleanupKeychain(service: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
    ]
    SecItemDelete(query as CFDictionary)
}

final class AIUsageAccountStoreRoundTripTests: XCTestCase {
    private let suiteName = "c11.aiusage.tests.\(UUID().uuidString)"
    private var defaults: UserDefaults!
    private var service: String!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        service = uniqueKeychainService()
        defaults.removePersistentDomain(forName: suiteName)
        cleanupKeychain(service: service)
    }

    override func tearDown() {
        cleanupKeychain(service: service)
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    @MainActor
    func testAddSecretUpdateRemoveRoundTrip() async throws {
        let indexKey = uniqueIndexKey()
        let store = AIUsageAccountStore(
            userDefaults: defaults,
            indexKey: indexKey,
            keychainServiceResolver: { _ in self.service }
        )
        XCTAssertTrue(store.accounts.isEmpty)

        let original = AIUsageSecret(fields: ["sessionKey": "secret-value", "orgId": "org-1"])
        try await store.add(providerId: "claude", displayName: "Personal", secret: original)
        XCTAssertEqual(store.accounts.count, 1)
        let id = store.accounts[0].id

        let loaded = try await store.secret(for: id)
        XCTAssertEqual(loaded.fields["sessionKey"], "secret-value")
        XCTAssertEqual(loaded.fields["orgId"], "org-1")

        let updated = AIUsageSecret(fields: ["sessionKey": "rotated", "orgId": "org-2"])
        try await store.update(id: id, displayName: "Work", secret: updated)
        XCTAssertEqual(store.accounts[0].displayName, "Work")
        let reloaded = try await store.secret(for: id)
        XCTAssertEqual(reloaded.fields["sessionKey"], "rotated")
        XCTAssertEqual(reloaded.fields["orgId"], "org-2")

        try await store.remove(id: id)
        XCTAssertTrue(store.accounts.isEmpty)
        do {
            _ = try await store.secret(for: id)
            XCTFail("expected notFound")
        } catch AIUsageStoreError.notFound {
            // expected
        }
    }

    @MainActor
    func testIndexPersistsAcrossInstances() async throws {
        let indexKey = uniqueIndexKey()
        let resolver: (String) -> String = { _ in self.service }
        let first = AIUsageAccountStore(
            userDefaults: defaults,
            indexKey: indexKey,
            keychainServiceResolver: resolver
        )
        let secret = AIUsageSecret(fields: ["sessionKey": "v"])
        try await first.add(providerId: "claude", displayName: "Personal", secret: secret)
        XCTAssertEqual(first.accounts.count, 1)

        let second = AIUsageAccountStore(
            userDefaults: defaults,
            indexKey: indexKey,
            keychainServiceResolver: resolver
        )
        XCTAssertEqual(second.accounts.count, 1)
        XCTAssertEqual(second.accounts[0].providerId, "claude")
        XCTAssertEqual(second.accounts[0].displayName, "Personal")

        try await second.remove(id: second.accounts[0].id)
        XCTAssertTrue(second.accounts.isEmpty)
    }
}

final class AIUsageSecretRedactionTests: XCTestCase {
    func testDescriptionElidesValues() {
        let secret = AIUsageSecret(fields: ["sessionKey": "topsecret", "orgId": "abcd-1234"])
        let description = secret.description
        XCTAssertTrue(description.contains("<redacted>"))
        XCTAssertFalse(description.contains("topsecret"))
        XCTAssertFalse(description.contains("abcd-1234"))
        XCTAssertEqual(secret.debugDescription, description)
    }

    func testDumpDoesNotLeakValues() {
        let secret = AIUsageSecret(fields: ["accessToken": "supersecret"])
        var sink = ""
        dump(secret, to: &sink)
        XCTAssertFalse(sink.contains("supersecret"))
    }

    func testStringInterpolationDoesNotLeakValues() {
        let secret = AIUsageSecret(fields: ["accessToken": "interp-secret"])
        let interpolated = "secret=\(secret)"
        XCTAssertFalse(interpolated.contains("interp-secret"))
        XCTAssertTrue(interpolated.contains("<redacted>"))
    }

    func testCodableRoundTripPreservesValues() throws {
        let secret = AIUsageSecret(fields: ["sessionKey": "codable-v"])
        let data = try JSONEncoder().encode(secret.fields)
        let decoded = try JSONDecoder().decode([String: String].self, from: data)
        XCTAssertEqual(decoded["sessionKey"], "codable-v")
    }
}
