import SwiftUI
import AppKit

struct AboutView: View {
    @State private var showLicenses = false
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? String(localized: "Development") }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md"),
              let data = try? Data(contentsOf: url), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else { return String(localized: "License notices could not be loaded.") }
        return text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MacPulse").font(.title.weight(.semibold))
                    Text("Version \(version) · macOS 14+").foregroundStyle(Palette.secondary)
                    Text("Runs locally on this Mac").font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            Text("Watch your Mac's resources, device status and AI account usage in one window.")
            Label("Measurements and history stay on this Mac.", systemImage: "lock.shield").foregroundStyle(Palette.accent)
            Text("System monitoring needs no account. AI limits are read from providers using your existing sessions. Closing the window doesn't stop monitoring; it continues from the menu bar. Press Cmd+Q to quit completely.")
                .font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Shortcuts").font(.headline)
            Text("Cmd+1…7: main tabs · Cmd+8: history · Cmd+9: alerts\nCmd+Shift+B: Bluetooth · Cmd+Shift+S: audio\nCmd+Shift+M: quick panel · Cmd+Shift+P: pause/resume\nCmd+O: main window · Cmd+,: settings · Cmd+Shift+H: about")
                .font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Third-party licenses", isExpanded: $showLicenses) {
                ScrollView { Text(notices).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8) }
                    .frame(height: 190)
            }
        }.padding(28).frame(width: 530).background(Palette.background).foregroundStyle(.primary)
    }
}
