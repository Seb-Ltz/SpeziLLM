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

    // swiftlint:disable:next function_body_length
    func receiveLoop() async {
        guard let task = webSocketTask else {
            return
        }
        
        while true {
            do {
                let message = try await task.receive()
                
                if case let .string(text) = message {
                    guard let jsonData = text.data(using: .utf8),
                          let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: []),
                          let jsonDict = jsonObject as? [String: Any],
                          let type = jsonDict["type"] as? String else {
                        Self.logger.warning("Invalid message format: \(text)")
                        continue
                    }
                    
                    Self.logger.info("Received WebSocket text message, of type \(type)")
                    
                    await MainActor.run {
                        self.lastEventType = type
                    }
                    
                    switch type {
                    case "session.created":
                        Self.logger.info("Session created")
                        sessionIsActive.send(true)
                    case "response.audio.delta":
                        // If present, yield the "delta" value to the stream.
                        if let delta = jsonDict["delta"] as? String {
                            audioDeltaContinuation?.yield(delta)
                        } else {
                            Self.logger.warning("Missing 'delta' in audio delta message: \(text)")
                        }
                    case "response.audio.done":
                        // When done, close the stream.
                        audioDeltaContinuation?.finish()
                    case "response.audio_transcript.done":
                        Self.logger.debug("Final transcript: \(jsonDict["transcript"] as? String ?? "Not found")")
                    case "response.done":
                        guard let response = jsonDict["response"] as? [String: Any],
                              let output = response["output"] as? [[String: Any]],
                              !output.isEmpty,
                              let type = output[0]["type"] as? String,
                              let name = output[0]["name"] as? String,
                              let callId = output[0]["call_id"] as? String,
                              let arguments = output[0]["arguments"] as? String,
                              type == "function_call"
                        else {
                            continue
                        }
                        
                        Self.logger.log("arguments function call: \(arguments)")
                        Task {
                            try schema.functions[name]?.injectParameters(from: arguments.data(using: .utf8) ?? Data())
                            let functionOutput = try await schema.functions[name]?.execute()
                            let eventData: [String: Any] = [
                                "type": "conversation.item.create",
                                "item": [
                                    "type": "function_call_output",
                                    "call_id": callId,
                                    "output": functionOutput
                                ]
                            ]
                            
                            let eventDataJson = try JSONSerialization.data(withJSONObject: eventData, options: .prettyPrinted)
                            
                            let responseData: [String: Any] = [
                                "type": "response.create"
                            ]
                            let responseDataJson = try JSONSerialization.data(withJSONObject: responseData, options: .prettyPrinted)
                            
                            
                            try await webSocketTask?.send(.string(String(decoding: eventDataJson, as: UTF8.self)))
                            Self.logger.debug("Function call event:\n\(String(decoding: eventDataJson, as: UTF8.self))")
                            
                            try await webSocketTask?.send(.string(String(decoding: responseDataJson, as: UTF8.self)))
                        }
                        
                    case "error":
                        Self.logger.error("Encountered error: \(jsonDict)")
                    default:
                        Self.logger.info("Received WebSocket message, of another type than text")
                    }
                }
            } catch {
                Self.logger.error("WebSocket receive error: \(error.localizedDescription)")
                audioDeltaContinuation?.finish(throwing: error)
                break
            }
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
            
            Self.logger.debug("Sent audio buffer:\n\(String(decoding: eventDataJson, as: UTF8.self))")
        } catch {
            Self.logger.error("\(error)")
        }
        
        // Remove element from context
//        DispatchQueue.main.async {
//            self.context.remove(at: contextIndex) // Error: out of range...
//        }
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
        
        try await createResponse()
    }
    
    private func createResponse() async throws {
        let responseData = RealtimeClientEventResponseCreate(
            _type: .response_period_create,
            response: .init(modalities: [.text, .audio], instructions: "Please assist the user.")
        )
        
        let responseDataJson = try JSONEncoder().encode(responseData)
        try await webSocketTask?.send(.string(String(decoding: responseDataJson, as: UTF8.self)))
    }
}
