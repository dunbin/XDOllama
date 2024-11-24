//
//  xllamaApp.swift
//  xllama
//
//  Created by dunbin on 2024/11/21.
//

import SwiftUI

@main
struct XLlamaApp: App {
    @StateObject private var networkService = NetworkService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
