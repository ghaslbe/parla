import SwiftUI
import AppKit
import AVFoundation

/// SwiftUI settings form. Reads/writes `AppSettings.shared` directly; simple and
/// good enough while the option set is small.
struct SettingsView: View {
    @State private var trigger = AppSettings.shared.trigger
    @State private var holdToTalk = AppSettings.shared.holdToTalk
    @State private var insertMethod = AppSettings.shared.insertMethod
    @State private var provider = AppSettings.shared.provider
    @State private var endpoint = AppSettings.shared.endpoint
    @State private var apiKey = AppSettings.shared.apiKey
    @State private var model = AppSettings.shared.model
    @State private var language = AppSettings.shared.language

    @State private var micOK = false
    @State private var axOK = false
    @State private var inputOK = false

    @ObservedObject private var models = ModelManager.shared

    var body: some View {
        Form {
            Section("Trigger") {
                Picker("Key", selection: $trigger) {
                    ForEach(TriggerKey.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Hold to talk (off = press to toggle)", isOn: $holdToTalk)
            }

            Section("Transcription") {
                Picker("Backend", selection: $provider) {
                    ForEach(ProviderKind.allCases) { Text($0.label).tag($0) }
                }
                switch provider {
                case .appleSpeech:
                    Text("Uses Apple's built-in on-device speech model. The system downloads the language assets automatically on first use. Requires macOS 26+.")
                        .font(.caption).foregroundStyle(.secondary)
                case .localWhisper:
                    localModelsView
                case .openAICompatible:
                    TextField("Endpoint (…/v1)", text: $endpoint)
                    SecureField("API key (optional)", text: $apiKey)
                    TextField("Model", text: $model)
                }
                TextField("Language (ISO code, empty = auto)", text: $language)
            }

            Section("Output") {
                Picker("Insert", selection: $insertMethod) {
                    ForEach(InsertMethod.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Permissions") {
                permissionRow("Microphone", micOK) { }
                permissionRow("Accessibility (type at cursor)", axOK) {
                    TextInserter.requestAccessibility()
                }
                permissionRow("Input Monitoring (detect key)", inputOK) {
                    HotkeyMonitor.requestInputMonitoring()
                }
                Button("Re-check") { refreshPermissions() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onAppear(perform: refreshPermissions)
        .onChange(of: trigger) { AppSettings.shared.trigger = $0 }
        .onChange(of: holdToTalk) { AppSettings.shared.holdToTalk = $0 }
        .onChange(of: insertMethod) { AppSettings.shared.insertMethod = $0 }
        .onChange(of: provider) { AppSettings.shared.provider = $0 }
        .onChange(of: endpoint) { AppSettings.shared.endpoint = $0 }
        .onChange(of: apiKey) { AppSettings.shared.apiKey = $0 }
        .onChange(of: model) { AppSettings.shared.model = $0 }
        .onChange(of: language) { AppSettings.shared.language = $0 }
    }

    @ViewBuilder private var localModelsView: some View {
        Text("Fully offline. Audio never leaves your Mac.")
            .font(.caption).foregroundStyle(.secondary)

        if let dl = models.downloading {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(L("Downloading")) \(dl)…").font(.caption)
                ProgressView(value: models.progress)
            }
        }
        if let err = models.lastError {
            Text(err).font(.caption).foregroundStyle(.red)
        }

        ForEach(WhisperModel.catalog) { model in
            HStack {
                let installed = models.installed.contains(model.id)
                let active = models.activePath == models.localURL(for: model).path
                Image(systemName: active ? "largecircle.fill.circle" : (installed ? "circle" : "arrow.down.circle"))
                    .foregroundStyle(active ? Color.accentColor : .secondary)
                Text(model.id)
                Text(model.approxSize).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if installed {
                    if !active { Button("Use") { models.activate(model) } }
                    Button(role: .destructive) { models.delete(model) } label: {
                        Image(systemName: "trash")
                    }.buttonStyle(.borderless)
                } else {
                    Button("Download") { models.download(model) }
                        .disabled(models.downloading != nil)
                }
            }
        }
    }

    private func permissionRow(_ title: LocalizedStringKey, _ ok: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok { Button("Grant", action: action) }
        }
    }

    private func refreshPermissions() {
        axOK = TextInserter.hasAccessibility
        inputOK = HotkeyMonitor.hasInputMonitoring
        micOK = AudioPermission.granted
    }
}

enum AudioPermission {
    static var granted: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
    static func request(_ done: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

/// Hosts the SwiftUI settings form in a standard window.
final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView())
        let win = NSWindow(contentViewController: hosting)
        win.title = L("Parla Settings")
        win.styleMask = [.titled, .closable, .miniaturizable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
