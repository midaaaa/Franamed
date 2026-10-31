import Foundation
import Testing
@testable import PvPBackend

@Suite(.serialized)
struct BackendPvPServiceTests {
    let server: FakeServer
    let service: BackendPvPService

    init() throws {
        server = try FakeServer()
        let client = BackendAPIClient(configuration: BackendConfiguration(apiBaseURL: server.baseURL, imageBaseURL: ""))
        service = BackendPvPService(client: client)
    }

    @Test func readsAndUpdatesProfile() async throws {
        let generated = try await service.profile()
        #expect(!generated.customName)
        #expect(!generated.name.isEmpty)

        let named = try await service.updateProfile(PvPProfileUpdate(name: "SilentFoley"))
        #expect(named.name == "SilentFoley")
        #expect(named.customName)
        #expect(named.uid == generated.uid)
    }

    @Test func goesBackToTheGeneratedName() async throws {
        let generated = try await service.profile()
        _ = try await service.updateProfile(PvPProfileUpdate(name: "SilentFoley", icon: "popcorn"))
        let reset = try await service.updateProfile(PvPProfileUpdate(generatedName: true))
        #expect(reset.name == generated.name)
        #expect(!reset.customName)
        #expect(reset.icon == "popcorn")
    }

    @Test func encodesAnExplicitNullName() throws {
        let data = try JSONEncoder().encode(PvPProfileUpdate(name: "Ignored", generatedName: true))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?.keys.contains("name") == true)
        #expect(object?["name"] is NSNull)
        let plain = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PvPProfileUpdate(icon: "star"))) as? [String: Any]
        #expect(plain?.keys.sorted() == ["icon"])
    }

    @Test func rejectsBadName() async throws {
        await #expect {
            try await service.updateProfile(PvPProfileUpdate(name: "кириллица"))
        } throws: { error in
            guard case let BackendError.api(status, code, _) = error else { return false }
            return status == 400 && code == "bad_request"
        }
    }

    @Test func createsRoomAndIssuesTicket() async throws {
        let created = try await service.createRoom(PvPCreateRoom(kind: .room, mediaType: .movie, films: 5))
        let code = try #require(created.code)
        #expect(code.count == 6)
        #expect(created.ticket.hasPrefix("pvp1."))
        #expect(created.socketURL.absoluteString.hasSuffix("/v1/pvp/rooms/\(code)/ws"))

        let ticket = try await service.ticket(code: code)
        #expect(ticket.code == nil)
        #expect(ticket.ticket.hasPrefix("pvp1."))
        #expect(ticket.ticket != created.ticket)
    }

    @Test func missingRoomIsBackendError() async throws {
        await #expect {
            try await service.ticket(code: "ZZZZZZ")
        } throws: { error in
            guard case let BackendError.api(status, code, _) = error else { return false }
            return status == 404 && code == "room_not_found"
        }
    }

    @Test func refusesDisabledMediaType() async throws {
        await #expect {
            try await service.createRoom(PvPCreateRoom(kind: .duel, mediaType: .tv))
        } throws: { error in
            guard case let BackendError.api(_, code, _) = error else { return false }
            return code == "media_type_disabled"
        }
    }
}
