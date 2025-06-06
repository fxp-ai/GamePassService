//
//  WebhookController.swift
//  GamePassService
//
//  Created by Felix Pultar on 06.06.2025.
//

import Foundation
import Hummingbird

struct WebhookController {
    let crawlerService: CrawlerService
    
    var endpoints: RouteCollection<AppRequestContext> {
        return RouteCollection(context: AppRequestContext.self)
            .add(middleware: BasicAuthenticator())
            .post("crawl", use: self.triggerCrawl)
            .get("crawl/status", use: self.getCrawlStatus)
    }
    
    struct CrawlStartedResponse: ResponseEncodable {
        let status: String
        let message: String
    }
    
    struct CrawlRunningResponse: ResponseEncodable {
        let status: String
        let message: String
    }
    
    @Sendable func triggerCrawl(request: Request, context: some RequestContext) async throws -> CrawlStartedResponse {
        let result = try await crawlerService.startCrawl()
        
        switch result {
        case .started:
            return CrawlStartedResponse(
                status: "crawl_started",
                message: "Crawler has been started successfully"
            )
            
        case .alreadyRunning:
            throw HTTPError(.conflict, message: "A crawl is already in progress")
        }
    }
    
    @Sendable func getCrawlStatus(request: Request, context: some RequestContext) async throws -> CrawlerService.CrawlStatus {
        return await crawlerService.getStatus()
    }
}

// Basic authentication middleware
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
