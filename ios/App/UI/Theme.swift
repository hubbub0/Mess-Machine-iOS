import SwiftUI

/// The Specimen skin from core/shared/tokens.json (Tyler plays in Specimen). The full skin set arrives with the
/// shared Compose screens; this is only for the day-one shell.
enum Ink {
    static func hex(_ v: UInt32) -> Color {
        Color(.sRGB, red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255,
              opacity: Double((v >> 24) & 0xFF) / 255)
    }
    static let ink = hex(0xFF151D1A)
    static let paper = hex(0xFF0E0F0C)
    static let card = hex(0xFF1A2320)
    static let card2 = hex(0xFF24302B)
    static let empty = hex(0xFF3A4440)
    static let cream = hex(0xFFE6DFCB)
    static let dim = hex(0xFFA39D8C)
    static let pink = hex(0xFFE0409A)
    static let teal = hex(0xFF2FB8A6)
    static let yellow = hex(0xFFD9B54A)
    static let riot = hex(0xFFC4552B)
}

enum F {
    static func heading(_ s: CGFloat = 20) -> Font { .custom("Bungee-Regular", size: s) }
    static func text(_ s: CGFloat = 14) -> Font { .custom("Archivo-ExtraBold", size: s) }
    static func textMedium(_ s: CGFloat = 14) -> Font { .custom("Archivo-Medium", size: s) }
    static func textBlack(_ s: CGFloat = 14) -> Font { .custom("Archivo-Black", size: s) }
    static func mono(_ s: CGFloat = 12, bold: Bool = false) -> Font { .custom(bold ? "IBMPlexMono-Bold" : "IBMPlexMono-Regular", size: s) }
    static func lcd(_ s: CGFloat = 14) -> Font { .custom("ShareTechMono-Regular", size: s) }
}

/// A section card with a stamped heading.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(F.heading(18))
                .foregroundStyle(Ink.yellow)
                .shadow(color: Ink.pink, radius: 0, x: 3, y: 3)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Ink.empty, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// A worn panel key: dark plate, brass rule, lit when on.
struct Key: View {
    let label: String
    var lit = false
    var tag: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(F.text(13))
                .tracking(1)
                .foregroundStyle(lit ? Ink.ink : Ink.cream)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background(lit ? Ink.yellow : Ink.card2)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Ink.yellow.opacity(lit ? 1 : 0.45), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(tag)
    }
}

/// A readout line: quiet label, amber value.
struct Readout: View {
    let label: String
    let value: String
    var tag: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(F.mono(12)).foregroundStyle(Ink.dim)
            Spacer(minLength: 8)
            Text(value).font(F.lcd(14)).foregroundStyle(Ink.yellow).multilineTextAlignment(.trailing)
                .accessibilityIdentifier(tag ?? "readout-\(label)")
        }
    }
}
