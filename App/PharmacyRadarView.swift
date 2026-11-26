import PharmacyCore
import SwiftUI
import UIKit

/// A foreground-only orientation aid, separate from the one-shot search.
struct PharmacyRadarView: View {
    let pharmacies: [Pharmacy]
    @State private var target: Pharmacy
    @StateObject private var location = RadarLocation()
    @State private var range = 200.0
    @State private var near = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme

    init(pharmacies: [Pharmacy], target: Pharmacy) {
        self.pharmacies = pharmacies
        _target = State(initialValue: target)
    }

    private var palette: NordicPalette { NordicPalette(dark: colorScheme == .dark) }
    private var distance: Double? { location.point?.distance(to: target.point) }
    private var bearing: Double? { location.point.flatMap { RadarGeometry.bearing(from: $0, to: target.point) } }

    private var candidates: [Pharmacy] {
        guard let origin = location.point else { return Array(pharmacies.prefix(8)) }
        let sorted = pharmacies.sorted { origin.distance(to: $0.point) < origin.distance(to: $1.point) }
        var result = Array(sorted.prefix(8))
        if !result.contains(where: { $0.id == target.id }) { result.append(target) }
        return result
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    status
                    if let origin = location.point {
                        chart(origin: origin)
                        Text("GPS accuracy: \(formatted(location.accuracy))")
                            .font(.footnote)
                        Text("Radar range: \(formatted(range))")
                            .font(.footnote)
                    }
                    Text(verbatim: target.name.isEmpty ? String(localized: "Unnamed pharmacy") : target.name)
                        .font(.title2.weight(.semibold))
                    Text(verbatim: target.address)
                    if let distance {
                        Text(verbatim: formatted(distance))
                            .font(.largeTitle.monospacedDigit())
                        if location.fresh {
                            if near {
                                Text("Near the mapped pharmacy. Look for its entrance.")
                            } else if distance <= location.accuracy {
                                Text("The pharmacy is within GPS uncertainty.")
                            } else if let bearing {
                                Text(verbatim: direction(bearing))
                            }
                        }
                    }
                    Picker("Choose pharmacy", selection: Binding(get: { target.id }, set: { id in
                        if let pharmacy = pharmacies.first(where: { $0.id == id }) { target = pharmacy }
                    })) {
                        ForEach(candidates) { pharmacy in
                            Text(verbatim: pharmacy.name.isEmpty ? String(localized: "Unnamed pharmacy") : pharmacy.name)
                                .tag(pharmacy.id)
                        }
                    }
                    .pickerStyle(.menu)
                    Text("Straight-line direction only, not a walking route. Live location stays on this device.")
                        .font(.footnote)
                    Link("Find a pharmacy on Apteekki.fi", destination: .pharmacyDirectory)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
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
        .onDisappear { location.stop(clear: true) }
        .onChange(of: scenePhase) { phase in
            if phase == .active { location.start() } else { location.stop() }
        }
        .onChange(of: location.point) { _ in updateRange() }
        .onChange(of: location.accuracy) { _ in updateRange() }
        .onChange(of: target) { _ in
            range = distance.map { RadarGeometry.range(distance: $0) } ?? 200
            near = false
            updateRange()
        }
    }

    @ViewBuilder
    private var status: some View {
        if location.denied {
            Text("Location unavailable or denied.")
        } else if location.fresh {
            Text("Live GPS")
        } else {
            Text("Waiting for a new GPS fix…")
        }
    }

    private func updateRange() {
        guard let distance else { return }
        range = RadarGeometry.range(distance: distance, current: range)
        near = location.fresh && RadarGeometry.isNear(distance: distance, accuracy: location.accuracy, wasNear: near)
    }

    private func formatted(_ meters: Double) -> String {
        let value = meters < 1000
            ? Measurement(value: meters, unit: UnitLength.meters)
            : Measurement(value: meters / 1000, unit: UnitLength.kilometers)
        return value.formatted(.measurement(width: .abbreviated, usage: .asProvided))
    }

    private func direction(_ bearing: Double) -> String {
        let angle = RadarGeometry.degrees(bearing - (location.heading ?? 0))
        let index = Int((angle / 45).rounded()) % 8
        let labels = location.heading == nil
            ? [String(localized: "North"), String(localized: "North-east"), String(localized: "East"),
                String(localized: "South-east"), String(localized: "South"), String(localized: "South-west"),
                String(localized: "West"), String(localized: "North-west")]
            : [String(localized: "Ahead"), String(localized: "Slightly right"), String(localized: "Right"),
                String(localized: "Behind right"), String(localized: "Behind"), String(localized: "Behind left"),
                String(localized: "Left"), String(localized: "Slightly left")]
        return labels[index]
    }

    private func chart(origin: Point) -> some View {
        Canvas { context, size in
            let side = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = side * 0.41
            func circle(_ center: CGPoint, _ radius: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            }
            for ring in 1...4 {
                context.stroke(circle(center, radius * CGFloat(ring) / 4), with: .color(.white.opacity(0.3)), lineWidth: 1)
            }
            context.fill(circle(center, min(radius, radius * location.accuracy / range)), with: .color(.cyan.opacity(0.2)))
            var drawn: [CGPoint] = []
            for pharmacy in [target] + candidates.filter({ $0.id != target.id }) {
                let selected = pharmacy.id == target.id
                let meters = origin.distance(to: pharmacy.point)
                guard selected || meters <= range else { continue }
                let b = RadarGeometry.bearing(from: origin, to: pharmacy.point)
                let p = b.map { RadarGeometry.project(bearing: $0, heading: location.heading, distance: meters, range: range) }
                let mark = p.map { CGPoint(x: $0.lon * size.width, y: $0.lat * size.height) } ?? center
                if !selected && (hypot(mark.x - center.x, mark.y - center.y) < 24 ||
                    drawn.contains(where: { hypot(mark.x - $0.x, mark.y - $0.y) < 30 })) { continue }
                drawn.append(mark)
                if selected && location.fresh && !near && hypot(mark.x - center.x, mark.y - center.y) > 18 {
                    var line = Path()
                    line.move(to: center)
                    line.addLine(to: mark)
                    context.stroke(line, with: .color(.white), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                }
                context.fill(circle(mark, selected ? 14 : 10), with: .color(selected ? .green : .white.opacity(0.7)))
                var cross = Path()
                cross.move(to: CGPoint(x: mark.x - 4, y: mark.y))
                cross.addLine(to: CGPoint(x: mark.x + 4, y: mark.y))
                cross.move(to: CGPoint(x: mark.x, y: mark.y - 4))
                cross.addLine(to: CGPoint(x: mark.x, y: mark.y + 4))
                context.stroke(cross, with: .color(.black), lineWidth: 2)
            }
            context.fill(circle(center, 5), with: .color(.cyan))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(Color(red: 0.09, green: 0.23, blue: 0.2))
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
