//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import os
import SpeziKeychainStorage
import SpeziLLM


extension LLMOpenAIVoiceSession {
    func setup() async -> Bool {
        await MainActor.run {
            self.state = .loading
        }

        let credentials = try? keychainStorage.retrieveCredentials(
            withUsername: LLMOpenAIConstants.credentialsUsername,
            for: .openAIKey
        )
        
        guard let openAPIKey = credentials?.password ?? platform.configuration.apiToken else {
            Self.logger.warning("Missing OpenAI key credentials or apiToken variable")
            return false
        }
        
        let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview")!

        var request = URLRequest(url: url)
        request.addValue("Bearer \(openAPIKey)", forHTTPHeaderField: "Authorization")
        request.addValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        self.webSocketTask = URLSession.shared.webSocketTask(with: request)
        self.webSocketTask?.resume()
        
        let task = Task {
            await self.receiveLoop()
        }

        _ = lock.withLock {
            tasks.insert(task)
        }

        guard await withCheckedContinuation({ continuation in
            self.sessionCreatedContinuation = continuation
        }) else {
            return false
        }
        do {
            try await sendSetupSession()
        } catch {
            Self.logger.error("\(error)")
        }
        
        await MainActor.run {
            self.state = .ready
        }

        return true
    }
    
    func sendSetupSession() async throws {
        let tools = try schema.functions.values.compactMap { function in
            [
                "type": "function",
                "name": Swift.type(of: function).name,
                "description": Swift.type(of: function).description,
                "parameters": try JSONSerialization
                    .jsonObject(with: try JSONEncoder().encode(try function.schema), options: []) as? [String: Any] ?? [:]
            ]
        }
        print(tools.debugDescription)
        
        let sessionUpdateData: [String: Any] = [
            "type": "session.update",
            "session": [
                "tools": tools
            ]
        ]
        print("------")
        print(sessionUpdateData)
        print("------")
        
        let sessionUpdateDataJson = try JSONSerialization.data(withJSONObject: sessionUpdateData, options: .prettyPrinted)
        
        try await webSocketTask?.send(.string(String(decoding: sessionUpdateDataJson, as: UTF8.self)))
        Self.logger.debug("Sent session update:\n\(String(decoding: sessionUpdateDataJson, as: UTF8.self))")
    }
}
