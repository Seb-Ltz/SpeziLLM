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

import GeneratedOpenAIClient
import OpenAPIURLSession

extension LLMOpenAIVoiceSession {
    typealias ToolsPayload = Components.Schemas.RealtimeSessionCreateRequest.toolsPayloadPayload
    typealias TurnDetectionPayload = Components.Schemas.RealtimeSessionCreateRequest.turn_detectionPayload
    typealias RealtimeClientEventSessionUpdate = Components.Schemas.RealtimeClientEventSessionUpdate
    
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
        
        guard let url = URL(string: "wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview") else {
            return false
        }

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

        await awaitUntilSessionCreated()

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
    
    private func sendSetupSession() async throws {
        let tools: [ToolsPayload] = try schema.functions.values.compactMap { function in
            let functionType = Swift.type(of: function)
            let encodedSchema = try JSONEncoder().encode(try function.schema)
            let jsonObject = try JSONSerialization.jsonObject(with: encodedSchema) as? [String: any Sendable] ?? [:]

            return ToolsPayload(
                _type: .function,
                name: functionType.name,
                description: functionType.description,
                parameters: try .init(unvalidatedValue: jsonObject)
            )
        }
        
        let turnDetection: TurnDetectionPayload? = platform.configuration.turnDetectionSettings.map {
            TurnDetectionPayload(
                _type: $0.type,
                threshold: $0.threshold,
                prefix_padding_ms: $0.prefixPaddingMs,
                silence_duration_ms: $0.silenceDurationMs
            )
        }
    
        let eventSessionUpdate = RealtimeClientEventSessionUpdate(
            _type: .session_period_update,
            session: .init(
                turn_detection: turnDetection,
                tools: tools
            )
        )
        
        let eventSessionUpdateJson = try JSONEncoder().encode(eventSessionUpdate)
        try await webSocketTask?.send(.string(String(decoding: eventSessionUpdateJson, as: UTF8.self)))
        Self.logger.debug("Sent session update:\n\(String(decoding: eventSessionUpdateJson, as: UTF8.self))")
    }
}
