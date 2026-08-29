//
//  TicketCurlTopology.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 23.08.2026.
//

import Foundation

enum TicketCurlTopology {
    static let colsA = 96
    static let colsB = 48

    static var indexCount: Int { colsA * colsB * 6 }

    static func makeIndices() -> [UInt16] {
        var idx: [UInt16] = []
        idx.reserveCapacity(indexCount)
        let rowStride = colsA + 1
        for j in 0..<colsB {
            for i in 0..<colsA {
                let a0 = UInt16(j * rowStride + i)
                let a1 = UInt16(j * rowStride + i + 1)
                let b0 = UInt16((j + 1) * rowStride + i)
                let b1 = UInt16((j + 1) * rowStride + i + 1)
                idx.append(contentsOf: [a0, b0, a1, a1, b0, b1])
            }
        }
        return idx
    }
}
