//
//  HallPhoneDraw.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 09.10.2026.
//

import simd
import UIKit

struct HallPhoneArgs {
    var right: SIMD4<Float>
    var up: SIMD4<Float>
    var back: SIMD4<Float>
    var cameraRight: SIMD4<Float>
    var cameraUp: SIMD4<Float>
    var cameraBack: SIMD4<Float>
    var center: SIMD4<Float>
    var face: SIMD4<Float>
    var lens: SIMD4<Float>
    var view: SIMD4<Float>
    var chrome: SIMD4<Float>
    var color: SIMD4<Float>
    var stage: SIMD4<Float>
    var glow: SIMD4<Float>
    var thumb: SIMD4<Float>
}

struct HallPhoneDraw {
    var args: HallPhoneArgs
    var lensArgs: HallShaderArgs
    var lensWidth: Int
    var lensHeight: Int
    var reusesLens = false
    let chrome: HallPicture?
    let turnedChrome: HallPicture?
    let thumbnail: HallPicture?
    let screenOn: Float
    let veil: Float
    let shownPoint: SIMD2<Float>
    let layout: HallPhone.Layout

    static let armDepth: Float = 0.75
    static let length: Float = 0.1466
    private static let armInset: Float = 0.075
    private static let distance: Float = 0.4
    private static let thickness: Float = 0.117
    private static let stageFocal: Float = 1.2
    private static let bodyRounding: Float = 0.155
    private static let wideCrop: Float = (16.0 / 9) / (4.0 / 3)
    private static let pushSteps = 4
    private static let lensLimit: Float = 3.5
    private static let lensStep: Float = 64
    private static let glowFloor: Float = 0.06
    private static let veilLimit: Float = 0.4

    static func armPoint(eye: SIMD3<Float>, seatPitch: Float, armTop: Float) -> SIMD3<Float> {
        SIMD3(seatPitch / 2 - armInset, armTop + length * thickness / 4, eye.z - armDepth)
    }

    static func project(_ p: SIMD3<Float>, eye: SIMD3<Float>, focal: Float, center: SIMD2<Float>) -> SIMD2<Float> {
        let depth = eye.z - p.z
        return SIMD2(center.x + focal * (p.x - eye.x) / depth, center.y - focal * (p.y - eye.y) / depth)
    }

    init(pose: HallPhone.Pose, hall: HallShaderArgs, viewSize: SIMD2<Float>, pixelScale s: Float) {
        let settings = pose.settings
        let camera = Projection(hall)
        let k = max(pose.zoom, 1) * (settings.isWide ? Self.wideCrop : 1)
        let full = settings.size(viewWidth: viewSize.x) * s
        let layout = pose.layout
        let toView = { (p: SIMD2<Float>) in (p - layout.origin) * s }

        let parts = layout.phoneParts(pose.point)
        let settled = toView(parts.inner)
        let give = parts.give * s
        let point = settled + give
        let lensPoint = toView(layout.phonePoint(pose.lensPoint))
        let bodyAim = Aim(point: point, target: toView(layout.target(pose.point)),
                          reach: layout.reach(pose.point), camera: camera, aim: settings.aim)
        let lensAim = Aim(point: lensPoint, target: toView(layout.target(pose.lensPoint)),
                          reach: layout.reach(pose.lensPoint), camera: camera, aim: settings.aim)
        let lensBasis = lensAim.basis.rolled(pose.roll)

        let shift = camera.slope(at: lensPoint) * Self.distance
        let fromPhone = lensAim.target * camera.eye.z - SIMD3(shift, 0)
        let sight = fromPhone / -fromPhone.z
        let sightPixel = camera.pixel(of: sight)
        let local = SIMD3(simd_dot(sight, lensBasis.right), simd_dot(sight, lensBasis.up),
                          simd_dot(sight, lensBasis.back))
        let aimed = SIMD2(local.x, local.y) / -local.z

        let t = pose.raise * pose.raise * (3 - 2 * pose.raise)
        let lyingRoll: Float = settings.isPortrait ? 0 : -.pi / 2
        let body = Basis(simd_slerp(Basis.resting.rolled(lyingRoll).rotation,
                                    bodyAim.basis.rolled(pose.roll).rotation, t))
        let arm = Self.armPoint(eye: camera.eye, seatPitch: hall.seat.x, armTop: hall.rows.x * hall.rows.y + hall.arm.x)
        let rest = Self.project(arm, eye: camera.eye, focal: camera.focal, center: camera.center)
        let lying = full * (camera.focal * Self.length / Self.armDepth / full.max())
        let size = simd_mix(lying, full, SIMD2(repeating: t))
        let stage = Stage(center: simd_mix(camera.center, viewSize * s / 2, SIMD2(repeating: t)),
                          focal: simd_mix(camera.focal, viewSize.y * s * Self.stageFocal, t),
                          distance: simd_mix(Self.armDepth, Self.distance, t))
        let area = Area(low: (layout.areaLow - layout.origin) * s, high: (layout.areaHigh - layout.origin) * s,
                        radius: layout.areaRadius * s)
        var place = simd_mix(rest, settled, SIMD2(repeating: t))
        var push = SIMD2<Float>.zero
        for _ in 0..<Self.pushSteps {
            push += Self.silhouettePush(place: place + push, size: size, body: body, stage: stage, area: area)
        }
        place += (push + give) * t

        screenOn = min(max((pose.raise - 0.55) / 0.45, 0), 1)
        shownPoint = (point + push) / s + layout.origin
        self.layout = layout

        let lens = Self.lens(full: full, k: k, aimed: aimed, basis: lensBasis, camera: camera, settings: settings)
        var lensArgs = hall
        lensArgs.eye = SIMD4(camera.eye + SIMD3(shift, 0), 0)
        lensArgs.camera = SIMD4(camera.focal * k, lens.offset.y + k * camera.center.y,
                                lens.offset.x + k * camera.center.x, 0)
        lensArgs.frame = SIMD4(lens.offset.y + k * hall.frame.x, lens.offset.y + k * hall.frame.y,
                               lens.offset.x + k * hall.frame.z, lens.offset.x + k * hall.frame.w)
        self.lensArgs = lensArgs
        lensWidth = Int(lens.size.x)
        lensHeight = Int(lens.size.y)

        let screenColor = Self.screenColor(sight: sightPixel, full: full, k: k, hall: hall, settings: settings)
        let lit = settings.bloom * screenOn * screenOn
        let metersPerPixel = stage.distance / stage.focal
        args = HallPhoneArgs(
            right: SIMD4(body.right, 0),
            up: SIMD4(body.up, 0),
            back: SIMD4(body.back, 0),
            cameraRight: SIMD4(lensBasis.right, 0),
            cameraUp: SIMD4(lensBasis.up, 0),
            cameraBack: SIMD4(lensBasis.back, 0),
            center: SIMD4(place.x, place.y, stage.distance, 1),
            face: SIMD4(size.x, size.y, size.x * metersPerPixel / 2, size.y * metersPerPixel / 2),
            lens: SIMD4(aimed.x, aimed.y, 1 / (k * camera.focal), camera.focal),
            view: SIMD4(lens.offset.x, lens.offset.y, k, size.min() * metersPerPixel * Self.thickness),
            chrome: SIMD4(settings.isPortrait ? 1 : 0, settings.showsGrid ? 1 : 0, settings.finderRatio,
                          pose.zoom),
            color: SIMD4(settings.color, screenOn),
            stage: SIMD4(stage.center.x, stage.center.y, stage.focal, max(1 - abs(pose.roll) / (.pi / 2), 0)),
            glow: SIMD4(screenColor, lit),
            thumb: SIMD4(pose.thumbnail == nil ? 0 : 1, pose.thumbnail?.aspect ?? 1, 0, 0)
        )
        let brightness = simd_dot(screenColor, SIMD3(0.2126, 0.7152, 0.0722))
        veil = min(lit * (0.12 + 0.5 * brightness), Self.veilLimit)
        chrome = pose.chrome
        turnedChrome = pose.turnedChrome
        thumbnail = pose.thumbnail
    }

    func reusingLens(of previous: HallPhoneDraw) -> HallPhoneDraw {
        var draw = self
        draw.args.cameraRight = previous.args.cameraRight
        draw.args.cameraUp = previous.args.cameraUp
        draw.args.cameraBack = previous.args.cameraBack
        draw.args.lens = previous.args.lens
        draw.args.view.x = previous.args.view.x
        draw.args.view.y = previous.args.view.y
        draw.args.view.z = previous.args.view.z
        draw.lensArgs = previous.lensArgs
        draw.lensWidth = previous.lensWidth
        draw.lensHeight = previous.lensHeight
        draw.reusesLens = true
        return draw
    }

    // MARK: Geometry

    private struct Projection {
        let focal: Float
        let center: SIMD2<Float>
        let eye: SIMD3<Float>

        init(_ hall: HallShaderArgs) {
            focal = hall.camera.x
            center = SIMD2(hall.camera.z, hall.camera.y)
            eye = SIMD3(hall.eye.x, hall.eye.y, hall.eye.z)
        }

        func slope(at pixel: SIMD2<Float>) -> SIMD2<Float> {
            SIMD2(pixel.x - center.x, center.y - pixel.y) / focal
        }

        func pixel(of ray: SIMD3<Float>) -> SIMD2<Float> {
            let depth = max(-ray.z, 1e-4)
            return SIMD2(center.x + focal * ray.x / depth, center.y - focal * ray.y / depth)
        }
    }

    private struct Stage {
        let center: SIMD2<Float>
        let focal: Float
        let distance: Float
    }

    private struct Area {
        let low: SIMD2<Float>
        let high: SIMD2<Float>
        let radius: Float
    }

    private struct Aim {
        let target: SIMD3<Float>
        let basis: Basis

        private static let follow: Float = 0.6
        private static let edgeYaw: Float = 0.25

        init(point: SIMD2<Float>, target pixel: SIMD2<Float>, reach: Float, camera: Projection, aim: Float) {
            let held = camera.slope(at: point)
            target = SIMD3(camera.slope(at: pixel), -1)
            let middle = HallScene.screenBottom + HallScene.screenHeight / 2
            let neutral = SIMD2(-camera.eye.x / camera.eye.z, (middle - camera.eye.y) / camera.eye.z)
            let yaw = aim * (atan(held.x) - atan(neutral.x)) + Self.follow * Self.edgeYaw * min(max(reach, -1), 1)
            let pitch = aim * (atan(held.y) - atan(neutral.y)) + Self.follow * (atan(target.y) - atan(held.y))
            let forward = simd_normalize(SIMD3(tan(yaw), tan(pitch), -1))
            let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
            basis = Basis(right: right, up: simd_cross(right, forward), back: -forward)
        }
    }

    private struct Basis {
        var right: SIMD3<Float>
        var up: SIMD3<Float>
        var back: SIMD3<Float>

        var rotation: simd_quatf { simd_quatf(simd_float3x3(columns: (right, up, back))) }

        init(right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>) {
            self.right = right
            self.up = up
            self.back = back
        }

        init(_ rotation: simd_quatf) {
            right = rotation.act(SIMD3(1, 0, 0))
            up = rotation.act(SIMD3(0, 1, 0))
            back = rotation.act(SIMD3(0, 0, 1))
        }

        func rolled(_ angle: Float) -> Basis {
            Basis(right: cos(angle) * right + sin(angle) * up, up: cos(angle) * up - sin(angle) * right, back: back)
        }

        static let resting: Basis = {
            let flat = Basis(right: SIMD3(1, 0, 0), up: SIMD3(0, 0, -1), back: SIMD3(0, 1, 0))
            return Basis(simd_quatf(angle: -0.3, axis: SIMD3(0, 1, 0)) * flat.rotation)
        }()
    }

    private static func silhouettePush(place: SIMD2<Float>, size: SIMD2<Float>, body: Basis, stage: Stage,
                                       area: Area) -> SIMD2<Float> {
        let metersPerPixel = stage.distance / stage.focal
        let offset = (place - stage.center) * SIMD2(1, -1) * metersPerPixel
        let rounding = bodyRounding * size.min()
        let half = size / 2 - rounding
        let depth = size.min() * metersPerPixel * thickness / 2
        var push = SIMD2<Float>.zero
        for sign in [SIMD2<Float>(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)] {
            for side in [-depth, depth] {
                let local = half * sign * SIMD2(1, -1) * metersPerPixel
                let p = SIMD3(offset, -stage.distance) + body.right * local.x + body.up * local.y + body.back * side
                let shown = stage.center + stage.focal * SIMD2(p.x, -p.y) / max(-p.z, 1e-4)
                let curve = rounding * stage.distance / max(-p.z, 1e-4)
                let room = max(area.radius - curve, 0) * HallPhone.Layout.cornerReach
                let inner = area.low + curve + room, outer = simd_max(inner, area.high - curve - room)
                let core = simd_clamp(shown, inner, outer)
                let out = shown - core
                let length = HallPhone.Layout.cornerLength(out)
                let inside = length > room ? core + out * (room / max(length, 1e-4)) : shown
                let move = inside - shown
                if simd_length_squared(move) > simd_length_squared(push) { push = move }
            }
        }
        return push
    }

    // MARK: Screen

    private static func lens(full: SIMD2<Float>, k: Float, aimed: SIMD2<Float>, basis: Basis, camera: Projection,
                             settings: HallPhone.Settings) -> (size: SIMD2<Float>, offset: SIMD2<Float>) {
        let toLens = { (ray: SIMD3<Float>) in
            k * camera.pixel(of: basis.right * ray.x + basis.up * ray.y + basis.back * ray.z)
        }
        let middle = toLens(SIMD3(aimed, -1))
        let reach = screenCorners(size: full, settings: settings).reduce(SIMD2<Float>.zero) { reach, delta in
            let ray = SIMD3(aimed.x + delta.x / (k * camera.focal), aimed.y - delta.y / (k * camera.focal), -1)
            return simd_max(reach, abs(toLens(ray) - middle))
        }
        let needed = simd_min(2 * reach + 4, full * lensLimit)
        let size = (needed / lensStep).rounded(.up) * lensStep
        return (size, size / 2 - middle)
    }

    private static func screenCorners(size: SIMD2<Float>, settings: HallPhone.Settings) -> [SIMD2<Float>] {
        let extent = (settings.isPortrait ? size : SIMD2(size.y, size.x)) / 2
        let screenHalf = extent - 2 * HallPhone.Settings.bezel * extent.x
        let center = finderCenter(size: size, settings: settings)
        let reach = screenHalf + SIMD2(0, abs(center.x) + abs(center.y))
        return [SIMD2(-1, -1), SIMD2(1, -1), SIMD2(-1, 1), SIMD2(1, 1)].flatMap { sign in
            [reach * sign, SIMD2(reach.y, reach.x) * sign]
        }
    }

    private static func finderCenter(size: SIMD2<Float>, settings: HallPhone.Settings) -> SIMD2<Float> {
        let extent = (settings.isPortrait ? size : SIMD2(size.y, size.x)) / 2
        let screenHalf = extent - 2 * HallPhone.Settings.bezel * extent.x
        let center = settings.finder(screenHalf: screenHalf).center.y
        return settings.isPortrait ? SIMD2(0, center) : SIMD2(center, 0)
    }

    private static func screenColor(sight: SIMD2<Float>, full: SIMD2<Float>, k: Float, hall: HallShaderArgs,
                                    settings: HallPhone.Settings) -> SIMD3<Float> {
        let finderHalf = SIMD2(full.min(), full.min() * settings.finderRatio) / (2 * k)
        let low = simd_max(sight - finderHalf, SIMD2(hall.frame.z, hall.frame.x))
        let high = simd_min(sight + finderHalf, SIMD2(hall.frame.w, hall.frame.y))
        let overlap = simd_max(high - low, .zero)
        let shown = overlap.x * overlap.y / max(4 * finderHalf.x * finderHalf.y, 1)
        let mean = SIMD3(hall.mean.x, hall.mean.y, hall.mean.z)
        return simd_clamp(shown * mean + (1 - shown) * 0.06 * mean, SIMD3(repeating: glowFloor), SIMD3(repeating: 1))
    }
}

enum HallPhoneColor {
    static let white = 0xDBDBD6
    static let black = 0x333336
    static let custom = 0x9E998F

    static func vector(_ hex: Int) -> SIMD3<Float> {
        SIMD3(Float((hex >> 16) & 0xFF), Float((hex >> 8) & 0xFF), Float(hex & 0xFF)) / 255
    }

    static func hex(_ color: UIColor) -> Int {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let channel = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return channel(red) << 16 | channel(green) << 8 | channel(blue)
    }

    static func uiColor(_ hex: Int) -> UIColor {
        let value = vector(hex)
        return UIColor(red: CGFloat(value.x), green: CGFloat(value.y), blue: CGFloat(value.z), alpha: 1)
    }

    static func swatch(_ hex: Int, isSelected: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 26, height: 26)).image { _ in
            uiColor(hex).setFill()
            UIBezierPath(ovalIn: CGRect(x: 3, y: 3, width: 20, height: 20)).fill()
            guard isSelected else { return }
            UIColor.label.setStroke()
            let ring = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 24, height: 24))
            ring.lineWidth = 2
            ring.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
}
