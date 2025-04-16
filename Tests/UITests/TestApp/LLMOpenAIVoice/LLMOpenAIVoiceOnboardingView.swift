//
// This source file is part of the Stanford Spezi open source project
//
// SPDX-FileCopyrightText: 2022 Stanford University and the project authors (see CONTRIBUTORS.md)
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SwiftUI
import SpeziLLMOpenAI


struct LLMOpenAIVoiceOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    
    
    var body: some View {
        OnboardingStack {
            LLMOpenAIAPITokenOnboardingStep {
                dismiss()
            }
        }
            #if os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.headline)
                    }
                }
            }
            #endif
    }
}

