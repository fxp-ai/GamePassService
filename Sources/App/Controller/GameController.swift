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
            .add(middleware: BasicAuthenticator())
            .get(use: self.list)
            .get("details", use: self.details)
            .get("availability", use: self.availability)
            .get("search", use: self.search)
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
        
        // Try to get from database first
        var games = try await self.repository.details(productIds: productIds, language: language)
        
        // If some games are missing, fetch from Xbox API
        let requestedIds = productIds.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        let foundIds = Set(games.map { $0.productId })
        let missingIds = requestedIds.filter { !foundIds.contains($0) }
        
        if !missingIds.isEmpty {
            // Fetch missing games directly from Xbox API
            guard let lang = Localization.language(language),
                  let market = Localization.market("US") else {
                throw HTTPError(.badRequest, message: "Invalid language or market")
            }
            
            let xboxGames = try await XboxMarketplace.fetchProductInformation(
                gameIds: missingIds,
                language: lang,
                market: market
            )
            games.append(contentsOf: xboxGames)
        }
        
        return games
    }
    
    @Sendable func availability(request: Request, context: some RequestContext) async throws -> [String: [AvailabilityPeriod]] {
        let productIds = request.uri.queryParameters.get("productIds")
        let market = request.uri.queryParameters.get("market")
        let collectionId = request.uri.queryParameters.get("collectionId")
        guard let productIds, let market, let collectionId else { throw HTTPError(.badRequest) }
        return try await self.repository.availability(productIds: productIds, market: market, collectionId: collectionId)
    }
    
    @Sendable func search(request: Request, context: some RequestContext) async throws -> [String] {
        guard let query = request.uri.queryParameters.get("query"),
              let language = request.uri.queryParameters.get("language"),
              let market = request.uri.queryParameters.get("market") else {
            throw HTTPError(.badRequest, message: "Missing required parameters: query, language, market")
        }
        
        guard let lang = Localization.language(language),
              let mkt = Localization.market(market) else {
            throw HTTPError(.badRequest, message: "Invalid language or market")
        }
        
        return try await XboxMarketplace.queryXboxMarketplace(
            query: query,
            language: lang,
            market: mkt
        )
    }
}
