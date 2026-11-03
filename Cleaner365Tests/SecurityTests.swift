import XCTest
@testable import Cleaner365

final class SecurityTests: XCTestCase {
    func testPasswordGeneratorHonorsAllCombinations() {
        for mask in 0..<8 {
            let upper = mask & 1 != 0, digits = mask & 2 != 0, symbols = mask & 4 != 0
            for length in [12, 24, 64] {
                let password = PasswordGenerator.make(length: length, uppercase: upper, digits: digits, symbols: symbols)
                XCTAssertEqual(password.count, length)
                XCTAssertTrue(password.contains(where: \.isLowercase))
                XCTAssertEqual(password.contains(where: \.isUppercase), upper)
                XCTAssertEqual(password.contains(where: \.isNumber), digits)
                XCTAssertEqual(password.contains(where: { !$0.isLetter && !$0.isNumber }), symbols)
            }
        }
    }

    func testEmailOccupiesOneEncodedPathSegment() throws {
        let url = try XCTUnwrap(SecurityServices.emailLookupURL(" first+tag/box#1@example.com\n"))
        XCTAssertEqual(url.absoluteString, "https://haveibeenpwned.com/account/first%2Btag%2Fbox%231@example.com")
        XCTAssertNil(SecurityServices.emailLookupURL("missing-address"))
        XCTAssertNil(SecurityServices.emailLookupURL("bad@account@example.com"))
        XCTAssertNil(SecurityServices.emailLookupURL("name@example..com"))
        XCTAssertNil(SecurityServices.emailLookupURL("name@host/path"))
    }

    func testPasswordCheckSendsOnlyPrefixAndIgnoresPadding() async throws {
        let suffix = "1E4C9B93F3F0682250B6CF8331B7EE68FD8"
        let other = String(repeating: "A", count: 35)
        for expected in [0, 42] {
            let api = fixture { request in
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertEqual(request.url?.absoluteString, "https://api.pwnedpasswords.com/range/5BAA6")
                XCTAssertNil(request.httpBody)
                XCTAssertNil(request.value(forHTTPHeaderField: "Authentication"))
                XCTAssertEqual(request.value(forHTTPHeaderField: "Add-Padding"), "true")
                return (200, "\(other):3\r\n\(suffix):\(expected)\r\n")
            }
            let count = try await api.passwordOccurrences("password")
            XCTAssertEqual(count, expected)
        }
    }

    func testFailedAndMalformedLookupsCannotReportClean() async {
        for (status, response) in [(429, ""), (503, ""), (404, ""), (200, "<html>"), (200, "")] {
            let api = fixture { _ in (status, response) }
            do { _ = try await api.passwordOccurrences("test"); XCTFail("Expected lookup failure") }
            catch { XCTAssertTrue(error is SecurityServiceError) }
        }
    }

    func testAliasCreationAndReloadUseProviderMailboxAndKey() async throws {
        let item = #"{"id":91,"email":"relay@example.net","enabled":true,"mailboxes":[{"id":3,"email":"owner@example.org"}]}"#
        let api = fixture { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authentication"), "test-only")
            XCTAssertEqual(request.url?.host, "app.simplelogin.io")
            XCTAssertNil(request.value(forHTTPHeaderField: "Add-Padding"))
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/api/alias/random/new")
                return (201, item)
            }
            XCTAssertEqual(request.url?.absoluteString, "https://app.simplelogin.io/api/v2/aliases?page_id=0")
            return (200, #"{"aliases":["# + item + "]}")
        }
        let created = try await api.createAlias(key: "test-only")
        let listed = try await api.aliases(key: "test-only")
        XCTAssertEqual(created.id, listed.first?.id)
        XCTAssertEqual(created.mailboxes.first?.email, "owner@example.org")
    }

    func testAliasLimitAndMissingMailboxDoNotCreateSuccessfulResult() async {
        for (status, body) in [(403, "{}"), (401, "{}"), (201, #"{"id":1,"email":"x@example.com","enabled":true,"mailboxes":[]}"#)] {
            let api = fixture { _ in (status, body) }
            do { _ = try await api.createAlias(key: "test-only"); XCTFail("Unexpected provisioned alias") }
            catch { XCTAssertTrue(error is SecurityServiceError) }
        }
    }

    private func fixture(_ response: @escaping (URLRequest) -> (Int, String)) -> SecurityServices {
        let identifier = UUID().uuidString
        SecurityFixture.register(identifier, response)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [SecurityFixture.self]
        config.httpAdditionalHeaders = ["X-Test-Scenario": identifier]
        addTeardownBlock { SecurityFixture.forget(identifier) }
        return SecurityServices(session: URLSession(configuration: config))
    }
}

private final class SecurityFixture: URLProtocol {
    typealias Response = (URLRequest) -> (Int, String)
    static let lock = NSLock()
    static var responses: [String: Response] = [:]

    static func register(_ key: String, _ response: @escaping Response) {
        lock.withLock { responses[key] = response }
    }
    static func forget(_ key: String) {
        lock.withLock { responses[key] = nil }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Test-Scenario") ?? ""
        let block = Self.lock.withLock { Self.responses[key] }
        guard let url = request.url, let block else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse)); return
        }
        let (status, text) = block(request)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
