import Foundation

struct FaxAPI {
    static let baseURL = URL(string: "https://faxandscan-api.fly.dev")!

    struct Fax: Decodable {
        let id: String
        let to: String
        let pages: Int
        let status: String
        let failureMessage: String?
    }

    struct SendResponse: Decodable {
        let fax: Fax
        let pagesUsed: Int
        let pageLimit: Int
    }

    struct Usage: Decodable {
        let pagesUsed: Int
        let pageLimit: Int
    }

    struct APIError: LocalizedError, Decodable {
        let code: String
        let message: String
        var errorDescription: String? { message }

        var needsSubscription: Bool {
            ["subscription_required", "subscription_expired", "invalid_transaction"].contains(code)
        }
    }

    private struct ErrorEnvelope: Decodable { let error: APIError }
    private struct FaxEnvelope: Decodable { let fax: Fax }

    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        return URLSession(configuration: configuration)
    }()

    func send(pdf: URL, to number: String, transaction: String) async throws -> SendResponse {
        let boundary = "FaxScan-\(UUID().uuidString)"
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("to", number)
        field("transaction", transaction)
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"fax.pdf\"\r\nContent-Type: application/pdf\r\n\r\n")
        body.append(try Data(contentsOf: pdf))
        body.append("\r\n--\(boundary)--\r\n")

        var request = request(path: "/v1/faxes", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.upload(for: request, from: body)
        return try decode(SendResponse.self, data: data, response: response)
    }

    func status(of serverID: String) async throws -> Fax {
        let (data, response) = try await session.data(for: request(path: "/v1/faxes/\(serverID)", method: "GET"))
        return try decode(FaxEnvelope.self, data: data, response: response).fax
    }

    func usage(transaction: String) async throws -> Usage {
        var request = request(path: "/v1/usage", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["transaction": transaction])
        let (data, response) = try await session.data(for: request)
        return try decode(Usage.self, data: data, response: response)
    }

    private func request(path: String, method: String) -> URLRequest {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue(DeviceID.current.uuidString.lowercased(), forHTTPHeaderField: "X-Device-Id")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func decode<T: Decodable>(_ type: T.Type, data: Data, response: URLResponse) throws -> T {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if (200..<300).contains(status) {
            return try JSONDecoder().decode(T.self, from: data)
        }
        if let envelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data) {
            throw envelope.error
        }
        throw APIError(code: "http_\(status)", message: "Something went wrong (\(status)). Please try again.")
    }
}

private extension Data {
    mutating func append(_ string: String) { append(Data(string.utf8)) }
}

extension Error {
    /// A short message for alerts, with a clearer text for common network failures.
    var friendlyMessage: String {
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "You're offline. Connect to the internet and try again."
            case .timedOut:
                return "The connection timed out. Please try again."
            default:
                return "Couldn't reach the fax service. Please try again."
            }
        }
        return localizedDescription
    }
}
