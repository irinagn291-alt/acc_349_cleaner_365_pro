import Alamofire

enum APIConfig {
    private static let host = "https://api.cleaner365gandon.site"
    private static let path = "/api/v1/users/register"

    static func apply() {
        AppConfiguration.configure(host: host, path: path)
    }
}
