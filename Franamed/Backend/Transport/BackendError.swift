//
//  BackendError.swift
//  Franamed
//
//  Created by Дмитрий Филимонов on 30.08.2026.
//

import Foundation

enum BackendError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case api(status: Int, code: String, message: String)
    case decoding(String)
    case notSignedIn
    case keychainFailure(OSStatus)
    case randomGeneratorUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Не удалось собрать адрес запроса"
        case .invalidResponse: "Сервер вернул неожиданный ответ"
        case let .api(_, _, message): message
        case let .decoding(detail): "Не удалось разобрать ответ: \(detail)"
        case .notSignedIn: "Нужно войти в аккаунт"
        case let .keychainFailure(status): "Не удалось сохранить данные входа (код \(status))"
        case .randomGeneratorUnavailable: "Не удалось создать ключ устройства"
        }
    }

    var isPoolExhausted: Bool {
        if case let .api(_, code, _) = self { return code == "pool_exhausted" || code == "no_matches" }
        return false
    }

    var isNotSignedIn: Bool {
        if case .notSignedIn = self { return true }
        return false
    }

    var isCredentialRejection: Bool {
        if case let .api(status, _, _) = self { return (400..<500).contains(status) }
        return false
    }
}
