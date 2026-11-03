import UIKit
import Alamofire

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static let bind = "app.cleaner365.iphone"
    private let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        _ = Self.bind
        APIConfig.apply()
        RegistrationSession.install()
        return notificationDelegate.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}

final class RegistrationSession: URLProtocol, @unchecked Sendable {
    private static let handled = "RegistrationSession.handled"
    private static let storageKey = "rs.jar.v1"
    private var loader: URLSession?
    private var loaderTask: URLSessionDataTask?

    static func install() {
        URLProtocol.registerClass(RegistrationSession.self)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handled, in: request) == nil else { return false }
        return request.url?.path == "/api/v1/users/register"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let urlRequest = (request as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        URLProtocol.setProperty(true, forKey: Self.handled, in: urlRequest)
        if urlRequest.value(forHTTPHeaderField: "Cookie") == nil, let header = Self.saved() {
            urlRequest.setValue(header, forHTTPHeaderField: "Cookie")
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = []
        let session = URLSession(configuration: config)
        self.loader = session
        let client = self.client
        let task = session.dataTask(with: urlRequest as URLRequest) { data, response, error in
            defer {
                self.loaderTask = nil
                self.loader = nil
            }
            if let error {
                client?.urlProtocol(self, didFailWithError: error)
                return
            }
            guard let response else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            if let http = response as? HTTPURLResponse {
                Self.store(http)
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data, !data.isEmpty {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        self.loaderTask = task
        task.resume()
    }

    override func stopLoading() {
        loaderTask?.cancel()
        loader?.invalidateAndCancel()
    }

    private static func saved() -> String? {
        let value = UserDefaults.standard.string(forKey: storageKey) ?? ""
        return value.isEmpty ? nil : value
    }

    private static func store(_ response: HTTPURLResponse) {
        guard let url = response.url else { return }
        var headers: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let name = key as? String, let header = value as? String else { continue }
            headers[name] = header
        }
        let pairs = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).map {
            "\($0.name)=\($0.value)"
        }
        guard !pairs.isEmpty else { return }
        UserDefaults.standard.set(pairs.joined(separator: "; "), forKey: storageKey)
    }
}
