import SwiftUI

@main
struct QwenTranscribeApp: App {
    @State private var backendReady = false
    @State private var modelLoaded = false
    @State private var timestampsSupported = false
    @State private var backendProcess: Process?
    @State private var showSettings = false

    private let backendURL = "http://127.0.0.1:8765"

    var body: some Scene {
        WindowGroup {
            ContentView(
                backendReady: $backendReady,
                modelLoaded: $modelLoaded,
                timestampsSupported: $timestampsSupported,
                showSettings: $showSettings
            )
            .frame(minWidth: 540, minHeight: 480)
            .onAppear { startBackend() }
            .onDisappear { stopBackend() }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    modelLoaded: $modelLoaded,
                    timestampsSupported: $timestampsSupported,
                    showSettings: $showSettings
                )
            }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Model Settings...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    func startBackend() {
        Task {
            for _ in 0..<30 {
                if let url = URL(string: "\(backendURL)/health"),
                   let (data, _) = try? await URLSession.shared.data(from: url),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   json["status"] as? String == "ok" {
                    await MainActor.run {
                        backendReady = true
                        modelLoaded = json["model_loaded"] as? Bool ?? false
                        timestampsSupported = json["timestamps_supported"] as? Bool ?? false
                        if !modelLoaded {
                            showSettings = true
                        }
                    }
                    return
                }

                if backendProcess == nil {
                    await MainActor.run { launchBackendProcess() }
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func launchBackendProcess() {
        let repoRoot = Bundle.main.bundlePath.contains("DerivedData") || Bundle.main.bundlePath.contains("debug")
            ? NSHomeDirectory() + "/codes/qwen-transcribe"
            : Bundle.main.bundlePath + "/../../../.."

        let venvPython = "\(repoRoot)/.venv/bin/python3"
        let serverScript = "\(repoRoot)/backend/server.py"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: venvPython)
        process.arguments = [serverScript]
        process.environment = [
            "QWEN3_ASR_MODEL_PATH": "\(repoRoot)/models/models--Qwen--Qwen3-ASR-1.7B/snapshots/7278e1e70fe206f11671096ffdd38061171dd6e5",
            "PATH": "/opt/homebrew/bin:/usr/bin:/bin",
        ]

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try? process.run()
        backendProcess = process
    }

    func stopBackend() {
        backendProcess?.terminate()
        backendProcess = nil
    }
}
