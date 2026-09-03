//
//  SessionLoadingView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import SwiftUI

struct SessionLoadingView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    SessionLoadingView()
}
