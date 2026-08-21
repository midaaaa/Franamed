//
//  RoundViewModel.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 15.08.2026.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class RoundViewModel: ObservableObject {
    let frameCount: Int
    private let modelContext: ModelContext
    private var attemptsMade = 0
    private let filters: MovieFilters

    @Published private(set) var movieWithBackdrops: MovieWithBackdrops?
    @Published private(set) var isLoading = true
    @Published private(set) var error: Error?
    @Published private(set) var searchResults: [Movie] = []
    @Published private(set) var hasSearched = false

    @Published var answerText = ""
    @Published private(set) var attemptsRemaining: Int
    @Published private(set) var outcome: RoundOutcome?
    @Published private(set) var revealedCount = 1
    @Published private(set) var currentFrameIndex = 0
    @Published private(set) var answeredFrameIndex: Int?
    private let movieFacade: MovieFacadeProtocol

    init(movieFacade: MovieFacadeProtocol, modelContext: ModelContext, filters: MovieFilters = MovieFilters(), frameCount: Int = 6) {
        self.movieFacade = movieFacade
        self.modelContext = modelContext
        self.filters = filters
        self.frameCount = frameCount
        self.attemptsRemaining = frameCount
    }

    func loadRound() async {
        defer {
            isLoading = false
        }

        isLoading = true
        error = nil
        outcome = nil
        searchResults = []
        hasSearched = false
        attemptsRemaining = frameCount
        answerText = ""
        revealedCount = 1
        currentFrameIndex = 0
        answeredFrameIndex = nil
        attemptsMade = 0

        do {
            movieWithBackdrops = try await movieFacade.fetchRandomMovieAndBackdrops(filters: filters, frameCount: frameCount)
        } catch {
            self.error = error
        }
    }

    func submitAnswer() {
        guard outcome == nil, let movieWithBackdrops else { return }
        answerText = answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedAnswer = answerText
        let movie = movieWithBackdrops.movie
        attemptsMade += 1
        if attemptsMade == 1 {
            modelContext.insert(WatchedMovieCache(tmdbId: movie.id, addedAt: .now))
        }
        let isCorrect = [movie.title, movie.originalTitle].contains {
            $0.caseInsensitiveCompare(answerText) == .orderedSame
        }
        if isCorrect {
            answeredFrameIndex = currentFrameIndex
            outcome = .correct
            modelContext.insert(RoundRecord(tmdbId: movie.id, playedAt: .now, attemptsUsed: attemptsMade, wasCorrect: true, guessedTitle: submittedAnswer, isDaily: false))
            revealedCount = frameCount
        } else {
            answerText = ""
            attemptsRemaining -= 1

            if revealedCount < frameCount {
                revealedCount += 1
                currentFrameIndex = revealedCount - 1
            }

            if attemptsRemaining == 0 {
                answeredFrameIndex = currentFrameIndex
                outcome = .incorrect
                modelContext.insert(RoundRecord(tmdbId: movie.id, playedAt: .now, attemptsUsed: attemptsMade, wasCorrect: false, guessedTitle: submittedAnswer, isDaily: false))
            }
        }
    }

    func showPreviousFrame() {
        currentFrameIndex = max(currentFrameIndex - 1, 0)
    }

    func showNextFrame() {
        currentFrameIndex = min(currentFrameIndex + 1, revealedCount - 1)
    }

    func searchAnswer() async {
        let trimmedQuery = answerText.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await Task.sleep(for: .milliseconds(400))
        } catch {
            return
        }

        guard !trimmedQuery.isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }

        do {
            let language = detectTMDBLanguage(from: trimmedQuery)
            let results = try await movieFacade.searchMovies(query: trimmedQuery, language: language)

            var seenTitles = Set<String>()
            searchResults = results.filter { seenTitles.insert($0.title).inserted }
            hasSearched = true
        } catch {
            searchResults = []
            hasSearched = true
        }
    }

    private static let cyrillicRange: ClosedRange<Unicode.Scalar> = "\u{0400}"..."\u{04FF}"

    private func detectTMDBLanguage(from text: String) -> String {
        let isCyrillic = text.unicodeScalars.contains { Self.cyrillicRange.contains($0) }
        return isCyrillic ? "ru-RU" : "en-US"
    }
}

enum RoundOutcome: Equatable {
    case correct
    case incorrect
}
