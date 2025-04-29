//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2025 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

/// Represents the configuration of the Spezi ``LLMOpenAIVoicePlatform``.
public struct LLMOpenAIVoicePlatformConfiguration: Sendable {
    /// The OpenAI API token on a global basis.
    let apiToken: String?
    /// Contains the LLMRealtimeTurnDetectionSettings. If set to nil, turn detection is disabled and requires explicit generation calls.
    let turnDetectionSettings: LLMRealtimeTurnDetectionSettings?

    public init(apiToken: String? = nil, turnDetectionSettings: LLMRealtimeTurnDetectionSettings? = nil) {
        self.apiToken = apiToken
        self.turnDetectionSettings = turnDetectionSettings
    }
}

public struct LLMRealtimeTurnDetectionSettings: Encodable, Sendable {
    /// Type of turn detection, only `"server_vad"` is currently supported.
    let type: String = "server_vad"
    /// Activation threshold for VAD (0.0 to 1.0), this defaults to 0.5.
    ///
    /// A higher threshold will require louder audio to activate the model, and thus might perform better in noisy environments.
    let threshold: Float
    /// Amount of audio to include before the VAD detected speech (in milliseconds). Defaults to 300ms.
    let prefixPaddingMs: Int
    /// Duration of silence to detect speech stop (in milliseconds). Defaults to 500ms.
    ///
    /// With shorter values the model will respond more quickly, but may jump in on short pauses from the user.
    let silenceDurationMs: Int
    
    public init(threshold: Float = 0.5, prefixPaddingMs: Int = 300, silenceDurationMs: Int = 500) {
        self.threshold = threshold
        self.prefixPaddingMs = prefixPaddingMs
        self.silenceDurationMs = silenceDurationMs
    }
}
