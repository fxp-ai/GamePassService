//
//  GameRepository.swift
//  GamePassService
//
//  Created by Felix Pultar on 05.06.2025.
//

import Foundation
import Hummingbird
import GamePassKit
import GamePassShared

protocol GameRepository: Sendable {
    func list(market: String?, collectionId: String?) async throws -> [String]
    func details(productIds: String, language: String, market: String, collectionId: String) async throws -> [GamePassGame]
}
