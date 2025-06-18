//
//  GamePostgresRepository.swift
//  GamePassService
//
//  Created by Felix Pultar on 05.06.2025.
//

import Foundation
import XboxKit
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
    
    func details(productIds: String, language: String) async throws -> [XboxGame] {
        let productIdArray = productIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        
        guard !productIdArray.isEmpty else {
            return []
        }
        
        // Create placeholders starting from $2
        let placeholders = (2...(1 + productIdArray.count)).map { "$\($0)" }.joined(separator: ", ")
        
        let query = """
            SELECT
                gd.product_id,
                gd.product_title,
                gd.product_description,
                gd.developer_name,
                gd.publisher_name,
                gd.short_title,
                gd.sort_title,
                gd.short_description,
                gi.file_id,
                gi.height,
                gi.width,
                gi.uri,
                gi.image_purpose,
                gi.image_position_info
            FROM game_descriptions gd
            LEFT JOIN game_images gi ON gd.product_id = gi.product_id AND gi.language = $1
            WHERE gd.product_id IN (\(placeholders))
                AND gd.language = $1
            ORDER BY gd.product_id, gi.image_position_info, gi.image_purpose;
        """
        
        var bindings = PostgresBindings()
        bindings.append(language)       // $1
        
        // Add product IDs starting from $2
        for productId in productIdArray {
            bindings.append(productId)
        }
    
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        let stream = try await client.query(postgresQuery)
        
        var gamesDict: [String: XboxGame] = [:]
        var imageDescriptorsDict: [String: [XboxImageDescriptor]] = [:]
        
        for try await row in stream.decode(
            (
                String, String, String?, String?, String?, String?, String?,
                String?, String?, Int?, Int?, String?, String?, String?
            ).self,
            context: .default
        ) {
            let (
                productId, productTitle, productDescription, developerName,
                publisherName, shortTitle, sortTitle, shortDescription,
                fileId, height, width, uri, imagePurpose, imagePositionInfo
            ) = row
            
            // Create game object if not already created
            if gamesDict[productId] == nil {
                gamesDict[productId] = XboxGame(
                    productId: productId,
                    productTitle: productTitle,
                    productDescription: productDescription,
                    developerName: developerName,
                    publisherName: publisherName,
                    shortTitle: shortTitle,
                    sortTitle: sortTitle,
                    shortDescription: shortDescription,
                    imageDescriptors: nil
                )
                imageDescriptorsDict[productId] = []
            }
            
            // Add image if present and not already added
            if let fileId = fileId {
                let alreadyExists = imageDescriptorsDict[productId]?.contains { $0.fileId == fileId } ?? false
                
                if !alreadyExists {
                    let imageDescriptor = XboxImageDescriptor(
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
            
            return XboxGame(
                productId: game.productId,
                productTitle: game.productTitle,
                productDescription: game.productDescription,
                developerName: game.developerName,
                publisherName: game.publisherName,
                shortTitle: game.shortTitle,
                sortTitle: game.sortTitle,
                shortDescription: game.shortDescription,
                imageDescriptors: images.isEmpty ? nil : images
            )
        }
        
    }
    
    func availability(productIds: String, market: String, collectionId: String) async throws -> [String: [AvailabilityPeriod]] {
        let productIdArray = productIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            
        guard !productIdArray.isEmpty else {
            return [:]  // Return empty dictionary instead of array
        }
        
        let placeholders = (3...(2 + productIdArray.count)).map { "$\($0)" }.joined(separator: ", ")
        
        let query = """
            SELECT
                product_id,
                DATE(available_at) as availability_date
            FROM game_availability
            WHERE product_id IN (\(placeholders))
                AND market = $1
                AND collection_id = $2
            ORDER BY product_id, availability_date;
        """
        
        var bindings = PostgresBindings()
        bindings.append(market)         // $1
        bindings.append(collectionId)   // $2
        
        for productId in productIdArray {
            bindings.append(productId)  // $3 onwards
        }
        
        let postgresQuery = PostgresQuery(unsafeSQL: query, binds: bindings)
        let stream = try await client.query(postgresQuery)
        
        // Group dates by product
        var productDates: [String: [Date]] = [:]
        
        for try await (productId, date) in stream.decode((String, Date).self, context: .default) {
            productDates[productId, default: []].append(date)
        }
        
        let today = Calendar.current.startOfDay(for: Date())
        
        // Build dictionary instead of array
        var result: [String: [AvailabilityPeriod]] = [:]
        
        for productId in productIdArray {
            guard let dates = productDates[productId], !dates.isEmpty else {
                result[productId] = []  // Empty array for products with no availability
                continue
            }
            
            var availabilityPeriods: [AvailabilityPeriod] = []
            var periodStart = dates[0]
            var lastDate = dates[0]
            
            for i in 1..<dates.count {
                let currentDate = dates[i]
                let daysDiff = Calendar.current.dateComponents([.day], from: lastDate, to: currentDate).day ?? 0
                
                if daysDiff > 1 {
                    // Gap found - close current period
                    availabilityPeriods.append(AvailabilityPeriod(start: periodStart, end: lastDate))
                    periodStart = currentDate
                }
                lastDate = currentDate
            }
            
            // Handle the last period
            if lastDate >= today {
                // Still ongoing
                availabilityPeriods.append(AvailabilityPeriod(start: periodStart, end: nil))
            } else {
                // Ended in the past
                availabilityPeriods.append(AvailabilityPeriod(start: periodStart, end: lastDate))
            }
            
            result[productId] = availabilityPeriods.sorted { $0.start < $1.start }
        }
        
        return result
    }
    
    func getImageUrl(productId: String, purpose: String, language: String) async throws -> String? {
        var bindings = PostgresBindings()
        bindings.append(productId)
        bindings.append(language)
        
        var query: String
        
        // Check if this is a screenshot with position
        if purpose.starts(with: "Screenshot-") {
            // Split the combined purpose
            let position = String(purpose.dropFirst(11)) // Remove "Screenshot-"
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
