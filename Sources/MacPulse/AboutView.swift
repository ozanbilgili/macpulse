import SwiftUI
import AppKit

struct AboutView: View {
    @State private var showLicenses = false
    private var version: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Geliştirme" }
    private var notices: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "md"),
              let data = try? Data(contentsOf: url), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else { return "Lisans bildirimi alınamadı." }
        return text
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage).resizable().frame(width: 68, height: 68).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MacPulse").font(.title.weight(.semibold))
                    Text("Sürüm \(version) · macOS 14+").foregroundStyle(Palette.secondary)
                    Text("Bu Mac'te yerel kullanım").font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            Text("Mac'inin kaynaklarını, cihaz durumunu ve AI hesaplarının kullanımını tek pencerede izle.")
            Label("Ölçümler ve geçmiş bu Mac'te kalır.", systemImage: "lock.shield").foregroundStyle(Palette.accent)
            Text("Sistem izleme için hesap gerekmez. AI limitleri mevcut oturumlarla sağlayıcılardan okunur. Pencereyi kapatmak izlemeyi durdurmaz; menü çubuğundan sürer. Tam çıkış için Cmd+Q kullan.")
                .font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Kısayollar").font(.headline)
            Text("Cmd+1…7: ana sekmeler · Cmd+8: geçmiş · Cmd+9: uyarılar\nCmd+Shift+B: Bluetooth · Cmd+Shift+S: ses\nCmd+Shift+M: hızlı panel · Cmd+Shift+P: duraklat/sürdür\nCmd+O: ana pencere · Cmd+,: tercihler · Cmd+Shift+H: hakkında")
                .font(.callout).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Üçüncü taraf lisansları", isExpanded: $showLicenses) {
                ScrollView { Text(notices).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8) }
                    .frame(height: 190)
            }
        }.padding(28).frame(width: 530).background(Palette.background).foregroundStyle(.primary)
    }
}
