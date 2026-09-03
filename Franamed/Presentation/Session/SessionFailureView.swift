//
//  SessionFailureView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import SwiftUI

struct SessionFailureView: View {
    let message: String
    let onRetry: () async -> Void

    @State private var isBusy = false

    var body: some View {
        ContentUnavailableView {
            Label("Нет связи с сервером", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(message)
        } actions: {
            Button("Повторить") {
                Task {
                    isBusy = true
                    await onRetry()
                    isBusy = false
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
    }
}

#Preview {
    SessionFailureView(message: "Сервер вернул неожиданный ответ", onRetry: {})
}
