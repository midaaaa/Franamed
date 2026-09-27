//
//  ResultStubContent.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 21.09.2026.
//

import Foundation
import UIKit

struct ResultStubContent: Hashable {
    let title: String
    let credits: [String]
    let meta: String
    let verdict: String
    let session: String
    let searchQuery: String
    let marks: [ResultStubMark]
    let currentFrame: Int?

    init(item: MediaItem,
         mediaType: MediaType,
         details: MediaDetails?,
         outcome: RoundOutcome?,
         attemptsUsed: Int,
         playedAt: Date = .now,
         marks: [ResultStubMark],
         currentFrame: Int? = nil) {
        title = item.originalTitle
        credits = Self.credits(mediaType: mediaType, authors: details?.authors ?? [])
        meta = Self.meta(mediaType: mediaType, item: item, details: details)
        switch outcome {
        case .correct: verdict = "УГАДАНО С \(attemptsUsed)-Й ПОПЫТКИ"
        case .incorrect: verdict = "НЕ УГАДАНО"
        case nil: verdict = ""
        }
        session = Self.session(playedAt)
        let year = item.releaseDate?.prefix(4) ?? ""
        searchQuery = year.isEmpty ? title : "\(title) \(year)"
        self.marks = marks
        self.currentFrame = currentFrame
    }

    private static func session(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: date)
        return String(format: "%02d.%02d.%02d %02d:%02d", parts.day ?? 0, parts.month ?? 0,
                      (parts.year ?? 0) % 100, parts.hour ?? 0, parts.minute ?? 0)
    }

    // MARK: Credits

    private static func credits(mediaType: MediaType, authors: [String]) -> [String] {
        let label = switch mediaType {
        case .movie: "реж."
        case .tv: authors.count == 1 ? "создатель" : "создатели"
        }
        return stride(from: authors.count, through: 1, by: -1).map { shown in
            let names = authors.prefix(shown).joined(separator: ", ")
            let rest = authors.count - shown
            return rest == 0 ? "\(label) \(names)" : "\(label) \(names) и ещё \(rest)"
        }
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

extension ResultStubContent {
    func menuItems(onWebSearch: @escaping (String) -> Void) -> [FlipMenuItem] {
        [
            FlipMenuItem(title: "Скопировать название", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = title
            },
            FlipMenuItem(title: "Загуглить", systemImage: "magnifyingglass") {
                onWebSearch(searchQuery)
            }
        ]
    }
}
