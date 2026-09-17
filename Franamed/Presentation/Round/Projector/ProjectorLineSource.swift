//
//  ProjectorLineSource.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 16.08.2026.
//

import SwiftUI

struct ProjectorLineSource: View {
    static let height: CGFloat = 12

    var width: CGFloat = 84

    var body: some View {
        ZStack {
            Capsule().fill(Color.white).frame(width: width, height: 3)
            Capsule().fill(Color.white.opacity(0.6))
                .frame(width: width * 1.3, height: Self.height)
                .blur(radius: 11)
        }
        .frame(height: Self.height)
    }
}

#Preview {
    ProjectorLineSource()
        .padding()
        .background(Color.black)
}
