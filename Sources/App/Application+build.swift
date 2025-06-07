import Hummingbird
import Logging
import PostgresNIO

/// Application arguments protocol. We use a protocol so we can call
/// `buildApplication` inside Tests as well as in the App executable.
/// Any variables added here also have to be added to `App` in App.swift and
/// `TestArguments` in AppTest.swift
public protocol AppArguments {
    var hostname: String { get }
    var port: Int { get }
    var logLevel: Logger.Level? { get }
}

// Request context used by application
typealias AppRequestContext = BasicRequestContext

///  Build application
/// - Parameter arguments: application arguments
public func buildApplication(_ arguments: some AppArguments) async throws -> some ApplicationProtocol {
    let environment = Environment()
    let logger = {
        var logger = Logger(label: "GamePassService")
        logger.logLevel =
            arguments.logLevel ??
            environment.get("LOG_LEVEL").flatMap { Logger.Level(rawValue: $0) } ??
            .info
        return logger
    }()
    
    // Database configuration from environment or defaults
    let dbHost = environment.get("DB_HOST") ?? "localhost"
    let dbUsername = environment.get("DB_USERNAME") ?? "fpultar"
    let dbPassword = environment.get("DB_PASSWORD") ?? "postgres"
    let dbName = environment.get("DB_NAME") ?? "example"
    
    let postgresConfiguration = PostgresClient.Configuration(
        host: dbHost,
        username: dbUsername,
        password: dbPassword,
        database: dbName,
        tls: .disable
    )
    
    let postgresClient = PostgresClient(configuration: postgresConfiguration, backgroundLogger: logger)
    let postgresGameRepository = GamePostgresRepository(client: postgresClient, logger: logger)
    
    // Initialize crawler service
    let crawlerService = CrawlerService(logger: logger, postgresClient: postgresClient)
    
    let router = buildRouter(
        gameRepository: postgresGameRepository,
        crawlerService: crawlerService
    )
    
    var app = Application(
        router: router,
        configuration: .init(
            address: .hostname(arguments.hostname, port: arguments.port),
            serverName: "GamePassService"
        ),
        logger: logger
    )
    app.addServices(postgresClient)
    return app
}

/// Build router
func buildRouter(
    gameRepository: some GameRepository,
    crawlerService: CrawlerService
) -> Router<AppRequestContext> {
    let router = Router(context: AppRequestContext.self)
    // Add middleware
    router.addMiddleware {
        // logging middleware
        LogRequestsMiddleware(.info)
    }
    
    let v1 = router.group("v1")
    v1.get("/") { _, _ in
        "GamePassService v1 API"
    }
    
    // Game endpoints
    v1.addRoutes(GameController(repository: gameRepository).endpoints, atPath: "/games")
    
    // Webhook endpoints
    v1.addRoutes(WebhookController(crawlerService: crawlerService).endpoints, atPath: "/webhooks")
    
    // Images
    v1.addRoutes(ImageController(repository: gameRepository).endpoints, atPath: "/images")
    
    return router
}
