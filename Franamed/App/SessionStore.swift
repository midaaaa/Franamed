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
    @Published private(set) var user: BackendUser?

    private let auth: BackendAuthServiceProtocol
    private let profile: BackendProfileServiceProtocol

    init(
        auth: BackendAuthServiceProtocol = AppFactory.makeBackend().auth,
        profile: BackendProfileServiceProtocol = AppFactory.makeBackend().profile
    ) {
        self.auth = auth
        self.profile = profile
    }

    // MARK: State

    var role: UserRole { user?.role ?? .user }

    var canModerate: Bool { role >= .moderator }

    var isAdmin: Bool { role == .admin }

    // MARK: Actions

    func start() async {
        guard user == nil else { return }

        if let signedIn = try? await auth.ensureSession() {
            user = signedIn
        } else {
            user = try? await auth.signInAnonymously()
        }
    }

    func setStatsExcluded(_ excluded: Bool) async {
        guard user != nil else { return }

        if let updated = try? await profile.setStatsExcluded(excluded) {
            user = updated
        }
    }
}
