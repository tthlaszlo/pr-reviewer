import SwiftUI
import CoreText

// Shared Focus tokens. All custom text uses the bundled Inter family.
enum Focus {
    static let background = Color(hex: 0xF9F9FC)
    static let surface = Color.white
    static let sidebar = Color(hex: 0xF0F0F6)
    static let text = Color(hex: 0x24232E)
    static let muted = Color(hex: 0x696775)
    static let border = Color(hex: 0xE5E4ED)
    static let accent = Color(hex: 0x7760DC)
    static let soft = Color(hex: 0xEFEBFC)
    static let accentText = Color(hex: 0x6048BD)
    static let success = Color(hex: 0x287756)
    static let warning = Color(hex: 0x986316)
    static let warningSurface = Color(hex: 0xFCF1DE)
    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Inter", size: size).weight(weight)
    }
    static func registerFonts() {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        for name in ["Inter"] {
            if let url = bundle.url(forResource: name, withExtension: "ttf", subdirectory: "Resources") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}
private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}
struct FocusButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Focus.font(13, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(primary ? .white : Focus.text)
            .background(primary ? Focus.accent : Focus.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(primary ? Focus.accent : Focus.border))
            .opacity(!enabled ? 0.45 : configuration.isPressed ? 0.75 : 1)
    }
}
