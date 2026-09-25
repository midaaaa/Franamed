//
//  WaitingSpinner.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 25.09.2026.
//

import SwiftUI

struct WaitingSpinner: View {
    var hidesFromCapture = false

    var body: some View {
        if hidesFromCapture {
            ProtectedContent(isProtected: true) { spinner }
        } else {
            spinner
        }
    }

    private var spinner: some View {
        ProgressView().tint(.white)
    }
}
