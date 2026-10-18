//
//  PlaylistStubBody.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 12.10.2026.
//

import SwiftUI

struct PlaylistStubBody: View {
    let mediaType: MediaType
    let mode: TicketGameMode
    let playlist: PlaylistTicket?
    var onOpenPicker: () -> Void = {}
    var onStart: () -> Void = {}

    private static let nameFont = Font.system(size: 20, weight: .semibold, design: .serif)

    var body: some View {
        VStack(alignment: .leading, spacing: TicketStyle.stubSpacing) {
            Text(mode.displayName)
                .font(TicketStyle.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            Button(action: onOpenPicker) {
                fields.contentShape(Rectangle())
            }
            .frame(maxHeight: .infinity)
            startButton
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.black)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let playlist, playlist.isFinished {
                PlaylistCompletionStamp(progress: playlist.stampProgress, seed: playlist.id,
                                        isPerfect: playlist.isStampGold)
                    .fixedSize()
                    .padding(.top, 16)
                    .padding(.trailing, 10)
                    .allowsHitTesting(false)
            }
        }
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: TicketStyle.fieldRowSpacing) {
            Text(playlist?.title ?? "Выберите подборку")
                .font(Self.nameFont)
                .foregroundStyle(playlist == nil ? TicketStyle.placeholderInk : Color.black)
                .lineLimit(2)
                .minimumScaleFactor(TicketStyle.minimumScale)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: TicketStyle.fieldColumnGap) {
                PlaylistStubField(label: "Пройдено",
                                  value: playlist.map { "\($0.answered)/\($0.total)" } ?? "—",
                                  isPlaceholder: playlist == nil)
                    .frame(width: TicketStyle.fieldYearWidth, alignment: .leading)
                PlaylistStubField(label: "Угадано",
                                  value: playlist.map { "\($0.correct)" } ?? "—",
                                  isPlaceholder: playlist == nil)
                    .frame(width: TicketStyle.fieldVotesWidth, alignment: .leading)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var startButton: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button(action: onStart) {
                TicketBarcodeView(mediaType: mediaType, mode: mode)
                    .contentShape(Rectangle())
            }
            Spacer(minLength: 0)
        }
    }
}

private struct PlaylistStubField: View {
    let label: String
    let value: String
    var isPlaceholder = false

    var body: some View {
        VStack(alignment: .leading, spacing: TicketStyle.fieldLabelSpacing) {
            Text(label)
                .font(TicketStyle.fieldLabel)
                .textCase(.uppercase)
                .tracking(TicketStyle.fieldLabelTracking)
                .lineLimit(1)
            Text(value)
                .font(isPlaceholder ? TicketStyle.fieldPlaceholder : TicketStyle.fieldValue)
                .foregroundStyle(isPlaceholder ? TicketStyle.placeholderInk : Color.black)
                .lineLimit(1)
                .minimumScaleFactor(TicketStyle.minimumScale)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PlaylistCompletionStamp: View {
    let progress: Double
    let seed: String
    var isPerfect = false

    private static let side: CGFloat = 52

    private var pose: (angle: Double, x: CGFloat, y: CGFloat) {
        let hash = PlaylistSeed.hash(seed)
        let a = Double(hash % 1_000) / 1_000
        let b = Double((hash / 1_000) % 1_000) / 1_000
        let c = Double((hash / 1_000_000) % 1_000) / 1_000
        let angle = a < 0.7 ? -(6 + a / 0.7 * 10) : 5 + (a - 0.7) / 0.3 * 7
        return (angle: angle, x: b * 14 - 7, y: c * 8 - 4)
    }

    var body: some View {
        let pose = pose
        Group {
            if isPerfect {
                PlaylistSealStamp(isGold: true)
                    .scaleEffect(1.5)
            } else {
                PlaylistInkStamp(ink: Accent.rewardInk)
            }
        }
        .frame(width: Self.side, height: Self.side)
        .rotationEffect(.degrees(pose.angle))
        .scaleEffect(1 + (1 - progress) * 1.6)
        .opacity(progress)
        .offset(x: pose.x, y: pose.y)
    }
}

struct PlaylistInkStamp: View {
    let ink: Color

    var body: some View {
        Image(systemName: "checkmark.seal")
            .font(.system(size: 20, weight: .heavy))
            .frame(width: 52, height: 52)
            .overlay(Circle().stroke(lineWidth: 2.5))
            .overlay(Circle().inset(by: 5).stroke(lineWidth: 1))
            .foregroundStyle(ink.opacity(0.8))
            .blendMode(.multiply)
    }
}

#Preview("Корешок подборки: пусто и все подборки") {
    PlaylistsPreview { playlists in
        ScrollView {
            VStack(spacing: 16) {
                ForEach([nil] + playlists.playlists.map(\.id), id: \.self) { id in
                    PlaylistStubBody(mediaType: .movie, mode: .collection, playlist: id.flatMap(playlists.ticket(id:)))
                        .modifier(TicketStubFrame(width: 300, edgeStyle: .scalloped))
                        .background(TicketStyle.paper)
                }
            }
            .padding()
        }
        .background(Color.black)
    }
}
