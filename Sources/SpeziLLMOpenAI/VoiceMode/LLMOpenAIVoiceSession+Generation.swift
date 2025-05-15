//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import Foundation
import GeneratedOpenAIClient
import OpenAPIURLSession
import os
import SpeziLLM

extension LLMOpenAIVoiceSession {
    typealias RealtimeClientEventResponseCreate = Components.Schemas.RealtimeClientEventResponseCreate

    // swiftlint:disable:next identifier_name
    func _generate(continuation: AsyncThrowingStream<String, any Error>.Continuation) async {
        guard await context.allSatisfy({ !$0.isAudio }) || platform.configuration.turnDetectionSettings == nil else {
            print("generate() only supported when turn detection turned off")
            return
        }

        do {
            try await commitContext()
        } catch {
            await finishGenerationWithError(LLMOpenAIVoiceError.unknown(error), on: continuation)
        }
    }
    
    func commitToAudioBuffer(base64data: String, contextIndex: Int) async {
        guard platform.configuration.turnDetectionSettings != nil else {
            print("Commit to audio buffer only supported when turn detection")
            return
        }

        await awaitUntilSessionCreated()

        do {
            let eventData = Components.Schemas.RealtimeClientEventInputAudioBufferAppend(
                _type: .input_audio_buffer_period_append,
                audio: base64data
            )
            
            let encoder = JSONEncoder()
            let eventDataJson = try encoder.encode(eventData)
            try await webSocketTask?.send(.string(String(decoding: eventDataJson, as: UTF8.self)))
            
            Self.logger.debug("Sent audio buffer!")
        } catch {
            Self.logger.error("\(error)")
        }
    }
    
    private func commitContext() async throws {
        let eventData: [String: Any] = await [
            "type": "conversation.item.create",
            "item": [
                "type": "message",
                "role": "user",
                "content":
                    context
                    .filter { $0.role == .user && !$0.isAudio }
                    .compactMap { [ "type": "input_text", "text": $0.content ] }
                + context
                    .filter { platform.configuration.turnDetectionSettings == nil && $0.role == .user && $0.isAudio }
                    .compactMap { [ "type": "input_audio", "audio": $0.content ] }
            ]
        ]
        
        let eventDataJson = try JSONSerialization.data(withJSONObject: eventData, options: .prettyPrinted)
        
        
        try await webSocketTask?.send(.string(String(decoding: eventDataJson, as: UTF8.self)))
        Self.logger.debug("Sent event:\n\(String(decoding: eventDataJson, as: UTF8.self))")
        
        try await createResponse(
            response: .init(modalities: [.text, .audio], instructions: "Please assist the user.")
        )
    }
    
    func createResponse(response: Components.Schemas.RealtimeResponseCreateParams? = nil) async throws {
        let responseData = RealtimeClientEventResponseCreate(
            _type: .response_period_create,
            response: response
        )
        
        let responseDataJson = try JSONEncoder().encode(responseData)
        try await webSocketTask?.send(.string(String(decoding: responseDataJson, as: UTF8.self)))
    }
}
