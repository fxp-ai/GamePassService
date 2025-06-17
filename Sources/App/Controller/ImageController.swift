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
        
        // Width is optional
        let widthString = request.uri.queryParameters.get("width")
        let width = widthString.flatMap { Int($0) }
        
        // Try database first
        var imageUrl = try await repository.getImageUrl(productId: productId, purpose: purpose, language: language)
        
        // If not found, fetch from Xbox API
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
        
        if let imageUrl {
            // Fetch from Microsoft
            let (imageData, _) = try await URLSession.shared.data(from: URL(string: "https:" + imageUrl)!)
            
            // Get original dimensions to calculate height if resizing
            var finalData = imageData
            var finalWidth: Int? = nil
            var finalHeight: Int? = nil
            
            if let width = width {
                // Load image to get dimensions
                let originalImage = try Image(data: imageData)
                let aspectRatio = Double(originalImage.size.height) / Double(originalImage.size.width)
                let height = Int(Double(width) * aspectRatio)
                
                // Check cache with proper dimensions
                if let cachedData = cache.get(productId: productId, language: language, purpose: purpose, width: width, height: height) {
                    var buffer = ByteBuffer()
                    buffer.writeBytes(cachedData)
                    
                    return Response(
                        status: .ok,
                        headers: [
                            .contentType: "image/jpeg",
                            .cacheControl: "max-age=86400"
                        ],
                        body: ResponseBody(byteBuffer: buffer)
                    )
                }
                
                // Resize if not cached
                finalData = try await resizeImage(data: imageData, toWidth: width)
                finalWidth = width
                finalHeight = height
            } else {
                // Check cache for original
                if let cachedData = cache.get(productId: productId, language: language, purpose: purpose, width: nil, height: nil) {
                    var buffer = ByteBuffer()
                    buffer.writeBytes(cachedData)
                    
                    return Response(
                        status: .ok,
                        headers: [
                            .contentType: "image/jpeg",
                            .cacheControl: "max-age=86400"
                        ],
                        body: ResponseBody(byteBuffer: buffer)
                    )
                }
            }
            
            // Cache and serve
            cache.set(productId: productId, language: language, purpose: purpose, width: finalWidth, height: finalHeight, data: finalData)
            
            // Convert Data to ByteBuffer
            var buffer = ByteBuffer()
            buffer.writeBytes(finalData)
            
            return Response(
                status: .ok,
                headers: [
                    .contentType: "image/jpeg",
                    .cacheControl: "max-age=86400"
                ],
                body: ResponseBody(byteBuffer: buffer)
            )
        } else {
            throw HTTPError(.notFound, message: "Image not found for product: \(productId), purpose: \(purpose)")
        }
    }
    
}
