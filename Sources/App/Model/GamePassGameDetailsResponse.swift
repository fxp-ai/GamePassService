//
//  GamePassGameHistoryResponse.swift
//  GamePassService
//
//  Created by Felix Pultar on 10.06.2025.
//

import Foundation
import XboxKit

struct GamePassGameDetailsResponse: Equatable, Codable, Sendable {
    let game: XboxGame
    let availabilityHistory: [Date]
}
