import SwiftUI

/// Paper, pine and water, with a cranberry and candlelight variant from 25 November to 6 January.
/// Every text colour keeps at least 4.5:1 contrast with the paper and wash it sits on (5.2:1 at worst).
struct NordicPalette {
    let dark: Bool
    let christmas: Bool

    init(dark: Bool) {
        self.dark = dark
        christmas = Self.isChristmasSeason()
    }

    private static func isChristmasSeason() -> Bool {
        let day = Calendar(identifier: .gregorian).dateComponents([.month, .day], from: Date())
        guard let month = day.month, let dayOfMonth = day.day else { return false }
        return (month == 11 && dayOfMonth >= 25) || month == 12 || (month == 1 && dayOfMonth <= 6)
    }

    var paper: Color { seasonal(regular: (0xF6F4EE, 0x202724), festive: (0xFFF8ED, 0x202A24)) }
    var ink: Color { seasonal(regular: (0x202B28, 0xF1F0E8), festive: (0x302821, 0xFFF3DF)) }
    var muted: Color { seasonal(regular: (0x52605A, 0xBDC9C1), festive: (0x62534A, 0xD3C9B9)) }
    var pine: Color { seasonal(regular: (0x17483D, 0xAED5BD), festive: (0x194B38, 0xB5D9BD)) }
    var line: Color { seasonal(regular: (0xD4D8CE, 0x46574E), festive: (0xDBCAB5, 0x59685B)) }
    var wash: Color { seasonal(regular: (0xE7EDE4, 0x303F36), festive: (0xE5EDDF, 0x34473A)) }
    var water: Color { seasonal(regular: (0xCDDCDA, 0x334D4B), festive: (0xA8C6B8, 0x315B49)) }
    var onPine: Color { dark ? Self.rgb(0x172E24) : .white }

    // Festive-only accents; outside the season they reuse the regular tokens.
    var land: Color { christmas ? appearance(light: 0xE9DFC8, dark: 0x414E38) : wash }
    var primary: Color { christmas ? appearance(light: 0x8B263B, dark: 0xAE3E54) : pine }
    var onPrimary: Color { christmas ? appearance(light: 0xFFF8ED, dark: 0xFFF9EE) : onPine }
    var festiveInk: Color { christmas ? appearance(light: 0x8B263B, dark: 0xF0A9B5) : pine }
    var gold: Color { christmas ? appearance(light: 0xAA7934, dark: 0xE4BD76) : line }

    /// Picks the (light, dark) pair for the current season, then the colour for the appearance.
    private func seasonal(regular: (UInt32, UInt32), festive: (UInt32, UInt32)) -> Color {
        let pair = christmas ? festive : regular
        return appearance(light: pair.0, dark: pair.1)
    }

    private func appearance(light: UInt32, dark: UInt32) -> Color {
        Self.rgb(self.dark ? dark : light)
    }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct NordicButton: ButtonStyle {
    let palette: NordicPalette
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? palette.onPrimary : palette.pine)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(minHeight: 48)
            .background(primary ? palette.primary : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(primary ? palette.primary : palette.pine, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

/// Decorative contour graphic; intentionally not a map or a simulated location.
struct ContourArt: View {
    let palette: NordicPalette

    var body: some View {
        Canvas { context, size in
            drawWater(in: &context, size: size)
            drawContours(in: &context, size: size)
            if palette.christmas {
                drawWinter(in: &context, size: size)
            }
            drawLocator(in: &context, size: size)
        }
        .background(palette.land)
        .overlay(Rectangle().strokeBorder(palette.gold, lineWidth: 1))
        .frame(height: 128)
        .accessibilityHidden(true)
    }

    private func drawWater(in context: inout GraphicsContext, size: CGSize) {
        let (w, h) = (size.width, size.height)
        var water = Path()
        water.move(to: CGPoint(x: w * 0.48, y: 0))
        water.addCurve(
            to: CGPoint(x: w * 0.35, y: h),
            control1: CGPoint(x: w * 0.8, y: h * 0.30),
            control2: CGPoint(x: w * 0.02, y: h * 0.58))
        water.addLine(to: CGPoint(x: w, y: h))
        water.addLine(to: CGPoint(x: w, y: 0))
        water.closeSubpath()
        context.fill(water, with: .color(palette.water))
    }

    private func drawContours(in context: inout GraphicsContext, size: CGSize) {
        let (w, h) = (size.width, size.height)
        for index in 0..<8 {
            let x = CGFloat(index) * w * 0.13 - w * 0.28
            var line = Path()
            line.move(to: CGPoint(x: x, y: -10))
            line.addCurve(
                to: CGPoint(x: x + w * 0.48, y: h + 10),
                control1: CGPoint(x: x + w * 0.7, y: h * 0.24),
                control2: CGPoint(x: x + w * 0.02, y: h * 0.74))
            context.stroke(line, with: .color(palette.pine.opacity(0.30)), lineWidth: 0.8)
        }
    }

    /// Still, abstract winter details: two pines, a star and a snow line. No animation.
    private func drawWinter(in context: inout GraphicsContext, size: CGSize) {
        let (w, h) = (size.width, size.height)
        var pines = Path()
        for (x, scale) in [(w * 0.13, CGFloat(1)), (w * 0.23, CGFloat(0.75))] {
            let y = h * 0.88
            pines.move(to: CGPoint(x: x, y: y))
            pines.addLine(to: CGPoint(x: x, y: y - 48 * scale))
            for (level, half) in [(CGFloat(12), CGFloat(8)), (23, 12), (34, 16)] {
                let top = y - (48 - level) * scale
                pines.move(to: CGPoint(x: x, y: top - 8 * scale))
                pines.addLine(to: CGPoint(x: x - half * scale, y: top + 3 * scale))
                pines.move(to: CGPoint(x: x, y: top - 8 * scale))
                pines.addLine(to: CGPoint(x: x + half * scale, y: top + 3 * scale))
            }
        }
        context.stroke(
            pines, with: .color(palette.pine), style: StrokeStyle(lineWidth: 1.25, lineCap: .round, lineJoin: .round))

        let star = CGPoint(x: w * 0.87, y: h * 0.22)
        var rays = Path()
        for (dx, dy) in [(8.0, 0.0), (0.0, 8.0), (4.0, 4.0), (4.0, -4.0)] {
            rays.move(to: CGPoint(x: star.x - dx, y: star.y - dy))
            rays.addLine(to: CGPoint(x: star.x + dx, y: star.y + dy))
        }
        context.stroke(rays, with: .color(palette.gold), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

        var snow = Path()
        snow.move(to: CGPoint(x: w * 0.05, y: h * 0.91))
        snow.addQuadCurve(to: CGPoint(x: w * 0.34, y: h * 0.91), control: CGPoint(x: w * 0.20, y: h * 0.84))
        context.stroke(snow, with: .color(palette.paper.opacity(0.9)), lineWidth: 1.5)
    }

    private func drawLocator(in context: inout GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width * 0.68, y: size.height * 0.48)
        for radius in [CGFloat(28), CGFloat(44)] {
            let ring = Path(
                ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            context.stroke(ring, with: .color(palette.pine.opacity(0.48)), lineWidth: 1)
        }
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)),
            with: .color(palette.primary))
        var cross = Path()
        cross.move(to: CGPoint(x: center.x - 7, y: center.y))
        cross.addLine(to: CGPoint(x: center.x + 7, y: center.y))
        cross.move(to: CGPoint(x: center.x, y: center.y - 7))
        cross.addLine(to: CGPoint(x: center.x, y: center.y + 7))
        context.stroke(cross, with: .color(palette.onPrimary), lineWidth: 2)
    }
}
