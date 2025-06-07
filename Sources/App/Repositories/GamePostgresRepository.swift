//
//  GamePostgresRepository.swift
//  GamePassService
//
//  Created by Felix Pultar on 05.06.2025.
//

import Foundation
import GamePassKit
import GamePassShared
import Hummingbird
import Logging
import PostgresNIO

struct GamePostgresRepository: GameRepository {

    let client: PostgresClient
    let logger: Logger

    func list(market: String?, collectionId: String?) async throws -> [String] {
        var games: [String] = []

        var bindings = PostgresBindings()
        var query = "SELECT DISTINCT ON (product_id) product_id FROM game_availability"
        var conditions: [String] = []

        if let market = market {
            conditions.append("market = $1")
            bindings.append(market)
        }

        if let collectionId = collectionId {
            conditions.append("collection_id = $2")
            bindings.append(collectionId)
        }

        // Add WHERE clause if there are any conditions
        if !conditions.isEmpty {
            query += " WHERE " + conditions.joined(separator: " AND ")
        }

        // Add ordering
        query += " ORDER BY product_id, available_at DESC;"

        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        let stream = try await client.query(postgresQuery)

        for try await (product_id) in stream.decode(
            (String.self),
            context: .default
        ) {
            games.append(product_id)
        }

        return games
    }
    
    func details(productIds: String, language: String, market: String, collectionId: String) async throws -> [GamePassGame] {
        let productIdArray = productIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        guard !productIdArray.isEmpty else {
            return []
        }
        
        // Create placeholders for both IN clauses
        let placeholders = (4...(3 + productIdArray.count)).map { "$\($0)" }.joined(separator: ", ")
        
        let query = """
            WITH game_data AS (
                SELECT
                    product_id,
                    product_title,
                    product_description,
                    developer_name,
                    publisher_name,
                    short_title,
                    sort_title,
                    short_description
                FROM game_descriptions
                WHERE product_id IN (\(placeholders))
                    AND language = $1
            ),
            availability_summary AS (
                SELECT
                    product_id,
                    array_agg(DISTINCT DATE(available_at) ORDER BY DATE(available_at) DESC) as availability_dates
                FROM game_availability
                WHERE product_id IN (\(placeholders))
                    AND market = $2
                    AND collection_id = $3
                GROUP BY product_id
            )
            SELECT
                gd.*,
                gi.file_id,
                gi.height,
                gi.width,
                gi.uri,
                gi.image_purpose,
                gi.image_position_info,
                av.availability_dates
            FROM game_data gd
            LEFT JOIN game_images gi ON gd.product_id = gi.product_id AND gi.language = $1
            LEFT JOIN availability_summary av ON gd.product_id = av.product_id
            ORDER BY gd.product_id, gi.image_position_info, gi.image_purpose;
        """
        
        var bindings = PostgresBindings()
        bindings.append(language)       // $1
        bindings.append(market)         // $2
        bindings.append(collectionId)   // $3
        
        // Add product IDs for both IN clauses
        for productId in productIdArray {
            bindings.append(productId)
        }
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        let stream = try await client.query(postgresQuery)
        
        var gamesDict: [String: GamePassGame] = [:]
        var imageDescriptorsDict: [String: [GamePassImageDescriptor]] = [:]
        var availabilityDict: [String: [Date]] = [:]
        
        for try await row in stream.decode(
            (
                String, String, String?, String?, String?, String?, String?,
                String?, String?, Int?, Int?, String?, String?, String?, [Date]?
            ).self,
            context: .default
        ) {
            let (
                productId, productTitle, productDescription, developerName,
                publisherName, shortTitle, sortTitle, shortDescription,
                fileId, height, width, uri, imagePurpose, imagePositionInfo,
                availabilityDates
            ) = row
            
            // Create game object if not already created
            if gamesDict[productId] == nil {
                gamesDict[productId] = GamePassGame(
                    productId: productId,
                    productTitle: productTitle,
                    productDescription: productDescription,
                    developerName: developerName,
                    publisherName: publisherName,
                    shortTitle: shortTitle,
                    sortTitle: sortTitle,
                    shortDescription: shortDescription,
                    imageDescriptors: nil,
                    availabilityHistory: nil
                )
                imageDescriptorsDict[productId] = []
                // Store availability dates from first row
                availabilityDict[productId] = availabilityDates ?? []
            }
            
            // Add image if present and not already added
            if let fileId = fileId {
                let alreadyExists = imageDescriptorsDict[productId]?.contains { $0.fileId == fileId } ?? false
                
                if !alreadyExists {
                    let imageDescriptor = GamePassImageDescriptor(
                        fileId: fileId,
                        height: height,
                        width: width,
                        uri: uri,
                        imagePurpose: imagePurpose,
                        imagePositionInfo: imagePositionInfo
                    )
                    imageDescriptorsDict[productId]?.append(imageDescriptor)
                }
            }
        }
        
        // Convert to array with all data
        return gamesDict.map { (productId, game) in
            let images = imageDescriptorsDict[productId] ?? []
            let availability = availabilityDict[productId] ?? []
            
            return GamePassGame(
                productId: game.productId,
                productTitle: game.productTitle,
                productDescription: game.productDescription,
                developerName: game.developerName,
                publisherName: game.publisherName,
                shortTitle: game.shortTitle,
                sortTitle: game.sortTitle,
                shortDescription: game.shortDescription,
                imageDescriptors: images.isEmpty ? nil : images,
                availabilityHistory: availability.isEmpty ? nil : availability
            )
        }
    }
    
    func getImageUrl(productId: String, purpose: String, language: String) async throws -> String? {
        var bindings = PostgresBindings()
        bindings.append(productId)
        bindings.append(language)
        
        var query: String
        
        // Check if this is a screenshot with position
        if purpose.starts(with: "Screenshot_") {
            // Split the combined purpose
            let position = String(purpose.dropFirst(11)) // Remove "Screenshot_"
            bindings.append("Screenshot")
            bindings.append(position)
            
            query = """
                SELECT uri FROM game_images
                WHERE product_id = $1 AND language = $2 
                AND image_purpose = $3 AND image_position_info = $4
                LIMIT 1
            """
        } else {
            // Normal query for other image types
            bindings.append(purpose)
            
            query = """
                SELECT uri FROM game_images
                WHERE product_id = $1 AND language = $2 AND image_purpose = $3
                LIMIT 1
            """
        }
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        let stream = try await client.query(postgresQuery)
        
        for try await (uri) in stream.decode(String.self, context: .default) {
            return uri
        }
        
        return nil
    }

}
