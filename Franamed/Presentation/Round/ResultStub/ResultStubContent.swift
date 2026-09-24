//
//  ResultStubContent.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import Foundation

struct ResultStubContent: Hashable {
    let title: String
    let authorsLabel: String
    let authors: String?
    let meta: String
    let verdict: String
    let session: String
    let attemptsUsed: Int
    let frameCount: Int
    let isCorrect: Bool

    init(item: MediaItem,
         mediaType: MediaType,
         details: MediaDetails?,
         outcome: RoundOutcome,
         attemptsUsed: Int,
         frameCount: Int,
         playedAt: Date = .now) {
        title = item.originalTitle
        authorsLabel = mediaType == .movie ? "реж." : "создатели"
        authors = details?.authors.isEmpty == false
            ? details?.authors.joined(separator: ", ")
            : nil
        meta = Self.meta(mediaType: mediaType, item: item, details: details)
        isCorrect = outcome == .correct
        self.attemptsUsed = attemptsUsed
        self.frameCount = frameCount
        verdict = isCorrect ? "УГАДАНО С \(attemptsUsed)-Й ПОПЫТКИ" : "НЕ УГАДАНО"
        session = Self.session(playedAt)
    }

    private static func session(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.day, .month, .hour, .minute], from: date)
        return String(format: "%02d.%02d %02d:%02d",
                      parts.day ?? 0, parts.month ?? 0, parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Meta line

    private static func meta(mediaType: MediaType, item: MediaItem, details: MediaDetails?) -> String {
        var parts: [String] = []

        if let years = years(mediaType: mediaType, item: item, details: details) { parts.append(years) }

        switch mediaType {
        case .movie:
            if let runtime = details?.runtimeMinutes, runtime > 0 { parts.append(duration(runtime)) }
        case .tv:
            if let seasons = details?.seasonCount, seasons > 0 { parts.append(seasonsText(seasons)) }
        }

        if let certification = details?.certification { parts.append(certification) }

        return parts.joined(separator: " · ")
    }

    private static func years(mediaType: MediaType, item: MediaItem, details: MediaDetails?) -> String? {
        let first = details?.firstYear ?? Int(item.releaseDate?.prefix(4) ?? "")
        guard let first else { return nil }

        guard mediaType == .tv else { return "\(first)" }

        if details?.isInProduction == true { return "\(first) — …" }
        if details?.isCanceled == true { return "\(first) — прервано" }
        guard let last = details?.lastYear, last != first else { return "\(first)" }
        return "\(first)–\(last)"
    }

    private static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) мин" }
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) мин"
    }

    private static func seasonsText(_ count: Int) -> String {
        let tail = count % 10, hundred = count % 100
        if hundred >= 11 && hundred <= 14 { return "\(count) сезонов" }
        switch tail {
        case 1: return "\(count) сезон"
        case 2...4: return "\(count) сезона"
        default: return "\(count) сезонов"
        }
    }
}
