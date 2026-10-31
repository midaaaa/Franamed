import Foundation
import Testing
@testable import PvPScreen

struct PvPRoomLinkTests {
    @Test func buildsAndParses() throws {
        let link = try #require(PvPRoomLink(code: "120934"))
        #expect(link.url.absoluteString == "franamed://pvp/120934")
        #expect(PvPRoomLink(url: link.url) == link)
        #expect(PvPRoomLink(url: try #require(URL(string: "franamed://pvp/120934/"))) == link)
        #expect(PvPRoomLink(url: try #require(URL(string: "FRANAMED://PVP/120934"))) == link)
    }

    @Test func refusesForeignLinks() throws {
        for text in ["https://pvp/120934", "franamed://round/120934", "franamed://pvp/", "franamed://pvp/120934/extra",
                     "franamed://pvp/12093", "franamed://pvp/ABC234"] {
            #expect(PvPRoomLink(url: try #require(URL(string: text))) == nil, "\(text)")
        }
    }

    @Test func checksCodes() {
        #expect(PvPRoomLink.isValid("000000"))
        #expect(PvPRoomLink.isValid("101010"))
        #expect(!PvPRoomLink.isValid("12345"))
        #expect(!PvPRoomLink.isValid("1234567"))
        #expect(!PvPRoomLink.isValid("ABC234"))
        #expect(!PvPRoomLink.isValid("12 456"))
        #expect(!PvPRoomLink.isValid("١٢٣٤٥٦"))
        #expect(PvPRoomLink(code: " 120934 ")?.code == "120934")
        #expect(PvPRoomLink(code: "12093a") == nil)
    }

    @Test func keepsOnlyDigitsOfTypedCodes() {
        #expect(PvPRoomLink.typed("120-934") == "120934")
        #expect(PvPRoomLink.typed("120 934 567") == "120934")
        #expect(PvPRoomLink.typed("код: 12a0b934") == "120934")
        #expect(PvPRoomLink.typed("abc") == "")
    }

    @Test func findsCodesInPastedText() {
        #expect(PvPRoomLink(text: "Заходи!\nКод: 120934\nfranamed://pvp/120934")?.code == "120934")
        #expect(PvPRoomLink(text: "120 934")?.code == "120934")
        #expect(PvPRoomLink(text: "привет") == nil)
        #expect(PvPRoomLink(text: "12345") == nil)
    }

    @Test func invitations() throws {
        let link = try #require(PvPRoomLink(code: "120934"))
        let room = link.invitation(kind: .room)
        #expect(room.contains("Код: 120934"))
        #expect(room.hasSuffix("franamed://pvp/120934"))
        #expect(link.invitation(kind: .duel).hasPrefix("Вызываю на дуэль"))
    }

    @Test func lobbyCarriesTheInvite() throws {
        guard case let .lobby(room) = PvPScreen(state: PvPMatchFixtures.lobbyHost, now: Date()).content,
              case let .lobby(duel) = PvPScreen(state: PvPMatchFixtures.lobbyDuel, now: Date()).content else {
            Issue.record("not lobby")
            return
        }
        #expect(room.invite?.url.absoluteString == "franamed://pvp/\(PvPMatchFixtures.roomCode)")
        #expect(duel.invite?.url.absoluteString == "franamed://pvp/\(PvPMatchFixtures.duelCode)")
        #expect(duel.invite?.text.hasPrefix("Вызываю на дуэль") == true)
    }
}
