//
//  BackendAuthServiceProtocol.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

protocol BackendAuthServiceProtocol: Sendable {
    @discardableResult
    func ensureSession() async throws -> BackendUser

    func isSignedIn() async -> Bool
    func currentUser() async -> BackendUser?
    func refreshCurrentUser() async throws -> BackendUser

    @discardableResult
    func signInAnonymously() async throws -> BackendUser
    func signInWithApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser
    func linkApple(identityToken: String, nonce: String?, displayName: String?) async throws -> BackendUser

    func signOut() async
    func forgetAccount() async
}
