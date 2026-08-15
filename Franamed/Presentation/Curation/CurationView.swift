//
//  CurationView.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 14.08.2026.
//

import SwiftUI

struct CurationView: View {
    @ObservedObject var coordinator: AppCoordinator
    @State private var isShowingProfile = false

    var body: some View {
        NavigationStack(path: $coordinator.curationPath) {
            List {
                Button("Start Curating") {
                    coordinator.showCurationQueue()
                }
            }
            .navigationDestination(for: CurationRoute.self) { route in
                switch route {
                case .queue:
                    Text("Curation placeholder")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $isShowingProfile) {
                Text("Profile placeholder")
            }
        }
    }
}

#Preview {
    CurationView(coordinator: AppCoordinator())
}
