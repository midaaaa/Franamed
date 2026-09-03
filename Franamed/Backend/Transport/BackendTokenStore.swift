//
//  BackendTokenStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

actor BackendTokenStore {
    private static let refreshTokenKey = "refreshToken"
    private static let signedOutKey = "backend.signedOut"
    private static let lastAccountAnonymousKey = "backend.lastAccountAnonymous"

    private let configuration: BackendConfiguration
    private let session: URLSession
    private let defaults: UserDefaults
    private let decoder: JSONDecoder

    private var accessToken: String?
    private var accessTokenExpiry: Date?
    private var currentUser: BackendUser?
    private var renewal: Task<String, Error>?

    init(configuration: BackendConfiguration, session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.configuration = configuration
        self.session = session
        self.defaults = defaults
        self.decoder = JSONDecoder()
    }

    // MARK: State

    var user: BackendUser? { currentUser }

    var isSignedOut: Bool { defaults.bool(forKey: Self.signedOutKey) }

    var hasStoredSession: Bool { KeychainStore.readString(Self.refreshTokenKey) != nil }

    var isSignedIn: Bool { hasStoredSession && !isSignedOut }

    private var lastAccountWasAnonymous: Bool {
        defaults.object(forKey: Self.lastAccountAnonymousKey) as? Bool ?? true
    }

    private var hasValidAccessToken: Bool {
        guard accessToken != nil, let expiry = accessTokenExpiry else { return false }
        return expiry.timeIntervalSinceNow > 60
    }

    // MARK: Access

    func validAccessToken() async throws -> String {
        if hasValidAccessToken, let token = accessToken { return token }

        if let renewal {
            return try await renewal.value
        }

        let task = Task<String, Error> { try await renewSession() }
        renewal = task

        defer { renewal = nil }
        return try await task.value
    }

    func invalidateAccessToken() {
        accessToken = nil
        accessTokenExpiry = nil
    }

    private func renewSession() async throws -> String {
        if isSignedOut { throw BackendError.notSignedIn }

        if let refreshToken = KeychainStore.readString(Self.refreshTokenKey) {
            do {
                return try apply(await post("/v1/auth/refresh", body: ["refreshToken": refreshToken]))
            } catch let error as BackendError where error.isCredentialRejection {
                KeychainStore.delete(Self.refreshTokenKey)
                guard lastAccountWasAnonymous else {
                    defaults.set(true, forKey: Self.signedOutKey)
                    throw BackendError.notSignedIn
                }
            }
        }

        return try apply(await anonymousSession())
    }

    // MARK: Sign in

    @discardableResult
    func signInAnonymously() async throws -> BackendUser {
        defaults.set(false, forKey: Self.signedOutKey)
        try apply(await anonymousSession())

        guard let currentUser else { throw BackendError.notSignedIn }
        return currentUser
    }

    func signInWithApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser {
        var body: [String: String] = ["identityToken": identityToken]
        if let nonce { body["nonce"] = nonce }
        if let displayName { body["displayName"] = displayName }

        defaults.set(false, forKey: Self.signedOutKey)
        try apply(await post("/v1/auth/apple", body: body))

        guard let currentUser else { throw BackendError.notSignedIn }
        return currentUser
    }

    private func anonymousSession() async throws -> AuthSession {
        try await post("/v1/auth/anonymous", body: ["deviceSecret": DeviceSecret.loadOrCreate()])
    }

    // MARK: Session lifetime

    func updateCachedUser(_ user: BackendUser) {
        currentUser = user
        defaults.set(user.isAnonymous, forKey: Self.lastAccountAnonymousKey)
    }

    func signOut() {
        KeychainStore.delete(Self.refreshTokenKey)
        defaults.set(true, forKey: Self.signedOutKey)
        accessToken = nil
        accessTokenExpiry = nil
        currentUser = nil
    }

    func forgetAccount() {
        signOut()
        DeviceSecret.reset()
        defaults.removeObject(forKey: Self.signedOutKey)
        defaults.removeObject(forKey: Self.lastAccountAnonymousKey)
    }

    @discardableResult
    private func apply(_ authSession: AuthSession) throws -> String {
        let status = KeychainStore.writeString(authSession.refreshToken, for: Self.refreshTokenKey)
        guard status == errSecSuccess else { throw BackendError.keychainFailure(status) }

        accessToken = authSession.accessToken
        accessTokenExpiry = Date().addingTimeInterval(TimeInterval(authSession.expiresIn))
        updateCachedUser(authSession.user)

        return authSession.accessToken
    }

    // MARK: Unauthenticated transport

    private func post(_ path: String, body: [String: String]) async throws -> AuthSession {
        guard let url = URL(string: configuration.apiBaseURL + path) else { throw BackendError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }

        guard (200...299).contains(http.statusCode) else {
            throw BackendAPIClient.decodeError(data: data, status: http.statusCode)
        }

        do {
            return try decoder.decode(AuthSession.self, from: data)
        } catch {
            throw BackendError.decoding(String(describing: error))
        }
    }
}
