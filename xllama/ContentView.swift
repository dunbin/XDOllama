//
//  ContentView.swift
//  xllama
//
//  Created by dunbin on 2024/11/21.
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @StateObject private var chatHistoryManager = ChatHistoryManager.shared
    @StateObject private var chatService = ChatService.shared
    
    var body: some View {
        NavigationSplitView {
            ChatHistoryView()
        } detail: {
            HStack(spacing: 0) {
                ChatView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 12) {
                    Button(action: { chatHistoryManager.createNewConversation() }) {
                        Image(systemName: "plus")
                    }
                    .disabled(shouldDisableNewChat)
                    
                    Button(action: { showSettings.toggle() }) {
                        Image(systemName: "gear")
                    }
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
    
    private var shouldDisableNewChat: Bool {
        guard let currentId = chatHistoryManager.currentConversationId,
              let currentConversation = chatHistoryManager.conversations.first(where: { $0.id == currentId })
        else { return false }
        
        return currentConversation.messages.isEmpty && chatService.isLoading
    }
}

#Preview {
    ContentView()
}
