import Cocoa
import WebKit

@main
final class FlightTrackerApp: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let appName = "Flight Tracker"
    private let placeholderUrl = "http://YOUR-WINDOWS-HOST:5099/?key=REPLACE_ME"

    private var window: NSWindow!
    private var webView: WKWebView!
    private var urlField: NSTextField!
    private var statusLabel: NSTextField!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        let configFileUrl = ensureConfigFile()
        let savedUrl = readSavedUrl(from: configFileUrl)
        urlField.stringValue = savedUrl

        if isConfigured(savedUrl) {
            loadDashboard(from: savedUrl)
        } else {
            statusLabel.stringValue = "Paste the shared or local dashboard URL above, then click Save and Load."
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 1320, height: 900)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = appName
        window.minSize = NSSize(width: 980, height: 700)

        let rootView = NSView(frame: contentRect)
        rootView.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = rootView

        let titleLabel = NSTextField(labelWithString: "Flight Tracker")
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)

        let subtitleLabel = NSTextField(labelWithString: "Dedicated Mac app with the dashboard inside the app window.")
        subtitleLabel.font = NSFont.systemFont(ofSize: 13, weight: .regular)
        subtitleLabel.textColor = NSColor.secondaryLabelColor

        urlField = NSTextField(string: "")
        urlField.placeholderString = "http://localhost:5099/?key=..."
        urlField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

        let saveButton = NSButton(title: "Save and Load", target: self, action: #selector(saveAndLoad))
        let reloadButton = NSButton(title: "Reload", target: self, action: #selector(reloadDashboard))

        statusLabel = NSTextField(labelWithString: "Loading app configuration...")
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 2

        let topStack = NSStackView(views: [titleLabel, subtitleLabel])
        topStack.orientation = .vertical
        topStack.spacing = 6
        topStack.translatesAutoresizingMaskIntoConstraints = false

        let controlsStack = NSStackView(views: [urlField, saveButton, reloadButton])
        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 10
        controlsStack.translatesAutoresizingMaskIntoConstraints = false

        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        rootView.addSubview(topStack)
        rootView.addSubview(controlsStack)
        rootView.addSubview(statusLabel)
        rootView.addSubview(webView)

        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: rootView.topAnchor, constant: 18),
            topStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            topStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),

            controlsStack.topAnchor.constraint(equalTo: topStack.bottomAnchor, constant: 14),
            controlsStack.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            controlsStack.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            urlField.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),

            statusLabel.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),

            webView.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 12),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor, constant: 18),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor, constant: -18),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor, constant: -18)
        ])

        window.makeKeyAndOrderFront(nil)
    }

    @objc
    private func saveAndLoad() {
        let value = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            statusLabel.stringValue = "Enter a dashboard URL first."
            return
        }

        do {
            try value.write(to: configFileUrl(), atomically: true, encoding: .utf8)
            loadDashboard(from: value)
        } catch {
            statusLabel.stringValue = "Could not save the dashboard URL: \(error.localizedDescription)"
        }
    }

    @objc
    private func reloadDashboard() {
        guard isConfigured(urlField.stringValue) else {
            statusLabel.stringValue = "Enter a dashboard URL before reloading."
            return
        }

        if let currentUrl = webView.url {
            webView.load(URLRequest(url: currentUrl))
        } else {
            loadDashboard(from: urlField.stringValue)
        }
    }

    private func loadDashboard(from value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme.lowercased()) else {
            statusLabel.stringValue = "The dashboard URL must start with http:// or https://."
            return
        }

        urlField.stringValue = trimmed
        statusLabel.stringValue = "Loading dashboard inside the Mac app..."
        webView.load(URLRequest(url: url))
    }

    private func ensureConfigFile() -> URL {
        let fileUrl = configFileUrl()
        let supportRoot = fileUrl.deletingLastPathComponent()

        do {
            try FileManager.default.createDirectory(at: supportRoot, withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: fileUrl.path) {
                if let bundledDefault = Bundle.main.url(forResource: "default-flight-tracker-url", withExtension: "txt") {
                    try FileManager.default.copyItem(at: bundledDefault, to: fileUrl)
                } else {
                    try (placeholderUrl + "\n").write(to: fileUrl, atomically: true, encoding: .utf8)
                }
            }
        } catch {
            statusLabel.stringValue = "Could not prepare the dashboard URL file: \(error.localizedDescription)"
        }

        return fileUrl
    }

    private func readSavedUrl(from fileUrl: URL) -> String {
        guard let text = try? String(contentsOf: fileUrl, encoding: .utf8) else {
            return placeholderUrl
        }

        return text.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? placeholderUrl
    }

    private func configFileUrl() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent("flight-tracker-url.txt", isDirectory: false)
    }

    private func isConfigured(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains("REPLACE_ME")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        statusLabel.stringValue = "Dashboard loaded inside the Mac app."
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        statusLabel.stringValue = "Navigation failed: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        statusLabel.stringValue = "Could not reach the dashboard URL: \(error.localizedDescription)"
    }
}
