// File: Sources/App/Controller/ImageController+Manifest.swift
// Replace the entire file with this corrected implementation

import Foundation
import Hummingbird
import PostgresNIO
import Crypto

// MARK: - MD5 Extension
extension Data {
    func md5() -> String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Add this extension to ImageController
extension ImageController {
    
    @Sendable func getManifest(request: Request, context: some RequestContext) async throws -> [String: String?] {
        // Extract and validate required parameters
        guard let language = request.uri.queryParameters.get("language") else {
            throw HTTPError(.badRequest, message: "Missing required parameter: language")
        }
        
        guard let purpose = request.uri.queryParameters.get("purpose") else {
            throw HTTPError(.badRequest, message: "Missing required parameter: purpose")
        }
        
        guard let widthString = request.uri.queryParameters.get("width"),
              let width = Int(widthString) else {
            throw HTTPError(.badRequest, message: "Missing or invalid required parameter: width")
        }
        
        guard let productIdsString = request.uri.queryParameters.get("productIds") else {
            throw HTTPError(.badRequest, message: "Missing required parameter: productIds")
        }
        
        // Parse product IDs
        let productIds = productIdsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !productIds.isEmpty else {
            throw HTTPError(.badRequest, message: "productIds parameter cannot be empty")
        }
        
        // Build response dictionary
        var checksums: [String: String?] = [:]
        
        for productId in productIds {
            // Build the expected cache path
            let cachedPath = cache.cacheDirectory
                .appendingPathComponent(productId)
                .appendingPathComponent(language)
            
            // We need to find a file matching the pattern: {purpose}-{width}x{height}.jpg
            // Since we don't know the height, we need to list directory contents
            let fileManager = FileManager.default
            
            if fileManager.fileExists(atPath: cachedPath.path) {
                do {
                    let files = try fileManager.contentsOfDirectory(atPath: cachedPath.path)
                    
                    // Find file matching our purpose and width
                    var foundChecksum: String? = nil
                    
                    for file in files {
                        // Expected format: "BoxArt-180x270.jpg" or "Screenshot_0-828x466.jpg"
                        guard file.hasSuffix(".jpg") else { continue }
                        
                        let nameWithoutExtension = String(file.dropLast(4))
                        
                        // Check if this file matches our purpose and width
                        if nameWithoutExtension.hasPrefix("\(purpose)-\(width)x") {
                            // This is our file - calculate checksum
                            let filePath = cachedPath.appendingPathComponent(file)
                            
                            if let data = try? Data(contentsOf: filePath) {
                                foundChecksum = data.md5()
                                break
                            }
                        }
                    }
                    
                    checksums[productId] = foundChecksum
                    
                } catch {
                    // Directory exists but can't be read - treat as not cached
                    checksums[productId] = nil
                }
            } else {
                // Product not cached at all
                checksums[productId] = nil
            }
        }
        
        return checksums
    }
}
