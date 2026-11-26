import PharmacyCore
import SwiftUI
import UIKit

/// A foreground-only orientation aid for one pharmacy, the one whose row opened it. It starts as it opens; the
/// distance and the way to turn come first, then the dial with only that pharmacy on it.
struct PharmacyRadarView: View {
    /// The result set, used only to tell when every result is far away.
    let pharmacies: [Pharmacy]
    let target: Pharmacy
    @StateObject private var location = RadarLocation()
    @State private var guidance: RadarGuidance?
    @State private var announcer = RadarAnnouncer()
    @State private var previousIdleTimer: Bool?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openURL) private var openURL

    init(pharmacies: [Pharmacy], target: Pharmacy) {
        self.pharmacies = pharmacies
        self.target = target
    }

    private var palette: NordicPalette { NordicPalette(dark: colorScheme == .dark) }

    var body: some View {
        NavigationStack {
            // Re-read every second, so a fix goes stale on time even when no new one arrives.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(reading: location.tracker.reading(at: timeline.date))
            }
            .background(palette.paper)
            .foregroundStyle(palette.ink)
            // The sheet's own bar, styled like the main screen's: pine actions on paper keep their contrast.
            .tint(palette.pine)
            .toolbarBackground(palette.paper, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("Pharmacy radar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close radar") { dismiss() }
                }
            }
        }
        .onAppear { if scenePhase == .active { location.start() } }
        .onDisappear {
            location.stop(clear: true)
            releaseScreen()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                location.start()
            case .background:
                location.stop()
                releaseScreen()
            default:
                // The location prompt makes the app inactive; stopping then would dismiss the prompt.
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            location.updateOrientation()
        }
    }

    @ViewBuilder
    private func content(reading: RadarReading) -> some View {
        let nearest = reading.point.flatMap { origin in pharmacies.map { origin.distance(to: $0.point) }.min() } ?? 0
        let current = RadarGuidance.evaluate(
            reading, target: target.point, nearestDistance: nearest, previous: guidance)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: label(target))
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    status(reading)
                        .font(.subheadline)
                        .foregroundStyle(palette.muted)
                }
                if location.reducedAccuracy { preciseLocationNotice }
                // What to do comes first: the distance and the way to turn, then the dial.
                if let current { readout(current) }
                if !location.denied {
                    chart(origin: reading.point, reading: reading, guidance: current)
                        .frame(maxWidth: 360)
                        .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let current {
                        modeLabel(reading)
                        Text("GPS accuracy: \(formatted(reading.accuracy))")
                        Text("Radar range: \(formatted(current.range))")
                    }
                    Text("Straight-line direction only, not a walking route. Nothing is sent or stored.")
                }
                .font(.footnote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: current) { next in
            guidance = next
            if let next { announce(next) }
        }
        .onChange(of: reading.isLive) { live in
            if live && scenePhase == .active { holdScreen() } else { releaseScreen() }
        }
    }

    @ViewBuilder
    private func status(_ reading: RadarReading) -> some View {
        if location.denied {
            Text("Location unavailable or denied.")
        } else if reading.isLive {
            Text("Live GPS")
        } else {
            Text("Waiting for a new GPS fix…")
        }
    }

    @ViewBuilder
    private func modeLabel(_ reading: RadarReading) -> some View {
        // With Reduce Motion the chart stays north-up; the words still say where to turn.
        if reduceMotion || reading.mode == .northUp {
            Text("North-up")
        } else if reading.mode == .compass {
            Text("Compass-up")
        } else {
            Text("Direction of travel")
        }
    }

    private var preciseLocationNotice: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Precise Location is off, so the radar cannot point the way.")
            Text("Turn it on for PharmaNear in Settings.")
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .frame(minHeight: 44)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Distance, direction and note, read by VoiceOver as one element that updates.
    private func readout(_ guidance: RadarGuidance) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Straight-line distance")
                .font(.caption)
                .foregroundStyle(palette.muted)
            Text(verbatim: formatted(guidance.distance))
                .font(.largeTitle.weight(.bold))
                .monospacedDigit()
            if let sector = guidance.sector {
                Text(verbatim: direction(sector, relative: guidance.isRelative))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(palette.pine)
            }
            if let note = noteText(guidance.note) {
                Text(verbatim: note).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func label(_ pharmacy: Pharmacy) -> String {
        guard pharmacy.name.isEmpty else { return pharmacy.name }
        let unnamed = String(localized: "Pharmacy — name unavailable")
        return pharmacy.address.isEmpty ? unnamed : "\(unnamed) (\(pharmacy.address))"
    }

    private func noteText(_ note: RadarGuidance.Note) -> String? {
        switch note {
        case .near: return String(localized: "Near the mapped pharmacy. Look for its entrance.")
        case .uncertain: return String(localized: "The pharmacy is within GPS uncertainty, so no direction is shown.")
        case .farResults: return String(localized: "These results are far from you. Search from your location instead.")
        case .outsideRange: return String(localized: "Target is outside the displayed range.")
        case .none: return nil
        }
    }

    /// VoiceOver hears the distance, direction and note when something meaningful changes, not on every fix.
    private func announce(_ guidance: RadarGuidance) {
        guard UIAccessibility.isVoiceOverRunning,
            announcer.shouldAnnounce(target: target.id, guidance: guidance, now: Date())
        else { return }
        let parts = [
            formatted(guidance.distance), guidance.sector.map { direction($0, relative: guidance.isRelative) },
            noteText(guidance.note),
        ]
        UIAccessibility.post(notification: .announcement, argument: parts.compactMap { $0 }.joined(separator: ". "))
    }

    private func holdScreen() {
        guard previousIdleTimer == nil else { return }
        previousIdleTimer = UIApplication.shared.isIdleTimerDisabled
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func releaseScreen() {
        guard let previousIdleTimer else { return }
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimer
        self.previousIdleTimer = nil
    }

    private func formatted(_ meters: Double) -> String {
        let isShort = meters < 1000
        let value =
            isShort
            ? Measurement(value: meters, unit: UnitLength.meters)
            : Measurement(value: meters / 1000, unit: UnitLength.kilometers)
        return value.formatted(
            .measurement(
                width: .abbreviated, usage: .asProvided,
                numberFormatStyle: .number.precision(.fractionLength(0...(isShort ? 0 : 1)))))
    }

    private func direction(_ sector: Int, relative: Bool) -> String {
        let labels =
            relative
            ? [
                String(localized: "Ahead"), String(localized: "Slightly right"), String(localized: "Right"),
                String(localized: "Behind right"), String(localized: "Behind"), String(localized: "Behind left"),
                String(localized: "Left"), String(localized: "Slightly left"),
            ]
            : [
                String(localized: "North"), String(localized: "North-east"), String(localized: "East"),
                String(localized: "South-east"), String(localized: "South"), String(localized: "South-west"),
                String(localized: "West"), String(localized: "North-west"),
            ]
        return labels[sector % 8]
    }

    /// The dial: rings, north, you in the middle and, once there is a fix, the one pharmacy with its needle.
    /// It shows at once, while the first fix is awaited, so the sheet does not jump when it arrives.
    private func chart(origin: Point?, reading: RadarReading, guidance: RadarGuidance?) -> some View {
        // With Reduce Motion the chart does not turn with the phone.
        let heading = reduceMotion ? nil : reading.heading
        return Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.41
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(
                    ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
                )
            }
            for ring in 1...4 {
                context.stroke(
                    circle(center, radius * CGFloat(ring) / 4), with: .color(.white.opacity(0.3)), lineWidth: 1)
            }
            let north = (0 - (heading ?? 0)) * .pi / 180
            context.draw(
                Text("N").font(.caption.weight(.semibold)).foregroundColor(.white),
                at: CGPoint(x: center.x + side * 0.46 * sin(north), y: center.y - side * 0.46 * cos(north)))
            if let origin, let guidance {
                let range = guidance.range
                context.fill(
                    circle(center, min(radius, radius * reading.accuracy / range)), with: .color(.cyan.opacity(0.2)))
                let meters = guidance.distance
                let projected = RadarGeometry.bearing(from: origin, to: target.point).map {
                    RadarGeometry.project(bearing: $0, heading: heading, distance: meters, range: range)
                }
                let mark = projected.map { CGPoint(x: $0.lon * size.width, y: $0.lat * size.height) } ?? center
                if guidance.sector != nil && hypot(mark.x - center.x, mark.y - center.y) > 18 {
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: mark)
                    context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                let beyond = meters > range
                if beyond {
                    // Beyond the range the pharmacy sits on the edge as a ring, never looking closer than it is.
                    context.stroke(circle(mark, 14), with: .color(.green), lineWidth: 3)
                } else {
                    context.fill(circle(mark, 15), with: .color(.green))
                }
                var cross = Path()
                cross.move(to: CGPoint(x: mark.x - 5, y: mark.y))
                cross.addLine(to: CGPoint(x: mark.x + 5, y: mark.y))
                cross.move(to: CGPoint(x: mark.x, y: mark.y - 5))
                cross.addLine(to: CGPoint(x: mark.x, y: mark.y + 5))
                context.stroke(cross, with: .color(beyond ? .green : .black), lineWidth: 2)
            }
            // You, dimmed until the first fix.
            context.fill(circle(center, 5), with: .color(.cyan.opacity(origin == nil ? 0.5 : 1)))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(red: 0.09, green: 0.23, blue: 0.2))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
