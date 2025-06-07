//
//  ImageController.swift
//  GamePassService
//
//  Created by Felix Pultar on 07.06.2025.
//

import Foundation
import Hummingbird
import PostgresNIO

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
        
        // Build cache key
        let cacheKey = "\(productId)_\(purpose)_\(width ?? 0)"
        
        // Check cache
        if let cachedData = cache.get(key: cacheKey) {
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
        
        // Get original URL from database
        let imageUrl = try await repository.getImageUrl(productId: productId, purpose: purpose, language: language)
        
        if let imageUrl {
            // Fetch from Microsoft
            let (imageData, _) = try await URLSession.shared.data(from: URL(string: "https:" + imageUrl)!)
            
            // Process if width specified
            let finalData = if let width = width {
                try await resizeImage(data: imageData, toWidth: width)
            } else {
                imageData
            }
            
            // Cache and serve
            cache.set(key: cacheKey, data: finalData)
            
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
