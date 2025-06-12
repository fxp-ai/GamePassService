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
            .get("details", use: self.details)
            .get("availability", use: self.availability)
    }
    
    @Sendable func list(request: Request, context: some RequestContext) async throws -> [String] {
        let market = request.uri.queryParameters.get("market")
        let collectionId = request.uri.queryParameters.get("collectionId")
        return try await self.repository.list(market: market, collectionId: collectionId)
    }
    
    @Sendable func details(request: Request, context: some RequestContext) async throws -> [XboxGame] {
        let productIds = request.uri.queryParameters.get("productIds")
        let language = request.uri.queryParameters.get("language")
        guard let productIds, let language else { throw HTTPError(.badRequest) }
        return try await self.repository.details(productIds: productIds, language: language)
    }
    
    @Sendable func availability(request: Request, context: some RequestContext) async throws -> [String: [AvailabilityPeriod]] {
        let productIds = request.uri.queryParameters.get("productIds")
        let market = request.uri.queryParameters.get("market")
        let collectionId = request.uri.queryParameters.get("collectionId")
        guard let productIds, let market, let collectionId else { throw HTTPError(.badRequest) }
        return try await self.repository.availability(productIds: productIds, market: market, collectionId: collectionId)
    }
}
