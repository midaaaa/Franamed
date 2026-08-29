//
//  TearGeometry.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 29.08.2026.
//

import CoreGraphics

struct TearGeometry {
    let config: TicketTearConfig
    let size: CGSize
    let fromStart: Bool

    var perfLength: CGFloat { config.stubSide.isVertical ? size.height : size.width }

    var perforation: TearPerforation {
        TearPerforation(config: config, length: perfLength)
    }

    var tabCount: Int { perforation.tabCount }
    var pitch: CGFloat { perforation.pitch }
    var holeLen: CGFloat { perforation.holeLength }
    var tabLen: CGFloat { perforation.tabLength }

    var axisDir: CGVector {
        config.stubSide.isVertical ? CGVector(dx: 0, dy: 1) : CGVector(dx: 1, dy: 0)
    }

    var stubN: CGVector {
        switch config.stubSide {
        case .trailing: return CGVector(dx: 1, dy: 0)
        case .leading:  return CGVector(dx: -1, dy: 0)
        case .bottom:   return CGVector(dx: 0, dy: 1)
        case .top:      return CGVector(dx: 0, dy: -1)
        }
    }

    var lineStart: CGPoint {
        switch config.stubSide {
        case .trailing: return CGPoint(x: size.width - config.stubExtent, y: 0)
        case .leading:  return CGPoint(x: config.stubExtent, y: 0)
        case .bottom:   return CGPoint(x: 0, y: size.height - config.stubExtent)
        case .top:      return CGPoint(x: 0, y: config.stubExtent)
        }
    }

    var perfOrigin: CGPoint {
        fromStart ? lineStart : lineStart + axisDir * perfLength
    }
    var perfDir: CGVector { fromStart ? axisDir : -axisDir }

    var handle: CGPoint { perfOrigin + stubN * config.stubExtent }

    var farCorner: CGPoint { perfOrigin + perfDir * perfLength + stubN * config.stubExtent }

    var returnDistance: CGFloat {
        config.returnFlightDistance > 0
            ? config.returnFlightDistance
            : config.stubExtent + config.canvasPadding
    }

    var detachDistance: CGFloat {
        config.detachFlightDistance > 0
            ? config.detachFlightDistance
            : perfLength + config.canvasPadding
    }

    func inTearSpace(_ p: CGPoint) -> CGPoint {
        let d = p - perfOrigin
        return CGPoint(x: d • perfDir, y: d • stubN)
    }

    // MARK: Узор перфорации, в координатах самого билета

    var patternOrigin: CGFloat { fromStart ? 0 : perfLength }
    var patternSign: CGFloat { fromStart ? 1 : -1 }
    var patternInset: CGFloat { config.perfEndInset + tabLen }
}
