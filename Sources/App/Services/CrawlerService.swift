//
//  CrawlerService.swift
//  GamePassService
//
//  Created by Felix Pultar on 06.06.2025.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Logging
import XboxKit
import PostgresNIO
import Hummingbird

// Crawler service that manages the crawling process
actor CrawlerService {
    private let logger: Logger
    private let postgresClient: PostgresClient
    private var isRunning = false
    private var lastRunDate: Date?
    private var currentTask: Task<Void, Error>?
    private let pythonMetadataServiceURL = "http://localhost:9090/crawl"
    
    // Configuration
    private let defaultLanguage = Localization.language("en-us")!
    private let defaultMarket = Localization.market("US")!
    private let collectionIds = [
        GamePassCatalog.kGamePassConsoleIdentifier, GamePassCatalog.kGamePassCoreIdentifier,
        GamePassCatalog.kGamePassStandardIdentifier, GamePassCatalog.kGamePassPcIdentifier,
        GamePassCatalog.kGamePassPcSecondaryIdentifier,
        GamePassCatalog.kGamePassConsoleSecondaryIdentifier,
        GamePassCatalog.kConsoleDayOneReleasesIdentifier,
        GamePassCatalog.kPcDayOneReleasesIdentifier,
        GamePassCatalog.kConsoleMostPopularIdentifier, GamePassCatalog.kPcMostPopularIdentifier,
        GamePassCatalog.kGamePassCoreMostPopularIdentifier,
        GamePassCatalog.kGamePassStandardMostPopularIdentifier,
        GamePassCatalog.kCloudMostPopularIdentifier,
        GamePassCatalog.kConsoleRecentlyAddedIdentifier,
        GamePassCatalog.kPcRecentlyAddedIdentifier,
        GamePassCatalog.kGamePassStandardRecentlyAddedIdentifier,
        GamePassCatalog.kConsoleComingToIdentifier, GamePassCatalog.kPcComingToIdentifier,
        GamePassCatalog.kGamePassStandardComingToIdentifier,
        GamePassCatalog.kConsoleLeavingSoonIdentifier, GamePassCatalog.kPcLeavingSoonIdentifier,
        GamePassCatalog.kGamePassStandardLeavingSoonIdentifier,
        GamePassCatalog.kUbisoftConsoleIdentifier, GamePassCatalog.kUbisoftPcIdentifier,
        GamePassCatalog.kEAPlayConsoleIdentifier, GamePassCatalog.kEAPlayPcIdentifier,
        GamePassCatalog.kEAPlayTrialConsoleIdentifier, GamePassCatalog.kEAPlayTrialPcIdentifier,
    ]
    
    init(logger: Logger, postgresClient: PostgresClient) {
        self.logger = logger
        self.postgresClient = postgresClient
    }
    
    // Status information
    struct CrawlStatus: Codable, ResponseEncodable {
        let isRunning: Bool
        let lastRunDate: Date?
    }
    
    func getStatus() -> CrawlStatus {
        CrawlStatus(isRunning: isRunning, lastRunDate: lastRunDate)
    }
    
    // Start crawling if not already running
    func startCrawl() async throws -> CrawlStartResult {
        guard !isRunning else {
            return .alreadyRunning
        }
        
        isRunning = true
        
        // Start the crawl in a separate task
        currentTask = Task {
            defer {
                self.isRunning = false
                self.lastRunDate = Date()
                self.currentTask = nil
            }
            
            do {
                try await performCrawl()
                logger.info("Crawl completed successfully")
            } catch {
                logger.error("Crawl failed: \(error)")
                throw error
            }
        }
        
        return .started
    }
    
    // Cancel current crawl if running
    func cancelCrawl() {
        currentTask?.cancel()
    }
    
    private func performCrawl() async throws {
        logger.info("Starting Game Pass crawler...")
        
        var gamesForMetadataCrawl: [[String: String]] = []
        
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            // Track markets that have games
            var marketsWithGames: Set<Market> = []
            
            // Phase 1: Fetch game collections and track active markets
            let games = try await withThrowingTaskGroup(of: (market: Market, gameIds: [String]).self) { fetchGroup in
                for collectionId in collectionIds {
                    for market in Localization.markets {
                        fetchGroup.addTask {
                            try Task.checkCancellation()
                            
                            let gameCollection = try? await GamePassCatalog.fetchGameCollection(
                                for: collectionId,
                                language: self.defaultLanguage,
                                market: market
                            )
                            
                            if let gameCollection {
                                self.logger.info("\(gameCollection.gameIds.count) games found for \(collectionId) in \(market.isoCode)")
                                
                                try await self.saveGameAvailibility(
                                    collectionId: collectionId,
                                    gameIds: gameCollection.gameIds,
                                    market: market.isoCode,
                                    date: Date()
                                )
                                return (market: market, gameIds: gameCollection.gameIds)
                            } else {
                                return (market: market, gameIds: [])
                            }
                        }
                    }
                }
                
                // Collect results and track which markets have games
                var collectedGames: Set<String> = []
                for try await (market, gameIds) in fetchGroup {
                    if !gameIds.isEmpty {
                        marketsWithGames.insert(market)
                        collectedGames.formUnion(gameIds)
                    }
                }
                return Array(collectedGames)
            }
            
            // Phase 2: Determine required languages based on active markets
            var requiredLanguages: Set<Language> = []
            for market in marketsWithGames {
                let marketLanguages = Localization.languages(in: market)
                requiredLanguages.formUnion(marketLanguages)
            }
            
            logger.info("Active markets: \(marketsWithGames.map { $0.isoCode })")
            logger.info("Required languages: \(requiredLanguages.map { $0.localeCode }) (\(requiredLanguages.count) out of \(Localization.languages.count) total)")
            
            // Phase 3: Fetch game details only for required languages
            try await withThrowingTaskGroup(of: [[String: String]].self) { fetchGroup in
                for language in requiredLanguages {
                    fetchGroup.addTask {
                        try Task.checkCancellation()
                        
                        var collectedGamesForLanguage: [[String: String]] = []
                        let chunks = games.chunked(into: 20)
                        
                        for (index, chunk) in chunks.enumerated() {
                            try Task.checkCancellation()
                            
                            self.logger.info(">>> Fetching game descriptions for \(language.localeCode) - chunk \(index + 1)/\(chunks.count)")
                            let gamesInfo = try await XboxMarketplace.fetchProductInformation(
                                gameIds: chunk,
                                language: language,
                                market: self.defaultMarket
                            )
                            
                            self.logger.info(">>> Saving game descriptions for \(language.localeCode) - chunk \(index + 1)/\(chunks.count)")
                            try await self.saveGameDescriptions(
                                games: gamesInfo,
                                language: language.localeCode,
                                market: self.defaultMarket.isoCode
                            )
                            
                            // Collect games for Python metadata crawl if this is default language/market
                            if language == self.defaultLanguage && self.defaultMarket == Localization.market("US")! {
                                for game in gamesInfo {
                                    collectedGamesForLanguage.append([
                                        "productId": game.productId,
                                        "productTitle": game.productTitle,
                                        "shortTitle": game.shortTitle ?? "",
                                        "sortTitle": game.sortTitle ?? ""
                                    ])
                                }
                            }
                            
                            self.logger.info(">>> Saving game images for \(language.localeCode) - chunk \(index + 1)/\(chunks.count)")
                            try await self.saveGameImages(
                                games: gamesInfo,
                                language: language.localeCode,
                                market: self.defaultMarket.isoCode
                            )
                        }
                        
                        return collectedGamesForLanguage
                    }
                }
                
                // Collect games from all language tasks
                for try await languageGames in fetchGroup {
                    gamesForMetadataCrawl.append(contentsOf: languageGames)
                }
            }
        }
        
        // Trigger Python metadata crawl for default language/market games
        if !gamesForMetadataCrawl.isEmpty {
            logger.info("Triggering Python metadata crawl for \(gamesForMetadataCrawl.count) games")
            await triggerPythonMetadataCrawl(games: gamesForMetadataCrawl)
        }
    }
    
    private func triggerPythonMetadataCrawl(games: [[String: String]]) async {
        do {
            let url = URL(string: pythonMetadataServiceURL)!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let requestBody = ["games": games]
            request.httpBody = try JSONEncoder().encode(requestBody)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode == 200 || httpResponse.statusCode == 202 {
                logger.info("Successfully triggered Python metadata crawl")
            } else {
                logger.error("Python metadata crawl request failed")
            }
            
        } catch {
            logger.error("Failed to trigger Python metadata crawl: \(error)")
            // Don't fail the main crawl if metadata crawl fails
        }
    }
    
    // Database save methods
    private func saveGameAvailibility(collectionId: String, gameIds: [String], market: String, date: Date) async throws {
        let query = """
            INSERT INTO game_availability (collection_id, market, product_id, available_at)
            SELECT $1, $2, unnest($3::text[]), $4;
            """
        
        var bindings = PostgresBindings()
        bindings.append(collectionId)
        bindings.append(market)
        bindings.append(gameIds)
        bindings.append(date)
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        try await postgresClient.query(postgresQuery)
    }
    
    private func saveGameDescriptions(games: [XboxGame], language: String, market: String) async throws {
        let query = """
            INSERT INTO game_descriptions (product_id, language, product_title, product_description, developer_name, publisher_name, short_title, sort_title, short_description)
            SELECT unnest($1::text[]), $2, unnest($3::text[]), unnest($4::text[]), unnest($5::text[]), unnest($6::text[]), unnest($7::text[]), unnest($8::text[]), unnest($9::text[])
            ON CONFLICT (product_id, language)
            DO UPDATE SET
                product_title = EXCLUDED.product_title,
                product_description = EXCLUDED.product_description,
                developer_name = EXCLUDED.developer_name,
                publisher_name = EXCLUDED.publisher_name,
                short_title = EXCLUDED.short_title,
                sort_title = EXCLUDED.sort_title,
                short_description = EXCLUDED.short_description;
            """
        
        var bindings = PostgresBindings()
        bindings.append(games.map { $0.productId })
        bindings.append(language)
        bindings.append(games.map { $0.productTitle })
        bindings.append(games.map { $0.productDescription ?? "" })
        bindings.append(games.map { $0.developerName ?? "" })
        bindings.append(games.map { $0.publisherName ?? "" })
        bindings.append(games.map { $0.shortTitle ?? "" })
        bindings.append(games.map { $0.sortTitle ?? "" })
        bindings.append(games.map { $0.shortDescription ?? "" })
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        try await postgresClient.query(postgresQuery)
    }
    
    private func saveGameImages(games: [XboxGame], language: String, market: String) async throws {
        // Flatten games and their image descriptors
        var productIds: [String] = []
        var productTitles: [String] = []
        var fileIds: [String] = []
        var heights: [Int] = []
        var widths: [Int] = []
        var uris: [String] = []
        var imagePurposes: [String] = []
        var imagePositionInfos: [String] = []
        
        for game in games {
            if let imageDescriptors = game.imageDescriptors {
                for descriptor in imageDescriptors {
                    productIds.append(game.productId)
                    productTitles.append(game.productTitle)
                    fileIds.append(descriptor.fileId ?? "")
                    heights.append(descriptor.height ?? -1)
                    widths.append(descriptor.width ?? -1)
                    uris.append(descriptor.uri ?? "")
                    imagePurposes.append(descriptor.imagePurpose ?? "")
                    imagePositionInfos.append(descriptor.imagePositionInfo ?? "")
                }
            }
        }
        
        let query = """
            INSERT INTO game_images (product_id, language, file_id, height, width, uri, image_purpose, image_position_info)
            SELECT unnest($1::text[]), $2, unnest($3::text[]), unnest($4::int[]), unnest($5::int[]), unnest($6::text[]), unnest($7::text[]), unnest($8::text[])
            ON CONFLICT (product_id, file_id, language, image_purpose, image_position_info)
            DO UPDATE SET
                uri = EXCLUDED.uri,
                height = EXCLUDED.height,
                width = EXCLUDED.width
            """
        
        var bindings = PostgresBindings()
        bindings.append(productIds)         // $1
        bindings.append(language)           // $2
        bindings.append(fileIds)            // $3
        bindings.append(heights)            // $4
        bindings.append(widths)             // $5
        bindings.append(uris)               // $6
        bindings.append(imagePurposes)      // $7
        bindings.append(imagePositionInfos) // $8
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        try await postgresClient.query(postgresQuery)
    }
    
    enum CrawlStartResult {
        case started
        case alreadyRunning
    }
}

// Extension to chunk arrays
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
