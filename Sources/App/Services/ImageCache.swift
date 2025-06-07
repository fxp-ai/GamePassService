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
    
    func path(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key + ".jpg")
    }
    
    func get(key: String) -> Data? {
        let url = path(for: key)
        return try? Data(contentsOf: url)
    }
    
    func set(key: String, data: Data) {
        let url = path(for: key)
        try? data.write(to: url)
    }
}
