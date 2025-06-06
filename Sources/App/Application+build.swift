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
    
    let postgresConfiguration = PostgresNIO.PostgresClient.Configuration(host: "localhost", username: "fpultar", password: "postgres", database: "example", tls: .disable)
    let postgresClient = PostgresClient(configuration: postgresConfiguration, backgroundLogger: logger)
    let postgresGameRepository = GamePostgresRepository(client: postgresClient, logger: logger)
    
    let router = buildRouter(gameRepository: postgresGameRepository)
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
func buildRouter(gameRepository: some GameRepository) -> Router<AppRequestContext> {
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
    
    v1.addRoutes(GameController(repository: gameRepository).endpoints, atPath: "/games")
    
    return router
}
