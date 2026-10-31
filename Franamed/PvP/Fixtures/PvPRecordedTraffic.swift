//
//  PvPRecordedTraffic.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

#if DEBUG
import Foundation

enum PvPRecordedTraffic {
    struct Line: Decodable, Sendable {
        let at: Double
        let msg: PvPEnvelope?
        let reconnect: Bool?
    }

    static func lines(_ traffic: String) -> [Line] {
        let decoder = JSONDecoder()
        return traffic.split(separator: "\n").compactMap { try? decoder.decode(Line.self, from: Data($0.utf8)) }
    }
}
#endif
