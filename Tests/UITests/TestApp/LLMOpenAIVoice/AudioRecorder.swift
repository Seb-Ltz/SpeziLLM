//
//  AudioRecorder.swift
//  UITests
//
//  Created by Sébastien Letzelter on 21.04.25.
//

import AVFoundation
import SwiftUI

@Observable
class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate, @unchecked Sendable {
    @ObservationIgnored static let shared = AudioRecorder()
    @ObservationIgnored private var audioRecorder: AVAudioRecorder?
    
    var isRecording = false
    var base64PCM = Data()

    func start() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        } catch {
            print(error)
            return
        }
        
        let settings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 24000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ] as [String: Any]

        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("voice-recording.wav")
        
        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Failed to start recording:", error)
        }
    }
    
    func stop() {
        audioRecorder?.stop()
        isRecording = false
        
        guard let url = audioRecorder?.url else {
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            base64PCM = data
            print("Base64 PCM:", base64PCM.prefix(100), "...")
            if let audioFileUrl = audioRecorder?.url {
                try FileManager.default.removeItem(at: audioFileUrl)
            }
        } catch {
            print("Failed to read audio data:", error)
        }
    }
}
