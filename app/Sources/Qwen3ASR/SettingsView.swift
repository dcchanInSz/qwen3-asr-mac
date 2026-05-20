import SwiftUI

struct SettingsView: View {
    @Binding var modelLoaded: Bool
    @Binding var timestampsSupported: Bool
    @Binding var showSettings: Bool
    @State private var modelExistsOnDisk = false
    @State private var alignerAvailable = false
    @State private var downloadStatus = "idle"
    @State private var downloadMessage = ""
    @State private var downloadProgress: Double = 0
    @State private var statusCheckTimer: Timer?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Settings")
                    .font(.title2)
                    .bold()
            }

            Divider()

            modelSection

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    showSettings = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(24)
        .frame(width: 420, height: 320)
        .onAppear {
            checkModelStatus()
            statusCheckTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                Task { @MainActor in checkModelStatus() }
            }
        }
        .onDisappear {
            statusCheckTimer?.invalidate()
            statusCheckTimer = nil
        }
    }

    var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: modelLoaded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(modelLoaded ? .green : .orange)
                Text("Speech Recognition Model")
                    .font(.headline)
            }

            if modelLoaded {
                HStack {
                    Image(systemName: "checkmark")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Qwen3-ASR 1.7B — Loaded")
                        .font(.caption)
                }
                HStack {
                    Image(systemName: timestampsSupported ? "checkmark" : "xmark")
                        .foregroundColor(timestampsSupported ? .green : .secondary)
                        .font(.caption)
                    Text(timestampsSupported ? "Forced Aligner 0.6B — Loaded" : "Forced Aligner — Not available")
                        .font(.caption)
                }
            } else if modelExistsOnDisk {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Model found on disk, waiting for backend...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No speech recognition model found.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Download Qwen3-ASR 1.7B + Forced Aligner (~3GB)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if downloadStatus == "downloading" {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(downloadMessage.isEmpty ? "Downloading..." : downloadMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            ProgressView(value: downloadProgress, total: 100)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: .infinity)
                            Text(String(format: "%.0f%% complete", downloadProgress))
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                            Text("This may take several minutes depending on your connection.")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                    } else if downloadStatus == "error" {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Download failed", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            if !downloadMessage.isEmpty {
                                Text(downloadMessage)
                                    .font(.caption2)
                                    .foregroundColor(.red.opacity(0.8))
                                    .lineLimit(3)
                            }
                            Button("Retry") {
                                startDownload()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else if downloadStatus == "done" {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.7)
                            Text("Download complete, loading model...")
                                .font(.caption)
                        }
                    } else {
                        Button(action: startDownload) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.down.circle.fill")
                                Text("Download Model")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }

            Divider().padding(.vertical, 4)

            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("The model will be downloaded to the app's models directory.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    func checkModelStatus() {
        guard let url = URL(string: "http://127.0.0.1:8765/model-status") else { return }

        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }

            await MainActor.run {
                modelLoaded = json["model_loaded"] as? Bool ?? false
                modelExistsOnDisk = json["model_exists_on_disk"] as? Bool ?? false
                alignerAvailable = json["aligner_available"] as? Bool ?? false
                timestampsSupported = json["aligner_available"] as? Bool ?? false

                if let dl = json["download"] as? [String: Any] {
                    let prevStatus = downloadStatus
                    downloadStatus = dl["status"] as? String ?? "idle"
                    downloadMessage = dl["message"] as? String ?? ""
                    downloadProgress = dl["progress"] as? Double ?? 0

                    if prevStatus == "downloading" && downloadStatus == "done" {
                        fetchLatestHealth()
                    }
                }
            }
        }
    }

    func fetchLatestHealth() {
        guard let url = URL(string: "http://127.0.0.1:8765/health") else { return }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                await MainActor.run {
                    modelLoaded = json["model_loaded"] as? Bool ?? false
                    timestampsSupported = json["timestamps_supported"] as? Bool ?? false
                }
            }
        }
    }

    func startDownload() {
        guard let url = URL(string: "http://127.0.0.1:8765/download-model") else { return }
        downloadStatus = "downloading"
        downloadMessage = "Starting download..."
        downloadProgress = 0
        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            _ = try? await URLSession.shared.data(for: request)
        }
    }
}
