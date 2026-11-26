import PharmacyCore
import SwiftUI
import UIKit

/// A foreground-only orientation aid, separate from the one-shot search.
struct PharmacyRadarView: View {
    let pharmacies: [Pharmacy]
    @State private var target: Pharmacy
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
        _target = State(initialValue: target)
    }

    private var palette: NordicPalette { NordicPalette(dark: colorScheme == .dark) }

    /// The choices keep the search's order, so live fixes never reorder an open menu.
    private var choices: [Pharmacy] {
        let first = Array(pharmacies.prefix(8))
        return first.contains { $0.id == target.id } ? first : first + [target]
    }

    var body: some View {
        NavigationStack {
            // Re-read every second, so a fix goes stale on time even when no new one arrives.
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                content(reading: location.tracker.reading(at: timeline.date))
            }
            .background(palette.paper)
            .foregroundStyle(palette.ink)
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
        .onChange(of: target) { _ in guidance = nil }
    }

    @ViewBuilder
    private func content(reading: RadarReading) -> some View {
        let nearest = reading.point.flatMap { origin in pharmacies.map { origin.distance(to: $0.point) }.min() } ?? 0
        let current = RadarGuidance.evaluate(
            reading, target: target.point, nearestDistance: nearest, previous: guidance)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                status(reading)
                if location.reducedAccuracy { preciseLocationNotice }
                if let origin = reading.point, let current {
                    chart(origin: origin, reading: reading, guidance: current)
                    VStack(alignment: .leading, spacing: 4) {
                        modeLabel(reading)
                        Text("GPS accuracy: \(formatted(reading.accuracy))")
                        Text("Radar range: \(formatted(current.range))")
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                }
                Text(verbatim: label(target))
                    .font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !target.name.isEmpty && !target.address.isEmpty {
                    Text(verbatim: target.address).fixedSize(horizontal: false, vertical: true)
                }
                if let current { readout(current) }
                picker
                Text("Straight-line direction only, not a walking route. Nothing is sent or stored.")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Link("Find a pharmacy on Apteekki.fi", destination: .pharmacyDirectory)
                    .frame(minHeight: 44)
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
                .font(.largeTitle)
                .monospacedDigit()
            if let sector = guidance.sector {
                Text(verbatim: direction(sector, relative: guidance.isRelative))
                    .font(.title3.weight(.semibold))
            }
            if let note = noteText(guidance.note) {
                Text(verbatim: note).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var picker: some View {
        let labels = choiceLabels
        return Picker(
            "Choose pharmacy",
            selection: Binding(
                get: { target.id },
                set: { id in
                    if let pharmacy = pharmacies.first(where: { $0.id == id }) { target = pharmacy }
                })
        ) {
            ForEach(choices) { pharmacy in
                Text(verbatim: labels[pharmacy.id] ?? label(pharmacy)).tag(pharmacy.id)
            }
        }
        .pickerStyle(.menu)
    }

    /// Choices that would read the same, such as unnamed pharmacies at one address, are numbered.
    private var choiceLabels: [String: String] {
        var seen: [String: Int] = [:]
        var labels: [String: String] = [:]
        for pharmacy in choices {
            let text = label(pharmacy)
            let count = (seen[text] ?? 0) + 1
            seen[text] = count
            labels[pharmacy.id] = count > 1 ? "\(text) (\(count))" : text
        }
        return labels
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

    private func chart(origin: Point, reading: RadarReading, guidance: RadarGuidance) -> some View {
        // With Reduce Motion the chart does not turn with the phone.
        let heading = reduceMotion ? nil : reading.heading
        let range = guidance.range
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
            context.fill(
                circle(center, min(radius, radius * reading.accuracy / range)), with: .color(.cyan.opacity(0.2)))
            var drawn: [CGPoint] = []
            for pharmacy in [target] + choices.filter({ $0.id != target.id }) {
                let selected = pharmacy.id == target.id
                let meters = origin.distance(to: pharmacy.point)
                guard selected || meters <= range else { continue }
                let bearing = RadarGeometry.bearing(from: origin, to: pharmacy.point)
                let projected = bearing.map {
                    RadarGeometry.project(bearing: $0, heading: heading, distance: meters, range: range)
                }
                let mark = projected.map { CGPoint(x: $0.lon * size.width, y: $0.lat * size.height) } ?? center
                if !selected
                    && (hypot(mark.x - center.x, mark.y - center.y) < 24
                        || drawn.contains(where: { hypot(mark.x - $0.x, mark.y - $0.y) < 30 }))
                {
                    continue
                }
                drawn.append(mark)
                if selected && guidance.sector != nil && hypot(mark.x - center.x, mark.y - center.y) > 18 {
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: mark)
                    context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                if selected && meters > range {
                    // Beyond the range the target sits on the edge as a ring, never looking closer than it is.
                    context.stroke(circle(mark, 13), with: .color(.green), lineWidth: 3)
                } else {
                    context.fill(
                        circle(mark, selected ? 14 : 10), with: .color(selected ? .green : .white.opacity(0.7)))
                }
                var cross = Path()
                cross.move(to: CGPoint(x: mark.x - 4, y: mark.y))
                cross.addLine(to: CGPoint(x: mark.x + 4, y: mark.y))
                cross.move(to: CGPoint(x: mark.x, y: mark.y - 4))
                cross.addLine(to: CGPoint(x: mark.x, y: mark.y + 4))
                context.stroke(cross, with: .color(selected && meters > range ? .green : .black), lineWidth: 2)
            }
            context.fill(circle(center, 5), with: .color(.cyan))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(red: 0.09, green: 0.23, blue: 0.2))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
