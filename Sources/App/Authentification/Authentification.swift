//
//  File.swift
//  GamePassService
//
//  Created by Felix Pultar on 18.06.2025.
//

import Foundation
import Hummingbird

struct BasicAuthenticator: RouterMiddleware {
    let validToken = ProcessInfo.processInfo.environment["WEBHOOK_AUTH_TOKEN"] ?? "your-secret-token"
    
    struct UnauthorizedError: ResponseEncodable {
        let error: String
    }
    
    func handle(_ request: Request, context: AppRequestContext, next: (Request, AppRequestContext) async throws -> Response) async throws -> Response {
        guard let authHeader = request.headers[.authorization],
              authHeader == "Bearer \(validToken)" else {
            throw HTTPError(.unauthorized, message: "Unauthorized")
        }
        
        return try await next(request, context)
    }
}
