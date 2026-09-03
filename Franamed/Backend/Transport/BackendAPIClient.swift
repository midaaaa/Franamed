//
//  BackendAPIClient.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendAPIClient: Sendable {
    let configuration: BackendConfiguration
    private let session: URLSession
    private let tokenStore: BackendTokenStore
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(configuration: BackendConfiguration = .default, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
        self.tokenStore = BackendTokenStore(configuration: configuration, session: session)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    var tokens: BackendTokenStore { tokenStore }

    // MARK: Requests

    func get<Response: Decodable & Sendable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(path: path, method: "GET", query: query, body: Optional<Empty>.none)
    }

    func post<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: "POST", query: [], body: body)
    }

    func post<Response: Decodable & Sendable>(_ path: String) async throws -> Response {
        try await send(path: path, method: "POST", query: [], body: Optional<Empty>.none)
    }

    func patch<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: "PATCH", query: [], body: body)
    }

    func put<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ path: String,
        body: Body
    ) async throws -> Response {
        try await send(path: path, method: "PUT", query: [], body: body)
    }

    func delete(_ path: String, query: [URLQueryItem] = []) async throws {
        let _: EmptyResponse = try await send(path: path, method: "DELETE", query: query, body: Optional<Empty>.none)
    }

    // MARK: Engine

    private func send<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        path: String,
        method: String,
        query: [URLQueryItem],
        body: Body?,
        isRetry: Bool = false
    ) async throws -> Response {
        guard var components = URLComponents(string: configuration.apiBaseURL + path) else {
            throw BackendError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw BackendError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(try await tokenStore.validAccessToken())", forHTTPHeaderField: "Authorization")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }

        if http.statusCode == 401 && !isRetry {
            await tokenStore.invalidateAccessToken()
            return try await send(path: path, method: method, query: query, body: body, isRetry: true)
        }

        guard (200...299).contains(http.statusCode) else {
            throw Self.decodeError(data: data, status: http.statusCode)
        }

        if data.isEmpty || Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
            return empty
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }

    static func decodeError(data: Data, status: Int) -> BackendError {
        struct ErrorBody: Decodable {
            let error: String?
            let message: String?
        }

        let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
        return .api(
            status: status,
            code: body?.error ?? "http_\(status)",
            message: body?.message ?? "Запрос завершился с кодом \(status)"
        )
    }
}

struct Empty: Codable, Sendable {}

struct EmptyResponse: Codable, Sendable {}
