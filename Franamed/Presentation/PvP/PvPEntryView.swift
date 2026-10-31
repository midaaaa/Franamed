//
//  PvPEntryView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.10.2026.
//

import SwiftUI

struct PvPEntryView: View {
    @StateObject private var viewModel: PvPEntryViewModel
    @FocusState private var isCodeFocused: Bool
    @State private var isEditingProfile = false
    @Binding private var pendingCode: String?
    private let mediaFacade: MediaFacadeProtocol
    private let makeSession: (PvPRoomTicket, String) -> any PvPSessionProtocol
    private let onClose: () -> Void

    init(service: any PvPServiceProtocol, mediaFacade: MediaFacadeProtocol, mediaType: MediaType = .movie,
         pendingCode: Binding<String?> = .constant(nil),
         makeSession: @escaping (PvPRoomTicket, String) -> any PvPSessionProtocol, onClose: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: PvPEntryViewModel(service: service, mediaType: mediaType))
        _pendingCode = pendingCode
        self.mediaFacade = mediaFacade
        self.makeSession = makeSession
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            PvPPage {
                profileCard
                modes
                joinCard
            }
            .navigationTitle("С друзьями")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .alert("Не получилось", isPresented: hasError) {
                Button("OK", role: .cancel) { viewModel.dismissError() }
            } message: {
                Text(viewModel.error ?? "")
            }
            .sheet(isPresented: $isEditingProfile) {
                if let profile = viewModel.profile {
                    PvPProfileEditor(profile: profile, isSaving: viewModel.busy == .saving) { update in
                        await viewModel.update(update)
                    }
                }
            }
            .fullScreenCover(item: $viewModel.room) { room in
                PvPRoomView(session: makeSession(room.ticket, room.code), code: room.code,
                            mediaFacade: mediaFacade) {
                    viewModel.room = nil
                }
            }
            .task { await viewModel.load() }
            .task(id: pendingCode) { await joinPending() }
        }
    }

    private var hasError: Binding<Bool> {
        Binding { viewModel.error != nil } set: { if !$0 { viewModel.dismissError() } }
    }

    private func joinPending() async {
        guard let code = pendingCode else { return }
        pendingCode = nil
        viewModel.room = nil
        await viewModel.join(code: code)
    }

    // MARK: Profile

    private var profileCard: some View {
        Button {
            isEditingProfile = true
        } label: {
            PvPCard {
                HStack(spacing: 14) {
                    if let avatar = viewModel.avatar {
                        PvPAvatarView(avatar: avatar, size: 52)
                    } else {
                        Circle().fill(.fill.tertiary).frame(width: 52, height: 52)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        PvPKicker(text: "Ваш ник")
                        Text(viewModel.profile?.name ?? " ")
                            .font(.title3.weight(.semibold))
                            .redacted(reason: viewModel.profile == nil ? .placeholder : [])
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "pencil")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.profile == nil)
    }

    // MARK: Modes

    private var modes: some View {
        VStack(spacing: 12) {
            modeCard(kind: .room, title: "Комната", detail: "До 8 игроков. Кто наберёт больше очков за все фильмы",
                     action: "Создать комнату")
            modeCard(kind: .duel, title: "Дуэль", detail: "Один на один. Отстающий теряет здоровье, пока не кончится",
                     action: "Вызвать на дуэль")
        }
    }

    private func modeCard(kind: PvPRoomKind, title: String, detail: String, action: String) -> some View {
        PvPCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(PvPStyle.title)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                PvPPrimaryButton(title: action, isEnabled: viewModel.busy == nil || viewModel.busy == .creating(kind),
                                 isBusy: viewModel.busy == .creating(kind)) {
                    Task { await viewModel.create(kind) }
                }
            }
        }
    }

    // MARK: Join

    private var joinCard: some View {
        PvPCard {
            VStack(alignment: .leading, spacing: 12) {
                PvPKicker(text: "Войти по коду")
                HStack(spacing: 10) {
                    TextField("", text: $viewModel.code, prompt: Text("123456").foregroundStyle(.white.opacity(0.25)))
                        .font(PvPStyle.code)
                        .keyboardType(.numberPad)
                        .autocorrectionDisabled()
                        .focused($isCodeFocused)
                        .onChange(of: viewModel.code) { _, code in
                            if PvPRoomLink.isValid(code) { isCodeFocused = false }
                        }
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in viewModel.paste(text) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                }
                PvPPrimaryButton(title: "Войти", isEnabled: viewModel.canJoin, isBusy: viewModel.busy == .joining) {
                    isCodeFocused = false
                    Task { await viewModel.join() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Вход") {
    PvPEntryView(service: PvPPreviewService(), mediaFacade: PreviewMediaFacade(), makeSession: PvPPreview.session) {}
        .preferredColorScheme(.dark)
}

#Preview("Вход, комнаты нет") {
    PvPEntryView(service: PvPPreviewService(failure: "room_not_found"), mediaFacade: PreviewMediaFacade(),
                 makeSession: PvPPreview.session) {}
        .preferredColorScheme(.dark)
}

#Preview("Вход по ссылке") {
    @Previewable @State var code: String? = PvPMatchFixtures.roomCode
    PvPEntryView(service: PvPPreviewService(), mediaFacade: PreviewMediaFacade(), pendingCode: $code,
                 makeSession: PvPPreview.session) {}
        .preferredColorScheme(.dark)
}
#endif
