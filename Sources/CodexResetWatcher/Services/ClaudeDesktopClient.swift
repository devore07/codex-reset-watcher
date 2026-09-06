import ClaudeUsageCore
import Foundation

struct ClaudeDesktopResult: Sendable {
    let report: ClaudeUsageReport
    let fingerprint: Data
}

struct ClaudeDesktopClient: Sendable {
    var credentials = ClaudeDesktopCredentials()
    var perform: @Sendable (URLRequest) async throws -> (Data, URLResponse) = {
        try await session.data(for: $0)
    }
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration, delegate: ClaudeNoRedirects(), delegateQueue: nil)
    }()

    func fetch(session suppliedSession: ClaudeDesktopSession? = nil, allowInteraction: Bool = false) async throws -> ClaudeDesktopResult {
        let auth = try suppliedSession ?? credentials.load(allowInteraction: allowInteraction)
        let endpoint = Self.endpoint(organization: auth.organization)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("sessionKey=\(auth.sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await perform(request)
        guard let http = response as? HTTPURLResponse, http.url == endpoint else { throw ClaudeDesktopError.invalidResponse }
        switch http.statusCode {
        case 200...299: break
        case 401, 403: throw ClaudeDesktopError.loginRejected
        case 429: throw ClaudeDesktopError.rateLimited
        default: throw ClaudeDesktopError.serverUnavailable
        }
        guard data.count <= 65_536,
            http.value(forHTTPHeaderField: "Content-Type")?.lowercased().contains("application/json") == true
        else {
            throw ClaudeDesktopError.invalidResponse
        }
        let report = try Self.decode(data)
        // Discard a response if Desktop switched organizations or sessions during the request.
        guard try credentials.load().fingerprint == auth.fingerprint else { throw ClaudeDesktopError.accountChanged }
        return ClaudeDesktopResult(report: report, fingerprint: auth.fingerprint)
    }

    static func endpoint(organization: UUID) -> URL {
        URL(string: "https://claude.ai/api/organizations/\(organization.uuidString.lowercased())/usage")!
    }

    static func decode(_ data: Data, now: Date = Date()) throws -> ClaudeUsageReport {
        struct Window: Decodable {
            let value: ClaudeUsageWindow
            enum CodingKeys: String, CodingKey {
                case utilization
                case resetsAt = "resets_at"
            }
            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                let reset = try? values.decode(String.self, forKey: .resetsAt)
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var date = reset.flatMap(formatter.date(from:))
                if date == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    date = reset.flatMap(formatter.date(from:))
                }
                value = ClaudeUsageWindow(
                    usedPercentage: try? values.decode(Double.self, forKey: .utilization),
                    resetsAt: date?.timeIntervalSince1970)
            }
        }
        struct Envelope: Decodable {
            let five: Window?
            let seven: Window?
            enum CodingKeys: String, CodingKey {
                case five = "five_hour"
                case seven = "seven_day"
            }
            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                five = try? values.decode(Window.self, forKey: .five)
                seven = try? values.decode(Window.self, forKey: .seven)
            }
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            let report = ClaudeUsageReport(receivedAt: now, fiveHour: envelope.five?.value, sevenDay: envelope.seven?.value)
            guard report.hasUsage else { throw ClaudeDesktopError.invalidResponse }
            return report
        } catch { throw ClaudeDesktopError.invalidResponse }
    }
}

private final class ClaudeNoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum ClaudeDesktopError: LocalizedError, Equatable {
    case loginUnavailable, keychainAccess, cookieFormat, loginRejected, rateLimited, serverUnavailable, invalidResponse, accountChanged
    var errorDescription: String? {
        switch self {
        case .loginUnavailable: "Open Claude Desktop and sign in, then reconnect. Its saved login could not be read."
        case .keychainAccess: "Claude Keychain access is needed. Click Reconnect Desktop to allow access when macOS asks."
        case .cookieFormat: "Claude Desktop's saved login format is unsupported. Try the terminal feed instead."
        case .loginRejected: "Claude rejected this usage request. Open Claude Desktop and check your login."
        case .rateLimited: "Claude limited usage checks. Automatic checks will wait 15 minutes before retrying."
        case .serverUnavailable: "Claude usage is temporarily unavailable. Try again later."
        case .invalidResponse: "Claude returned no usable subscription limits. Its internal usage interface may have changed."
        case .accountChanged: "Claude Desktop's login changed during refresh. Refresh again for the current subscription."
        }
    }
}
