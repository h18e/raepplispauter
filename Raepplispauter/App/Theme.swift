import SwiftUI

/// Farb- und Stilwerte der App.
///
/// Gestaltung nach den Apple Human Interface Guidelines mit **Dark Mode als
/// primärem Erscheinungsbild**: tiefer, fast schwarzer Hintergrund, leicht
/// aufgehellte Karten, sparsam gesetzte Akzentfarbe.
public enum Theme {

    // MARK: - Flächen

    public static let background = Color(red: 0.055, green: 0.059, blue: 0.071)
    public static let surface = Color(red: 0.094, green: 0.101, blue: 0.121)
    public static let surfaceElevated = Color(red: 0.129, green: 0.137, blue: 0.161)
    public static let separator = Color.white.opacity(0.08)

    // MARK: - Text

    public static let textPrimary = Color.white
    public static let textSecondary = Color.white.opacity(0.62)
    public static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Akzente

    /// Markenfarbe (auch als AccentColor im Asset-Katalog hinterlegt).
    public static let accent = Color(red: 0.396, green: 0.831, blue: 0.596)
    /// Positiver Saldo (steht im Plus).
    public static let positive = Color(red: 0.396, green: 0.831, blue: 0.596)
    /// Negativer Saldo (schuldet noch).
    public static let negative = Color(red: 0.965, green: 0.447, blue: 0.447)
    /// Hinweise/Warnungen, z. B. fehlender Wechselkurs.
    public static let warning = Color(red: 0.984, green: 0.749, blue: 0.353)

    public static let cornerRadius: CGFloat = 16

    /// Farbe für einen Saldo: Plus grün, Minus rot, Null neutral.
    public static func amountColor(_ value: Decimal) -> Color {
        if Money.isZero(value) { return textSecondary }
        return value > 0 ? positive : negative
    }

    // MARK: - Paletten

    /// Farben für Personen. Die Reise vergibt sie reihum, damit sich auch bei
    /// vielen Teilnehmenden benachbarte Einträge gut unterscheiden lassen.
    private static let participantPalette: [Color] = [
        Color(red: 0.443, green: 0.663, blue: 0.976),   // Blau
        Color(red: 0.878, green: 0.588, blue: 0.925),   // Violett
        Color(red: 0.482, green: 0.827, blue: 0.529),   // Grün
        Color(red: 0.976, green: 0.643, blue: 0.376),   // Orange
        Color(red: 0.361, green: 0.792, blue: 0.827),   // Türkis
        Color(red: 0.929, green: 0.510, blue: 0.522),   // Rot
        Color(red: 0.596, green: 0.612, blue: 0.949),   // Indigo
        Color(red: 0.902, green: 0.796, blue: 0.404)    // Gelb
    ]

    private static let categoryPalette: [Color] = [
        Color(red: 0.443, green: 0.663, blue: 0.976),
        Color(red: 0.976, green: 0.643, blue: 0.376),
        Color(red: 0.482, green: 0.827, blue: 0.529),
        Color(red: 0.596, green: 0.612, blue: 0.949),
        Color(red: 0.929, green: 0.510, blue: 0.522),
        Color(red: 0.361, green: 0.792, blue: 0.827),
        Color(red: 0.878, green: 0.588, blue: 0.925),
        Color(red: 0.902, green: 0.796, blue: 0.404)
    ]

    public static var participantPaletteSize: Int { participantPalette.count }
    public static var categoryPaletteSize: Int { categoryPalette.count }

    public static func participantColor(_ index: Int) -> Color {
        guard !participantPalette.isEmpty else { return accent }
        let safe = ((index % participantPalette.count) + participantPalette.count) % participantPalette.count
        return participantPalette[safe]
    }

    public static func categoryColor(_ index: Int) -> Color {
        guard !categoryPalette.isEmpty else { return accent }
        let safe = ((index % categoryPalette.count) + categoryPalette.count) % categoryPalette.count
        return categoryPalette[safe]
    }
}

/// Karten-Hintergrund im App-Stil.
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .stroke(Theme.separator, lineWidth: 1)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Einheitlicher, dunkler Bildschirmhintergrund.
    func screenBackground() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}
