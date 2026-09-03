//
//  SessionStore.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    enum State {
        case loading
        case signedOut
        case signedIn(BackendUser)
        case failed(String)
    }

    @Published private(set) var state: State = .loading

    private let auth: BackendAuthServiceProtocol

    init(auth: BackendAuthServiceProtocol = AppFactory.makeBackend().auth) {
        self.auth = auth
    }

    // MARK: State

    var user: BackendUser? {
        if case let .signedIn(user) = state { return user }
        return nil
    }

    var role: UserRole { user?.role ?? .user }

    var canModerate: Bool { role >= .moderator }

    var isAdmin: Bool { role == .admin }

    // MARK: Actions

    func start() async {
        switch state {
        case .signedIn: return
        default: break
        }

        state = .loading

        do {
            state = .signedIn(try await auth.ensureSession())
        } catch let error as BackendError where error.isNotSignedIn {
            state = .signedOut
        } catch {
            state = .failed(message(for: error))
        }
    }

    func signInAnonymously() async {
        state = .loading

        do {
            state = .signedIn(try await auth.signInAnonymously())
        } catch {
            state = .failed(message(for: error))
        }
    }

    func refreshUser() async {
        guard case .signedIn = state else { return }

        if let user = try? await auth.refreshCurrentUser() {
            state = .signedIn(user)
        }
    }

    func signOut() async {
        await auth.signOut()
        state = .signedOut
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
