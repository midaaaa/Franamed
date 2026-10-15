//
//  HallPhoneApp.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 13.10.2026.
//

import SwiftUI

enum StatsColor {
    static let solved = Color(red: 0.25, green: 0.84, blue: 0.45)
    static let lost = Color(red: 1, green: 0.38, blue: 0.36)

    static func accent(isSolved: Bool) -> Color { isSolved ? solved : lost }
}

private enum StatsType {
    static let caption = Font.system(size: 21, weight: .bold)
    static let unit = Font.system(size: 24, weight: .semibold)
    static let axis: CGFloat = 18
    static let label = Font.system(size: 22, weight: .semibold, design: .rounded)
    static let mark = Font.system(size: 20, weight: .bold)
    static let secondary = Color(white: 0.55)
}

struct PercentText: View {
    let share: Double
    let size: CGFloat
    var weight: Font.Weight = .heavy

    static let decimalLimit: Double = 5

    static func parts(_ share: Double) -> (whole: String, fraction: String?) {
        let percent = share * 100
        guard percent > 0, percent < 100 else { return ("\(Int(percent.rounded()))", nil) }
        let tenths = Int(max((percent * 10).rounded(), 1))
        guard Double(tenths) < decimalLimit * 10 else { return ("\(min(Int(percent.rounded()), 99))", nil) }
        return ("\(tenths / 10)", ",\(tenths % 10)")
    }

    var body: some View {
        let parts = Self.parts(share)
        SmallTailText(main: parts.whole, tail: "\(parts.fraction ?? "")%", size: size, weight: weight)
    }
}

private struct SmallTailText: View {
    let main: String
    let tail: String
    let size: CGFloat
    var weight: Font.Weight = .heavy

    var body: some View {
        let small = Font.system(size: size * 0.55, weight: weight, design: .rounded)
        Text("\(Text(main))\(Text(tail).font(small))")
            .font(.system(size: size, weight: weight, design: .rounded))
    }
}

// MARK: Stats page

struct HallPhoneStatsPage: View {
    let stats: PhoneStats
    let isTurned: Bool

    private var accent: Color { StatsColor.accent(isSolved: stats.isSolved) }

    var body: some View {
        Group {
            if isTurned { landscape } else { portrait }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            close
                .padding(.top, isTurned ? Self.closeInset : 48)
                .padding(.trailing, isTurned ? Self.closeInset : 16)
        }
        .background(Color.black)
    }

    private static let closeSize: CGFloat = 30
    private static let closeInset: CGFloat = 20

    private var close: some View {
        Image(systemName: "xmark.circle.fill")
            .font(.system(size: Self.closeSize))
            .symbolRenderingMode(.palette)
            .foregroundStyle(Color(white: 0.58), Color(white: 0.15))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(stats.caption)
                .font(StatsType.caption)
                .tracking(1.3)
                .foregroundStyle(StatsType.secondary)
            heroValue
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if isTurned { Spacer(minLength: 0) }
            Text(stats.unit)
                .font(StatsType.unit)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private var heroValue: some View {
        let size: CGFloat = isTurned ? 132 : 96
        switch stats.framing {
        case .onlyPlayer:
            SmallTailText(main: "1", tail: "", size: size)
        case _ where !stats.showsPercent:
            SmallTailText(main: "\(stats.heroCount)", tail: " из \(stats.stats.players)", size: size)
        default:
            PercentText(share: stats.heroShare, size: size)
        }
    }

    private var histogram: some View {
        FrameHistogram(stats: stats, accent: accent, barHeight: isTurned ? 196 : 280, reservesAxis: isTurned)
    }

    private var portrait: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            Spacer(minLength: 24)
            histogram
        }
        .padding(.top, 66)
        .padding(.horizontal, 24)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var landscape: some View {
        HStack(alignment: .top, spacing: 14) {
            HStack(alignment: .top, spacing: 28) {
                hero
                    .padding(.top, 20)
                    .frame(width: 226, alignment: .leading)
                    .frame(maxHeight: .infinity)
                histogram
            }
            .fixedSize(horizontal: false, vertical: true)
            Color.clear.frame(width: Self.closeSize)
        }
        .padding(.leading, 66)
        .padding(.trailing, 18)
        .padding(.vertical, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FrameHistogram: View {
    let stats: PhoneStats
    let accent: Color
    let barHeight: CGFloat
    let reservesAxis: Bool

    private enum AxisPlacement {
        case none
        case inline
        case column
    }

    private static let slots = 7
    private static let spacing: CGFloat = 8
    private static let markRoom: CGFloat = 32
    private static let axisWidth: CGFloat = 40
    private static let axisGap: CGFloat = 8
    private static let inlineAxisColumns = 5

    private var columns: [PhoneStats.Column] { stats.columns }

    private var axisPlacement: AxisPlacement {
        if reservesAxis { return .column }
        return columns.count <= Self.inlineAxisColumns ? .inline : .none
    }

    private func height(of share: Double) -> CGFloat {
        (barHeight - Self.markRoom) * share / stats.gridTop
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: Self.axisGap) {
                ZStack(alignment: .bottom) {
                    ForEach(stats.gridLines, id: \.self) { line in
                        Rectangle()
                            .fill(Color(white: 0.15))
                            .frame(height: 2)
                            .offset(y: -height(of: line.share))
                    }
                    SlotRow(slots: Self.slots, spacing: Self.spacing) {
                        ForEach(columns) { bar($0) }
                    }
                    if axisPlacement == .inline { axis.frame(maxWidth: .infinity, alignment: .trailing) }
                }
                if axisPlacement == .column { axis }
            }
            .frame(height: barHeight, alignment: .bottom)
            HStack(spacing: Self.axisGap) {
                SlotRow(slots: Self.slots, spacing: Self.spacing) {
                    ForEach(columns) { column in
                        Text(column.label)
                            .font(StatsType.label)
                            .foregroundStyle(column.isMine ? accent : Color(white: 0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
                if axisPlacement == .column { Color.clear.frame(width: Self.axisWidth, height: 1) }
            }
        }
    }

    private var axis: some View {
        ZStack(alignment: axisPlacement == .inline ? .bottomTrailing : .bottomLeading) {
            ForEach(stats.gridLines, id: \.self) { line in
                axisLabel(line)
                    .foregroundStyle(Color(white: 0.45))
                    .fixedSize()
                    .padding(.leading, axisPlacement == .inline ? 6 : 0)
                    .background(Color.black)
                    .alignmentGuide(.bottom) { $0[VerticalAlignment.center] }
                    .offset(y: -height(of: line.share))
            }
        }
        .frame(width: Self.axisWidth, alignment: axisPlacement == .inline ? .trailing : .leading)
    }

    @ViewBuilder
    private func axisLabel(_ line: PhoneStats.GridLine) -> some View {
        if let players = line.players {
            Text("\(players)")
                .font(.system(size: StatsType.axis, weight: .semibold, design: .rounded))
        } else {
            PercentText(share: line.share, size: StatsType.axis, weight: .semibold)
        }
    }

    private func bar(_ column: PhoneStats.Column) -> some View {
        let color = column.isMine ? accent : Color(white: column.isCounted ? 0.42 : 0.2)
        return UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6, style: .continuous)
            .fill(color)
            .frame(height: max(5, height(of: column.share)))
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if column.isMine {
                    Text("вы")
                        .font(StatsType.mark)
                        .foregroundStyle(accent)
                        .fixedSize()
                        .offset(y: -Self.markRoom + 4)
                }
            }
    }
}

private struct SlotRow: Layout {
    let slots: Int
    let spacing: CGFloat

    private func slotWidth(_ width: CGFloat) -> CGFloat {
        (width - spacing * CGFloat(slots - 1)) / CGFloat(slots)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let slot = ProposedViewSize(width: slotWidth(width), height: nil)
        return CGSize(width: width, height: subviews.map { $0.sizeThatFits(slot).height }.max() ?? 0)
    }

    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize,
                           subviews: Subviews, cache: inout ()) -> CGFloat? {
        guard guide == .lastTextBaseline || guide == .firstTextBaseline, let first = subviews.first else { return nil }
        let dimensions = first.dimensions(in: ProposedViewSize(width: slotWidth(bounds.width), height: nil))
        return bounds.maxY - dimensions.height + dimensions[guide]
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = slotWidth(bounds.width)
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(index) * (width + spacing), y: bounds.maxY - size.height),
                          anchor: .topLeading, proposal: ProposedViewSize(width: width, height: size.height))
        }
    }
}

// MARK: Lock screen

struct HallPhoneLockScreen: View {
    let time: Date

    private static let locale = Locale(identifier: "ru_RU")

    var body: some View {
        VStack(spacing: 0) {
            Text(time.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Self.locale)))
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 74)
            Text(time.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Self.locale)))
                .font(.system(size: 88, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            HallPhoneNotice()
                .padding(.horizontal, 12)
                .padding(.bottom, 130)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

struct HallPhoneNotice: View {
    var body: some View {
        HStack(spacing: 12) {
            AppIconImage()
                .frame(width: 44, height: 44)
                .opacity(0.8)
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(.white.opacity(0.4)).frame(width: 110, height: 9)
                Capsule().fill(.white.opacity(0.25)).frame(height: 9)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(Color(white: 0.11)))
    }
}

struct AppIconImage: View {
    var body: some View {
        GeometryReader { proxy in
            Group {
                if let icon = Self.icon {
                    Image(uiImage: icon).resizable().interpolation(.high)
                } else {
                    Color(white: 0.3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: proxy.size.width * 0.225, style: .continuous))
        }
    }

    static let icon: UIImage? = {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String] ?? []
        return files.reversed().lazy.compactMap { UIImage(named: $0) }.first { $0.cgImage != nil }
    }()
}

// MARK: Rendering

@MainActor
enum HallPhoneAppRender {
    static var portrait: CGSize { CGSize(width: HallPhoneChrome.width, height: HallPhoneChrome.height) }

    static func pictures(_ stats: PhoneStats) async -> HallPhoneScreen.Pictures {
        HallPhoneScreen.Pictures(app: await render(HallPhoneStatsPage(stats: stats, isTurned: false), turned: false),
                                 turnedApp: await render(HallPhoneStatsPage(stats: stats, isTurned: true), turned: true),
                                 notice: await lockScreen(time: stats.time))
    }

    static func lockScreen(time: Date) async -> HallPicture? {
        await render(HallPhoneLockScreen(time: time), turned: false)
    }

    private static func render(_ view: some View, turned: Bool) async -> HallPicture? {
        let size = turned ? CGSize(width: portrait.height, height: portrait.width) : portrait
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height)
            .environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        format.preferredRange = .standard
        let flat = UIGraphicsImageRenderer(size: portrait, format: format).image { context in
            if turned {
                context.cgContext.translateBy(x: portrait.width, y: 0)
                context.cgContext.rotate(by: .pi / 2)
            }
            image.draw(at: .zero)
        }
        return await HallPicture.make(flat)
    }
}

#Preview("Статистика — со 2-го кадра") {
    HallPhoneStatsPage(stats: .preview(solvedAtFrame: 2), isTurned: false)
        .frame(width: HallPhoneAppRender.portrait.width, height: HallPhoneAppRender.portrait.height)
}

#Preview("Статистика — не угадал, горизонтально") {
    HallPhoneStatsPage(stats: .preview(solvedAtFrame: nil), isTurned: true)
        .frame(width: HallPhoneAppRender.portrait.height, height: HallPhoneAppRender.portrait.width)
}

#Preview("Статистика — мало игроков, 3 кадра") {
    HallPhoneStatsPage(stats: PhoneStats(stats: RoundStats(players: 7, solvedAtFrame: [2, 1, 1, 0, 0, 0]),
                                         solvedAtFrame: 2, frameCount: 3), isTurned: false)
        .frame(width: HallPhoneAppRender.portrait.width, height: HallPhoneAppRender.portrait.height)
}

#Preview("Статистика — только вы") {
    HallPhoneStatsPage(stats: PhoneStats(stats: RoundStats(players: 0, solvedAtFrame: [0, 0, 0, 0, 0, 0]),
                                         solvedAtFrame: 4, frameCount: 6), isTurned: false)
        .frame(width: HallPhoneAppRender.portrait.width, height: HallPhoneAppRender.portrait.height)
}

#Preview("Экран блокировки") {
    HallPhoneLockScreen(time: .now)
        .frame(width: HallPhoneAppRender.portrait.width, height: HallPhoneAppRender.portrait.height)
}

extension PhoneStats {
    static func preview(solvedAtFrame: Int?) -> PhoneStats {
        PhoneStats(stats: RoundStats(players: 3_870, solvedAtFrame: [310, 540, 850, 740, 460, 310]),
                   solvedAtFrame: solvedAtFrame, frameCount: 6)
    }
}
