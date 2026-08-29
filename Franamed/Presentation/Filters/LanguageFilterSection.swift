//
//  LanguageFilterSection.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 19.08.2026.
//

import SwiftUI

struct LanguageFilterSection: View {
    private static let defaultLanguages: [Language] = [
        Language(code: "en", name: "Английский"), Language(code: "ru", name: "Русский"),
        Language(code: "ja", name: "Японский"), Language(code: "fr", name: "Французский"),
        Language(code: "es", name: "Испанский")
    ]

    private static let moreLanguages: [Language] = [
        Language(code: "ko", name: "Корейский"), Language(code: "de", name: "Немецкий"),
        Language(code: "it", name: "Итальянский"), Language(code: "zh", name: "Китайский"),
        Language(code: "hi", name: "Хинди"), Language(code: "pt", name: "Португальский"),
        Language(code: "tr", name: "Турецкий"), Language(code: "th", name: "Тайский"),
        Language(code: "sv", name: "Шведский"), Language(code: "da", name: "Датский"),
        Language(code: "ar", name: "Арабский"), Language(code: "id", name: "Индонезийский"),
        Language(code: "vi", name: "Вьетнамский"), Language(code: "pl", name: "Польский"),
        Language(code: "nl", name: "Нидерландский"), Language(code: "fi", name: "Финский"),
        Language(code: "no", name: "Норвежский"), Language(code: "cs", name: "Чешский"),
        Language(code: "el", name: "Греческий"), Language(code: "he", name: "Иврит"),
        Language(code: "uk", name: "Украинский"), Language(code: "ro", name: "Румынский"),
        Language(code: "hu", name: "Венгерский"), Language(code: "fa", name: "Персидский"),
        Language(code: "bn", name: "Бенгальский")
    ]

    @Binding var selectedCodes: [String]?
    @State private var showsAllLanguages = false

    private var orderedLanguages: [Language] {
        var result = showsAllLanguages ? Self.defaultLanguages + Self.moreLanguages : Self.defaultLanguages

        if let systemCode = Locale.current.language.languageCode?.identifier,
           let index = result.firstIndex(where: { $0.code == systemCode }) {
            result.insert(result.remove(at: index), at: 0)
        }

        if let englishIndex = result.firstIndex(where: { $0.code == "en" }), englishIndex != 0 {
            result.insert(result.remove(at: englishIndex), at: 1)
        }

        return result
    }

    var body: some View {
        Section {
            anyLanguageRow

            ForEach(orderedLanguages) { language in
                languageRow(language)
            }

            Button(showsAllLanguages ? "Скрыть" : "Показать все") {
                showsAllLanguages.toggle()
            }
        } header: {
            header
        } footer: {
            Text("Достаточно совпадения хотя бы с одним языком.")
        }
    }

    private var anyLanguageRow: some View {
        Button {
            selectedCodes = nil
        } label: {
            HStack {
                Text("Любой")
                Spacer()
                if selectedCodes == nil {
                    Image(systemName: "checkmark")
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func languageRow(_ language: Language) -> some View {
        Button {
            toggle(language.code)
        } label: {
            HStack {
                Text(language.name)
                Spacer()
                if isSelected(language.code) {
                    Image(systemName: "checkmark")
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private var header: some View {
        HStack {
            Text("Язык оригинала")
            Spacer()
            if selectedCodes?.isEmpty == false {
                Button("Очистить") {
                    selectedCodes = nil
                }
                .font(.caption)
                .textCase(nil)
            }
        }
    }

    private func isSelected(_ code: String) -> Bool {
        selectedCodes?.contains(code) == true
    }

    private func toggle(_ code: String) {
        var current = selectedCodes ?? []
        if let index = current.firstIndex(of: code) {
            current.remove(at: index)
        } else {
            current.append(code)
        }
        selectedCodes = current.isEmpty ? nil : current
    }
}

private struct LanguageFilterSectionPreview: View {
    @State var selectedCodes: [String]?

    var body: some View {
        Form {
            LanguageFilterSection(selectedCodes: $selectedCodes)
        }
    }
}

#Preview {
    LanguageFilterSectionPreview(selectedCodes: nil)
}
