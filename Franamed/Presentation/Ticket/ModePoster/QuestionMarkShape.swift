//
//  QuestionMarkShape.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 27.10.2026.
//

import SwiftUI

struct QuestionMarkShape: Shape {
    static let aspectRatio = glyphBounds.width / glyphBounds.height
    static let opticalShift: CGFloat = 0.0512

    func path(in rect: CGRect) -> Path {
        let bounds = Self.glyphBounds
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        let width = bounds.width * scale, height = bounds.height * scale
        let origin = CGPoint(x: rect.midX - width / 2, y: rect.midY - height / 2)
        let transform = CGAffineTransform(translationX: origin.x, y: origin.y)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.minX, y: -bounds.minY)
        return Self.glyph.applying(transform)
    }

    // MARK: Glyph

    private static let glyphBounds = glyph.boundingRect

    private static let glyph: Path = {
        let source = "M1016 1037Q1016 836 878.0 711.0Q740 586 510 568L504 432H415V821Q560 833 642.0 912.5Q724 992 724 1129Q724 1238 666.5 1303.5Q609 1369 512 1369Q471 1369 439.0 1360.5Q407 1352 377 1334Q387 1302 400.5 1251.5Q414 1201 414 1158Q414 1088 368.5 1049.5Q323 1011 242 1011Q166 1011 122.5 1059.0Q79 1107 79 1177Q79 1292 210.0 1372.0Q341 1452 526 1452Q745 1452 880.5 1338.0Q1016 1224 1016 1037ZM656 156Q656 80 598.5 25.5Q541 -29 464 -29Q386 -29 328.5 25.5Q271 80 271 156Q271 232 328.5 287.5Q386 343 464 343Q541 343 598.5 287.5Q656 232 656 156Z"
        var path = Path()
        var command: Character = "M"
        var numbers: [CGFloat] = []
        var current = CGPoint.zero
        let flip = { (x: CGFloat, y: CGFloat) in CGPoint(x: x, y: -y) }

        func flush() {
            switch command {
            case "M":
                current = CGPoint(x: numbers[0], y: numbers[1])
                path.move(to: flip(current.x, current.y))
            case "L":
                current = CGPoint(x: numbers[0], y: numbers[1])
                path.addLine(to: flip(current.x, current.y))
            case "H":
                current.x = numbers[0]
                path.addLine(to: flip(current.x, current.y))
            case "V":
                current.y = numbers[0]
                path.addLine(to: flip(current.x, current.y))
            case "Q":
                current = CGPoint(x: numbers[2], y: numbers[3])
                path.addQuadCurve(to: flip(current.x, current.y), control: flip(numbers[0], numbers[1]))
            case "Z":
                path.closeSubpath()
            default:
                break
            }
            numbers.removeAll()
        }

        var token = ""
        func endNumber() {
            if let value = Double(token) { numbers.append(CGFloat(value)) }
            token = ""
        }
        for character in source {
            if character.isLetter {
                endNumber()
                if !numbers.isEmpty { flush() }
                command = character
                if character == "Z" { flush() }
            } else if character == " " {
                endNumber()
            } else if character == "-", !token.isEmpty {
                endNumber()
                token = "-"
            } else {
                token.append(character)
            }
        }
        endNumber()
        if !numbers.isEmpty { flush() }
        return path
    }()
}

#Preview {
    QuestionMarkShape()
        .fill(.white)
        .frame(width: 200, height: 300)
        .border(.red)
        .padding()
        .background(.black)
}
