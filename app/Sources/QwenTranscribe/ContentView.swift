import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

// MARK: - Data Models

struct TimestampSegment: Codable, Identifiable {
    var id: String { "\(start)-\(end)-\(text)" }
    let start: Double
    let end: Double
    var text: String
}

// MARK: - Main View

struct ContentView: View {
    @Binding var backendReady: Bool
    @Binding var modelLoaded: Bool
    @Binding var timestampsSupported: Bool
    @Binding var showSettings: Bool
    @State private var transcription = ""
    @State private var detectedLanguage = ""
    @State private var selectedLanguage = ""
    @State private var statusMessage = "Waiting for backend..."
    @State private var isTranscribing = false
    @State private var timestamps: [TimestampSegment] = []
    @State private var showFilePicker = false
    @State private var elapsedSeconds = 0
    @State private var progressTimer: Timer?

    @State private var audioPlayer: AVAudioPlayer?
    @State private var audioFileURL: URL?
    @State private var isPlaying = false
    @State private var playbackTime: Double = 0
    @State private var audioDuration: Double = 0
    @State private var playbackTimer: Timer?
    @State private var editingIndex: Int?
    @State private var editBuffer: String = ""
    @FocusState private var editFieldFocused: Bool

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 1800
        config.timeoutIntervalForResource = 3600
        return URLSession(configuration: config)
    }()

    private let languages = [
        "", "Chinese", "English", "Cantonese", "Arabic", "German",
        "French", "Spanish", "Portuguese", "Indonesian", "Italian",
        "Korean", "Russian", "Thai", "Vietnamese", "Japanese",
        "Turkish", "Hindi", "Malay", "Dutch", "Swedish"
    ]

    var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            modelWarningBanner
            transcriptionView
            Divider()
            controlsView
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                transcribeFile(url: url)
            }
        }
    }

    // MARK: - Header

    var headerView: some View {
        HStack {
            Image(systemName: "waveform.circle.fill")
                .font(.title2)
                .foregroundColor(backendReady ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("QwenTranscribe")
                    .font(.headline)
                Text(headerStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            languagePicker
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    var headerStatusMessage: String {
        if !backendReady { return "Waiting for backend..." }
        if !modelLoaded { return "Model not installed" }
        return statusMessage
    }

    // MARK: - Language Picker

    var languagePicker: some View {
        Picker("", selection: $selectedLanguage) {
            Text("Auto Detect").tag("")
            ForEach(languages.filter { !$0.isEmpty }, id: \.self) { lang in
                Text(lang).tag(lang)
            }
        }
        .frame(width: 130)
        .disabled(isTranscribing)
    }

    // MARK: - Model Warning Banner

    @ViewBuilder
    var modelWarningBanner: some View {
        if backendReady && !modelLoaded {
            Button(action: { showSettings = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Speech recognition model not installed. Click to download.")
                        .font(.caption)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange.opacity(0.1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Divider()
        }
    }

    // MARK: - Transcription Area

    var transcriptionView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !detectedLanguage.isEmpty {
                    Label(detectedLanguage, systemImage: "globe")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !timestamps.isEmpty {
                    Label("\(timestamps.count) segments", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            ScrollViewReader { proxy in
                ScrollView {
                    if timestamps.isEmpty {
                        plainTextSection(proxy: proxy)
                    } else {
                        timelineSection(proxy: proxy)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            }

            if isTranscribing {
                HStack {
                    ProgressView().scaleEffect(0.7)
                    Text("Transcribing... \(elapsedSeconds)s")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(.bottom, 12)
            }
        }
    }

    func plainTextSection(proxy: ScrollViewProxy) -> some View {
        ZStack(alignment: .topLeading) {
            if transcription.isEmpty && !isTranscribing {
                Text("Select an audio file to transcribe...")
                    .foregroundColor(.secondary.opacity(0.5))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            } else {
                Text(transcription.isEmpty ? "Listening..." : transcription)
                    .font(.system(size: 18))
                    .lineSpacing(6)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("text")
                    .textSelection(.enabled)
            }
        }
    }

    func timelineSection(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(timestamps.enumerated()), id: \.offset) { i, seg in
                let isActive = playbackTime >= seg.start && playbackTime < seg.end
                let isEditing = editingIndex == i
                HStack(alignment: .top, spacing: 12) {
                    Text(formatTime(seg.start))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(isActive ? .accentColor : .secondary)
                        .frame(width: 56, alignment: .trailing)
                        .onTapGesture { seekTo(seg.start) }

                    if isEditing {
                        TextField("", text: $editBuffer, axis: .vertical)
                            .font(.system(size: 15))
                            .textFieldStyle(.plain)
                            .focused($editFieldFocused)
                            .onAppear { editFieldFocused = true }
                            .onSubmit { commitEdit() }
                            .onExitCommand { cancelEdit() }
                    } else {
                        Text(seg.text)
                            .font(.system(size: 15))
                            .textSelection(.enabled)
                            .onTapGesture { seekTo(seg.start) }
                    }

                    Spacer()

                    if isEditing {
                        Button("Done") { commitEdit() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundColor(.accentColor)
                    } else {
                        Button { startEdit(at: i) } label: {
                            Image(systemName: "pencil")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                    }

                    Text(formatTime(seg.end))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(isActive ? .accentColor : .secondary.opacity(0.6))
                        .frame(width: 56, alignment: .leading)
                        .onTapGesture { seekTo(seg.start) }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.08) : Color.clear)

                if i < timestamps.count - 1 {
                    Divider().padding(.leading, 88)
                }
            }
        }
        .padding(.bottom, 12)
        .id("timeline")
        .onChange(of: timestamps.count) { _, _ in
            withAnimation { proxy.scrollTo("timeline", anchor: .bottom) }
        }
    }

    func startEdit(at index: Int) {
        guard index < timestamps.count else { return }
        editingIndex = index
        editBuffer = timestamps[index].text
    }

    func commitEdit() {
        guard let idx = editingIndex, idx < timestamps.count else { return }
        timestamps[idx].text = editBuffer
        transcription = timestamps.map(\.text).joined()
        editingIndex = nil
        editBuffer = ""
        editFieldFocused = false
    }

    func cancelEdit() {
        editingIndex = nil
        editBuffer = ""
        editFieldFocused = false
    }

    func formatTime(_ seconds: Double) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 100)
        return String(format: "%d:%02d.%02d", m, s, ms)
    }

    func formatSRTTime(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        let ms = Int((seconds - Double(Int(seconds))) * 1000)
        return String(format: "%02d:%02d:%02d,%03d", h, m, s, ms)
    }

    func exportSRT() {
        var srt = ""
        for (i, seg) in timestamps.enumerated() {
            srt += "\(i + 1)\n\(formatSRTTime(seg.start)) --> \(formatSRTTime(seg.end))\n\(seg.text)\n\n"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcription.srt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? srt.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - Controls

    var controlsView: some View {
        VStack(spacing: 12) {
            if let url = audioFileURL {
                playerControls(url: url)
            } else {
                fileModeButton
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    var fileModeButton: some View {
        Button(action: { showFilePicker = true }) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.plus")
                Text("Select Audio File")
            }
            .font(.body)
            .foregroundColor(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.accentColor))
            .shadow(color: Color.accentColor.opacity(0.3), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!backendReady || !modelLoaded || isTranscribing)
        .opacity((backendReady && modelLoaded && !isTranscribing) ? 1 : 0.5)
    }

    func playerControls(url: URL) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)

                Slider(value: $playbackTime, in: 0...max(audioDuration, 0.01)) {
                    Text("Seek")
                } onEditingChanged: { editing in
                    if !editing {
                        audioPlayer?.currentTime = playbackTime
                    }
                }
                .disabled(audioDuration == 0)

                Text("\(formatTime(playbackTime))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
                Text("/")
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.3))
                Text("\(formatTime(audioDuration))")
                    .font(.caption.monospaced())
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .leading)
            }

            HStack {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if !timestamps.isEmpty {
                    Button("Export SRT") { exportSRT() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text("|")
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.3))
                }
                Button("Open New File") {
                    showFilePicker = true
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.accentColor)
            }
        }
    }

    // MARK: - File Transcription

    func transcribeFile(url: URL) {
        transcription = ""
        detectedLanguage = ""
        timestamps = []
        isTranscribing = true
        statusMessage = "Transcribing file..."
        startProgressTimer()
        stopPlayback()
        setupPlayer(url: url)

        Task {
            defer {
                Task { @MainActor in
                    isTranscribing = false
                    statusMessage = "Ready"
                    stopProgressTimer()
                }
            }

            guard let serverURL = URL(string: "http://127.0.0.1:8765/transcribe") else { return }

            let lang = await MainActor.run { selectedLanguage }

            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

            var body = Data()
            guard let audioData = try? Data(contentsOf: url) else { return }

            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)

            if !lang.isEmpty {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
                body.append(lang.data(using: .utf8)!)
                body.append("\r\n".data(using: .utf8)!)
            }

            let wantTS = await MainActor.run { timestampsSupported }
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"return_timestamps\"\r\n\r\n".data(using: .utf8)!)
            body.append((wantTS ? "true" : "false").data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)

            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            request.httpBody = body

            do {
                let (data, _) = try await session.data(for: request)
                await handleResponse(data: data)
            } catch {
                await MainActor.run { transcription = "Error: \(error.localizedDescription)" }
            }
        }
    }

    func handleResponse(data: Data) async {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            await MainActor.run { transcription = "Invalid response from server." }
            return
        }

        if let error = json["error"] as? String {
            await MainActor.run { transcription = "Error: \(error)" }
            return
        }

        await MainActor.run {
            transcription = json["text"] as? String ?? ""
            detectedLanguage = json["language"] as? String ?? ""

            if let tsArray = json["timestamps"] as? [[String: Any]] {
                timestamps = tsArray.compactMap { item in
                    guard let start = item["start"] as? Double,
                          let end = item["end"] as? Double,
                          let text = item["text"] as? String
                    else { return nil }
                    return TimestampSegment(start: start, end: end, text: text)
                }
            } else {
                timestamps = []
            }
        }
    }

    // MARK: - Progress Timer

    func startProgressTimer() {
        elapsedSeconds = 0
        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                elapsedSeconds += 1
            }
        }
    }

    func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
        elapsedSeconds = 0
    }

    // MARK: - Audio Player

    func setupPlayer(url: URL) {
        stopPlayback()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + url.pathExtension)
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        guard let _ = try? FileManager.default.copyItem(at: url, to: tempURL) else { return }
        audioFileURL = tempURL
        guard let player = try? AVAudioPlayer(contentsOf: tempURL) else { return }
        audioPlayer = player
        player.prepareToPlay()
        audioDuration = player.duration
        playbackTime = 0
        isPlaying = false
    }

    func seekTo(_ time: Double) {
        audioPlayer?.currentTime = time
        playbackTime = time
    }

    func togglePlayback() {
        guard let player = audioPlayer else { return }
        if player.isPlaying {
            player.pause()
            stopPlaybackTimer()
            isPlaying = false
        } else {
            if playbackTime >= audioDuration {
                player.currentTime = 0
                playbackTime = 0
            }
            player.play()
            startPlaybackTimer()
            isPlaying = true
        }
    }

    func stopPlayback() {
        audioPlayer?.stop()
        stopPlaybackTimer()
        isPlaying = false
        playbackTime = 0
    }

    func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                guard let p = audioPlayer, p.isPlaying else { return }
                playbackTime = p.currentTime
            }
        }
    }

    func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }
}
