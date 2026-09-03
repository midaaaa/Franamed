//
//  SignInView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import SwiftUI

struct SignInView: View {
    let onPlay: () async -> Void

    @State private var isBusy = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "film.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Franamed")
                    .font(.largeTitle.bold())

                Text("Угадай фильм по кадрам")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task {
                        isBusy = true
                        await onPlay()
                        isBusy = false
                    }
                } label: {
                    Text("Играть")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Text("Аккаунт хранится на этом устройстве. Прогресс потеряется при удалении приложения.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 32)
        .overlay {
            if isBusy {
                ProgressView()
                    .controlSize(.large)
            }
        }
    }
}

#Preview {
    SignInView(onPlay: {})
}
