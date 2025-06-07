//
//  ImageCache.swift
//  GamePassService
//
//  Created by Felix Pultar on 07.06.2025.
//

import Foundation

struct ImageCache {
    let cacheDirectory: URL
    
    init() {
        let paths = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        self.cacheDirectory = paths[0].appendingPathComponent("gamepass-images")
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
    
    func path(for productId: String, language: String, purpose: String, width: Int?, height: Int?) -> URL {
        // Create nested directory structure
        let productDir = cacheDirectory.appendingPathComponent(productId)
        let languageDir = productDir.appendingPathComponent(language)
        
        // Create filename
        let filename: String
        if let width = width, let height = height {
            filename = "\(purpose)-\(width)x\(height).jpg"
        } else {
            filename = "\(purpose)-original.jpg"
        }
        
        return languageDir.appendingPathComponent(filename)
    }
    
    func get(productId: String, language: String, purpose: String, width: Int?, height: Int?) -> Data? {
        let url = path(for: productId, language: language, purpose: purpose, width: width, height: height)
        return try? Data(contentsOf: url)
    }
    
    func set(productId: String, language: String, purpose: String, width: Int?, height: Int?, data: Data) {
        let url = path(for: productId, language: language, purpose: purpose, width: width, height: height)
        
        // Create directory structure if needed
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        try? data.write(to: url)
    }
}
