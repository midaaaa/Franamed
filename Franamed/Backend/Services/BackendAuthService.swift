//
//  BackendAuthService.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

final class BackendAuthService: BackendAuthServiceProtocol {
    private let client: BackendAPIClient

    init(client: BackendAPIClient) {
        self.client = client
    }

    @discardableResult
    func ensureSession() async throws -> BackendUser {
        _ = try await client.tokens.validAccessToken()
        if let user = await client.tokens.user { return user }
        return try await refreshCurrentUser()
    }

    func isSignedIn() async -> Bool {
        await client.tokens.isSignedIn
    }

    func currentUser() async -> BackendUser? {
        await client.tokens.user
    }

    func refreshCurrentUser() async throws -> BackendUser {
        let user: BackendUser = try await client.get("/v1/auth/me")
        await client.tokens.updateCachedUser(user)
        return user
    }

    @discardableResult
    func signInAnonymously() async throws -> BackendUser {
        try await client.tokens.signInAnonymously()
    }

    func signInWithApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser {
        try await client.tokens.signInWithApple(identityToken: identityToken, nonce: nonce, displayName: displayName)
    }

    func linkApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser {
        struct Payload: Encodable, Sendable {
            let identityToken: String
            let nonce: String?
            let displayName: String?
        }

        let user: BackendUser = try await client.post(
            "/v1/auth/link-apple",
            body: Payload(identityToken: identityToken, nonce: nonce, displayName: displayName)
        )
        await client.tokens.updateCachedUser(user)
        return user
    }

    func signOut() async {
        let _: EmptyResponse? = try? await client.post("/v1/auth/logout")
        await client.tokens.signOut()
    }

    func forgetAccount() async {
        await client.tokens.forgetAccount()
    }
}
