//
//  ImageController.swift
//  GamePassService
//
//  Created by Felix Pultar on 07.06.2025.
//

import Foundation
import Hummingbird
import PostgresNIO
import SwiftGD
import XboxKit

struct ImageController<Repository: GameRepository> {
    let repository: Repository
    let cache = ImageCache()
    
    var endpoints: RouteCollection<AppRequestContext> {
        RouteCollection(context: AppRequestContext.self)
            .get(":productId", use: serveImage)
    }
    
    @Sendable func serveImage(request: Request, context: some RequestContext) async throws -> Response {
        let productId = try context.parameters.require("productId", as: String.self)
        
        guard let language = request.uri.queryParameters.get("language") else {
            throw HTTPError(.badRequest, message: "Missing required parameter: language")
        }

        guard let purpose = request.uri.queryParameters.get("purpose") else {
            throw HTTPError(.badRequest, message: "Missing required parameter: purpose")
        }
        
        let widthString = request.uri.queryParameters.get("width")
        let requestedWidth = widthString.flatMap { Int($0) }
        
        // Helper function to create response from data
        func createResponse(from data: Data) -> Response {
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            return Response(
                status: .ok,
                headers: [
                    .contentType: "image/jpeg",
                    .cacheControl: "max-age=86400"
                ],
                body: ResponseBody(byteBuffer: buffer)
            )
        }
        
        // STEP 1: For original size (no width specified), check cache directly
        if requestedWidth == nil {
            if let cachedData = cache.get(productId: productId, language: language, purpose: purpose, width: nil, height: nil) {
                return createResponse(from: cachedData)
            }
        }
        
        // STEP 2: For resized images, we have a problem - we don't know the height yet
        // Let's check if we have ANY cached version by scanning the cache directory
        // This is a bit hacky but works
        if let requestedWidth = requestedWidth {
            let productDir = cache.cacheDirectory
                .appendingPathComponent(productId)
                .appendingPathComponent(language)
            
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: productDir.path) {
                // Look for a file matching our pattern
                let searchPattern = "\(purpose)-\(requestedWidth)x"
                if let files = try? fileManager.contentsOfDirectory(atPath: productDir.path) {
                    for file in files {
                        if file.hasPrefix(searchPattern) && file.hasSuffix(".jpg") {
                            // Found a cached file! Extract height from filename
                            // Format: "BoxArt-180x270.jpg"
                            let components = file.dropLast(4).split(separator: "x")
                            if components.count == 2,
                               let height = Int(components[1]) {
                                if let cachedData = cache.get(productId: productId, language: language, purpose: purpose, width: requestedWidth, height: height) {
                                    return createResponse(from: cachedData)
                                }
                            }
                        }
                    }
                }
            }
        }
        
        // STEP 3: Not in cache, need to download
        
        // First, try to get URL from database
        var imageUrl = try await repository.getImageUrl(productId: productId, purpose: purpose, language: language)
        
        // If not in database, fetch from Xbox API (marketplace game)
        if imageUrl == nil {
            guard let lang = Localization.language(language),
                  let market = Localization.market("US") else {
                throw HTTPError(.badRequest, message: "Invalid language or market")
            }
            
            let games = try await XboxMarketplace.fetchProductInformation(
                gameIds: [productId],
                language: lang,
                market: market
            )
            
            if let game = games.first,
               let descriptors = game.imageDescriptors {
                
                // Handle screenshot with position
                if purpose.starts(with: "Screenshot_") {
                    let position = String(purpose.dropFirst(11))
                    imageUrl = descriptors.first { descriptor in
                        descriptor.imagePurpose == "Screenshot" &&
                        descriptor.imagePositionInfo == position
                    }?.uri
                } else {
                    // Find the requested image type
                    imageUrl = descriptors.first { descriptor in
                        descriptor.imagePurpose == purpose
                    }?.uri
                }
            }
        }
        
        // If we still don't have a URL, the image doesn't exist
        guard let imageUrl = imageUrl else {
            throw HTTPError(.notFound, message: "Image not found for product: \(productId), purpose: \(purpose)")
        }
        
        // STEP 4: Download from Microsoft
        let fullUrl = URL(string: "https:" + imageUrl)!
        let (imageData, _) = try await URLSession.shared.data(from: fullUrl)
        
        // STEP 5: Process and cache ONLY the requested size
        var finalData = imageData
        var finalWidth: Int? = nil
        var finalHeight: Int? = nil
        
        if let requestedWidth = requestedWidth {
            // Calculate dimensions and resize
            let originalImage = try Image(data: imageData)
            let aspectRatio = Double(originalImage.size.height) / Double(originalImage.size.width)
            let calculatedHeight = Int(Double(requestedWidth) * aspectRatio)
            
            // Resize
            finalData = try await resizeImage(data: imageData, toWidth: requestedWidth)
            finalWidth = requestedWidth
            finalHeight = calculatedHeight
        }
        
        // Cache ONLY the size that was requested
        cache.set(productId: productId, language: language, purpose: purpose, width: finalWidth, height: finalHeight, data: finalData)
        
        return createResponse(from: finalData)
    }
    
}
