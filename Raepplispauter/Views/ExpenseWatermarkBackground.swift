import SwiftUI

/// Dezenter Hintergrund aus Symbolen typischer gemeinsamer Ausgaben.
///
/// Wirkt wie ein Wasserzeichen: sehr geringe Deckkraft, wechselnde Grössen und
/// leichte Drehungen. Die Anordnung **sieht** zufällig aus, ist aber
/// deterministisch – mit echtem Zufall würde das Muster bei jedem Neuzeichnen
/// der Ansicht neu ausgewürfelt und sichtbar springen.
///
/// Verteilt wird über ein Raster mit Streuung statt frei zufällig: rein
/// zufällige Punkte bilden Klumpen und lassen Löcher, ein gestreutes Raster
/// deckt die Fläche gleichmässig ab und wirkt trotzdem ungeordnet.
struct ExpenseWatermarkBackground: View {

    /// Symbole rund um gemeinsame Ausgaben – Essen, Unterwegs, Wohnen, Freizeit.
    static let defaultSymbols: [String] = [
        "fork.knife", "cart.fill", "bed.double.fill", "car.fill",
        "tram.fill", "airplane", "fuelpump.fill", "cup.and.saucer.fill",
        "wineglass.fill", "ticket.fill", "bag.fill", "basket.fill",
        "creditcard.fill", "banknote.fill", "house.fill", "popcorn.fill",
        "film.fill", "music.note", "gift.fill", "birthday.cake.fill",
        "beach.umbrella.fill", "figure.hiking", "bicycle", "ferry.fill",
        "map.fill", "camera.fill", "theatermasks.fill", "sportscourt.fill",
        "cross.case.fill", "parkingsign", "binoculars.fill", "mountain.2.fill"
    ]

    var symbols: [String] = defaultSymbols
    /// Kantenlänge einer Rasterzelle. Kleiner = dichteres Muster.
    var cellSize: CGFloat = 92
    /// Grunddeckkraft. Bewusst sehr niedrig – der Hintergrund soll den Text
    /// tragen, nicht mit ihm konkurrieren.
    var opacity: Double = 0.06

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(placements(in: geometry.size)) { item in
                    Image(systemName: item.symbol)
                        .font(.system(size: item.size, weight: .light))
                        .foregroundStyle(Theme.textPrimary)
                        .opacity(item.opacity)
                        .rotationEffect(.degrees(item.rotation))
                        .position(x: item.x, y: item.y)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Anordnung

    private struct Placement: Identifiable {
        let id: Int
        let symbol: String
        let x: CGFloat
        let y: CGFloat
        let size: CGFloat
        let rotation: Double
        let opacity: Double
    }

    private func placements(in size: CGSize) -> [Placement] {
        guard size.width > 0, size.height > 0, !symbols.isEmpty else { return [] }

        // Eine Zelle Überstand auf jeder Seite, damit auch die Ränder gefüllt
        // sind und keine leeren Streifen entstehen.
        let columns = max(1, Int((size.width / cellSize).rounded(.up)) + 1)
        let rows = max(1, Int((size.height / cellSize).rounded(.up)) + 1)

        var generator = SeededGenerator(seed: 0x5AE9_1C2B)
        var result: [Placement] = []
        result.reserveCapacity(columns * rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let jitterX = CGFloat.random(in: -0.42...0.42, using: &generator)
                let jitterY = CGFloat.random(in: -0.42...0.42, using: &generator)

                result.append(
                    Placement(
                        id: result.count,
                        symbol: symbols[Int.random(in: 0..<symbols.count, using: &generator)],
                        x: (CGFloat(column) + 0.5 + jitterX) * cellSize - cellSize / 2,
                        y: (CGFloat(row) + 0.5 + jitterY) * cellSize - cellSize / 2,
                        size: CGFloat.random(in: 22...46, using: &generator),
                        rotation: Double.random(in: -28...28, using: &generator),
                        // Leicht schwankende Deckkraft nimmt dem Muster die
                        // Gleichförmigkeit und lässt es räumlicher wirken.
                        opacity: opacity * Double.random(in: 0.55...1.45, using: &generator)
                    )
                )
            }
        }
        return result
    }
}

/// Zufallsquelle mit festem Startwert (SplitMix64).
///
/// Liefert bei gleichem Startwert immer dieselbe Folge – nötig, damit das
/// Wasserzeichen bei jedem Neuzeichnen identisch bleibt.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    ZStack {
        Theme.background.ignoresSafeArea()
        ExpenseWatermarkBackground()
        Text("Wasserzeichen")
            .font(.title.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
    }
    .preferredColorScheme(.dark)
}
