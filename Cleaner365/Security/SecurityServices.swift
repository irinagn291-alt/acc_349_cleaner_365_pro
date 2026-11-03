import CryptoKit
import Foundation

enum PasswordGenerator {
    static let lengths = 12...64
    static func make(length: Int, uppercase: Bool, digits: Bool, symbols: Bool) -> String {
        var groups = [Array("abcdefghijklmnopqrstuvwxyz")]
        if uppercase { groups.append(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")) }
        if digits { groups.append(Array("0123456789")) }
        if symbols { groups.append(Array("!#$%&()*+,-./:;=?@[]^_{|}~")) }
        let alphabet = groups.flatMap { $0 }
        let size = min(max(length, lengths.lowerBound), lengths.upperBound)
        var random = SystemRandomNumberGenerator()
        // Reject whole candidates so every valid password is equally likely.
        while true {
            let candidate = (0..<size).map { _ in alphabet.randomElement(using: &random)! }
            let used = Set(candidate)
            if groups.allSatisfy({ !used.isDisjoint(with: $0) }) { return String(candidate) }
        }
    }
}

enum SecurityServiceError: Error, LocalizedError {
    case invalidResponse, invalidKey, aliasUnavailable, offline, storage
    case rateLimited(Int?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The service returned an unexpected response. Try again."
        case .invalidKey: return "SimpleLogin rejected this key. Connect with a current personal API key."
        case .aliasUnavailable: return "SimpleLogin could not create this alias. Check your account’s alias limit and mailbox settings."
        case .offline: return "Could not reach the service. Check your connection and try again."
        case .storage: return "Could not access the key on this iPhone. Unlock the device and try again."
        case .rateLimited(let seconds):
            if let seconds { return "Too many requests. Try again in \(seconds) seconds." }
            return "Too many requests. Please try again later."
        }
    }
}

private final class NoSecurityRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct SecurityServices {
    static let live: Self = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.timeoutIntervalForRequest = 20
        return Self(session: URLSession(configuration: configuration, delegate: NoSecurityRedirects(), delegateQueue: nil))
    }()
    let session: URLSession

    static func emailLookupURL(_ input: String) -> URL? {
        let address = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.components(separatedBy: "@")
        guard parts.count == 2, !parts[0].isEmpty, parts[0].utf8.count <= 64,
              address.utf8.count <= 254, !address.contains(where: { $0.isWhitespace || $0.isNewline }),
              address.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
        let labels = parts[1].components(separatedBy: ".")
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-" &&
            label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return nil }
        // Encode a single path segment, including +, /, #, % and ? in an address.
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~@")
        guard let segment = address.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "https://haveibeenpwned.com/account/" + segment)
    }

    func passwordOccurrences(_ password: String) async throws -> Int {
        guard !password.isEmpty else { throw SecurityServiceError.invalidResponse }
        let digest = Insecure.SHA1.hash(data: Data(password.utf8)).map { String(format: "%02X", $0) }.joined()
        var request = URLRequest(url: URL(string: "https://api.pwnedpasswords.com/range/" + digest.prefix(5))!)
        request.setValue("true", forHTTPHeaderField: "Add-Padding")
        let data = try await send(request, expecting: 200)
        guard let text = String(data: data, encoding: .utf8) else { throw SecurityServiceError.invalidResponse }
        let lines = text.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { throw SecurityServiceError.invalidResponse }
        let suffix = digest.dropFirst(5)
        var occurrences = 0
        for line in lines {
            let pair = line.split(separator: ":", omittingEmptySubsequences: false)
            guard pair.count == 2, pair[0].utf8.count == 35, pair[0].allSatisfy(\.isHexDigit),
                  let count = Int(pair[1]), count >= 0 else { throw SecurityServiceError.invalidResponse }
            if pair[0].uppercased() == suffix { occurrences = count }
        }
        return occurrences
    }

    func aliases(key: String, page: Int = 0) async throws -> [ForwardingAlias] {
        let request = aliasRequest("v2/aliases?page_id=\(page)", key: key)
        let data = try await send(request, expecting: 200)
        struct Page: Decodable { let aliases: [ForwardingAlias] }
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else { throw SecurityServiceError.invalidResponse }
        return page.aliases
    }

    func createAlias(key: String) async throws -> ForwardingAlias {
        var request = aliasRequest("alias/random/new", key: key)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"note":"Created in Cleaner 365"}"#.utf8)
        let data = try await send(request, expecting: 201)
        guard let alias = try? JSONDecoder().decode(ForwardingAlias.self, from: data),
              alias.enabled, !alias.mailboxes.isEmpty else { throw SecurityServiceError.invalidResponse }
        return alias
    }

    private func aliasRequest(_ route: String, key: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://app.simplelogin.io/api/" + route)!)
        request.setValue(key, forHTTPHeaderField: "Authentication")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send(_ request: URLRequest, expecting success: Int) async throws -> Data {
        var request = request
        request.setValue("Cleaner365-iOS", forHTTPHeaderField: "User-Agent")
        let result: (Data, URLResponse)
        do { result = try await session.data(for: request) }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw SecurityServiceError.offline
        }
        guard let http = result.1 as? HTTPURLResponse else { throw SecurityServiceError.invalidResponse }
        if http.statusCode == success { return result.0 }
        if http.statusCode == 429 {
            throw SecurityServiceError.rateLimited(http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init))
        }
        if request.url?.host == "app.simplelogin.io" {
            if http.statusCode == 401 { throw SecurityServiceError.invalidKey }
            if request.httpMethod == "POST", [400, 402, 403, 409, 422].contains(http.statusCode) { throw SecurityServiceError.aliasUnavailable }
        }
        throw SecurityServiceError.invalidResponse
    }
}

struct ForwardingAlias: Identifiable, Decodable {
    struct Mailbox: Decodable { let email: String }
    let id: Int
    let email: String
    let enabled: Bool
    let mailboxes: [Mailbox]
}
