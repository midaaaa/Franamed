//
//  MediaFilters.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import Foundation

struct MediaFilters: Equatable {
    var genres: [Int]? = nil
    var yearRange: ClosedRange<Int>? = nil
    var minRating: Double? = nil
    var minVoteCount: Int? = nil
    var originalLanguages: [String]? = nil
    var includeAdult: Bool = false
    var sortBy: SortBy = .popularityDesc
}
