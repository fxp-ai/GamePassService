//
//  GamePassGameHistoryResponse.swift
//  GamePassService
//
//  Created by Felix Pultar on 10.06.2025.
//

import Foundation
import XboxKit

public struct GamePassGameDetailsResponse: Equatable, Codable, Sendable {
    public let game: XboxGame
    public let availabilityHistory: [Date]
    public init(game: XboxGame, availabilityHistory: [Date]) {
        self.game = game
        self.availabilityHistory = availabilityHistory
    }
}
