//
//  GameController.swift
//  GamePassService
//
//  Created by Felix Pultar on 05.06.2025.
//

import Foundation
import Hummingbird
import XboxKit

struct GameController<Repository: GameRepository> {
    let repository: Repository
    var endpoints: RouteCollection<AppRequestContext> {
        return RouteCollection(context: AppRequestContext.self)
            .get(use: self.list)
            .get(":productIds", use: self.details)
    }
    
    @Sendable func list(request: Request, context: some RequestContext) async throws -> [String] {
        let market = request.uri.queryParameters.get("market")
        let collectionId = request.uri.queryParameters.get("collectionId")
        return try await self.repository.list(market: market, collectionId: collectionId)
    }
    
    @Sendable func details(request: Request, context: some RequestContext) async throws -> [GamePassGameDetailsResponse] {
        let productIds = try context.parameters.require("productIds", as: String.self)
        let language = request.uri.queryParameters.get("language")
        let market = request.uri.queryParameters.get("market")
        let collectionId = request.uri.queryParameters.get("collectionId")
        guard let language, let market, let collectionId else { throw HTTPError(.badRequest) }
        return try await self.repository.details(productIds: productIds, language: language, market: market, collectionId: collectionId)
    }
}
