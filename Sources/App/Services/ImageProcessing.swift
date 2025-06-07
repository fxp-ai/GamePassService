//
//  ImageProcessing.swift
//  GamePassService
//
//  Created by Felix Pultar on 07.06.2025.
//

import Foundation
import SwiftGD
import Hummingbird

func resizeImage(data: Data, toWidth width: Int) async throws -> Data {
    let image = try Image(data: data)
    if width < image.size.width {
        let aspectRatio = Double(image.size.height) / Double(image.size.width)
        let newHeight = Int(Double(width) * aspectRatio)
        
        let resized = image.resizedTo(width: width, height: newHeight)
        
        guard let outputData = try resized?.export(as: .jpg(quality: 85)) else {
            throw HTTPError(.internalServerError, message: "Failed to export image")
        }
        
        return outputData
    } else {
        return data
    }
}
