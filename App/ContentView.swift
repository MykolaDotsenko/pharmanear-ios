import PharmacyCore
import SwiftUI
import MapKit
import UIKit

@MainActor struct ContentView: View {
    @StateObject private var finder = Finder()
    @State private var city = 0
    @State private var language = "en"
    @State private var selectedMap: Pharmacy?
    @State private var expanded = false
    @State private var privacyExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: NordicPalette { NordicPalette(dark:colorScheme == .dark) }
    private func t(_ key: String) -> String { words[language]?[key] ?? extraWords[language]?[key] ?? uxWords[language]?[key] ?? words["en"]?[key] ?? extraWords["en"]?[key] ?? uxWords["en"]?[key] ?? key }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    hero
                    if finder.status == "idle" { ContourArt(palette:palette) }
                    results
                    VStack(alignment:.leading,spacing:8) {
                        Rectangle().fill(palette.line).frame(height:1).accessibilityHidden(true)
                        Text(t("disclaimer")).font(.footnote).foregroundStyle(palette.muted)
                        Link(t("directory"),destination:URL(string:"https://www.apteekki.fi/apteekkihaku")!).font(.subheadline).frame(minHeight:44)
                        Link("© OpenStreetMap contributors",destination:URL(string:"https://www.openstreetmap.org/copyright")!).font(.footnote).frame(minHeight:44)
                    }
                }
                .frame(maxWidth:620)
                .padding(.horizontal,20).padding(.vertical,24)
                .frame(maxWidth:.infinity)
            }
            .background(palette.paper.ignoresSafeArea())
            .foregroundStyle(palette.ink)
            .tint(palette.pine)
            .toolbarBackground(palette.paper,for:.navigationBar)
            .toolbarBackground(.visible,for:.navigationBar)
            .navigationTitle("PharmaNear")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.navigationBarTrailing) {
                    Menu {
                        Picker(t("language"),selection:$language) {
                            Text("English").tag("en")
                            Text("Suomi").tag("fi")
                            Text("Svenska").tag("sv")
                        }
                    } label: {
                        Label(t("language"),systemImage:"globe").labelStyle(.iconOnly).frame(minWidth:44,minHeight:44)
                    }
                    .accessibilityLabel(t("language"))
                    .accessibilityIdentifier("language")
                }
            }
        }
        .onChange(of:finder.status) { value in
            if value == "loading" || value == "locating" { expanded = false }
            if ["found","empty","error","denied","cancelled"].contains(value) {
                UIAccessibility.post(notification:.announcement,argument:statusText)
            }
        }
        .sheet(item:$selectedMap) { pharmacy in
            PharmacyMapSheet(pharmacy:pharmacy,title:t("mapTitle"),close:t("closeMap"),disclosure:t("mapPrivacy"),unnamed:t("unnamed"))
        }
        .environment(\.locale,Locale(identifier:language))
    }
    private var hero: some View {
        VStack(alignment:.leading,spacing:15) {
            Text(t("eyebrow")).font(.caption.weight(.semibold)).tracking(1.7).foregroundStyle(palette.festiveInk)
            Text(t("heading"))
                .font(.system(finder.status == "idle" ? .largeTitle : .title2,design:.serif,weight:.regular))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal:false,vertical:true)
            if finder.status == "idle" { Text(t("intro")).font(.body).foregroundStyle(palette.muted) }
            Button { finder.locate() } label: {
                HStack(spacing:10) {
                    Image(systemName:"location").accessibilityHidden(true)
                    Text(t("locate")).multilineTextAlignment(.leading)
                    Spacer(minLength:4)
                    Image(systemName:"arrow.up.right").font(.subheadline).accessibilityHidden(true)
                }.frame(maxWidth:.infinity)
            }
            .buttonStyle(NordicButton(palette:palette,primary:true))
            .accessibilityIdentifier("use-location")
            DisclosureGroup(isExpanded:$privacyExpanded) {
                Text(t("privacy")).font(.footnote).foregroundStyle(palette.muted).frame(maxWidth:.infinity,alignment:.leading)
            } label: { Text(t("privacySummary")).font(.subheadline).foregroundStyle(palette.pine).frame(minHeight:44,alignment:.leading) }
            VStack(alignment:.leading,spacing:6) {
                Text(t("city")).font(.subheadline.weight(.semibold))
                if typeSize.isAccessibilitySize {
                    cityPicker
                    citySearch
                } else {
                    HStack(spacing:12) {
                        cityPicker
                        Spacer(minLength:4)
                        citySearch
                    }
                }
            }
        }
    }
    private var cityPicker: some View {
        Picker(t("city"),selection:$city) {
            ForEach(PharmacySearch.cities.indices,id:\.self) { Text(PharmacySearch.cities[$0].0).tag($0) }
        }
        .pickerStyle(.menu)
        .frame(minHeight:48,alignment:.leading)
        .accessibilityIdentifier("city-picker")
    }
    private var citySearch: some View {
        Button(t("search")) {
            let selected=PharmacySearch.cities[city]
            finder.search(selected.1,name:selected.0)
        }
        .buttonStyle(NordicButton(palette:palette,primary:false))
        .accessibilityIdentifier("city-search")
    }
    private var results: some View {
        VStack(alignment:.leading,spacing:12) {
            Rectangle().fill(palette.line).frame(height:1).accessibilityHidden(true)
            HStack(alignment:.firstTextBaseline) {
                Text(t("results")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer(minLength:8)
                if finder.busy { Button(t("cancel")) { finder.cancel() }.font(.subheadline).frame(minHeight:44) }
            }
            if finder.busy {
                ProgressView(t(finder.status)).font(.subheadline).foregroundStyle(palette.muted)
            } else {
                Text(statusText).font(.subheadline).foregroundStyle(palette.muted).accessibilityIdentifier("search-status")
            }
            if ["error","denied","empty"].contains(finder.status) {
                VStack(alignment:.leading,spacing:8) {
                    if finder.status == "error" {
                        Button(t("retry")) { finder.retry() }.buttonStyle(NordicButton(palette:palette,primary:false))
                    }
                    Link(t("fallback"),destination:URL(string:"https://www.apteekki.fi/apteekkihaku")!).font(.subheadline.weight(.semibold)).frame(minHeight:44)
                }
            }
            if let result=finder.result, !result.pharmacies.isEmpty {
                Text(t("distanceNote")).font(.footnote).foregroundStyle(palette.muted)
                Text(t("mapPrivacy")).font(.caption).foregroundStyle(palette.muted)
                LazyVStack(alignment:.leading,spacing:0) {
                    ForEach(Array(result.visiblePharmacies.prefix(expanded ? 20 : 5).enumerated()),id:\.element.id) { index,pharmacy in
                        pharmacyRow(pharmacy,index:index)
                    }
                }
                if result.pharmacies.count > 5 {
                    Button(expanded ? t("showLess") : t("showAll")) { expanded.toggle() }
                        .buttonStyle(NordicButton(palette:palette,primary:false))
                        .accessibilityIdentifier("show-more")
                }
            }
        }
        // Do not fade text during status changes; maintain contrast throughout.
    }
    private func pharmacyRow(_ pharmacy: Pharmacy,index:Int) -> some View {
        let name=pharmacy.name.isEmpty ? t("unnamed") : pharmacy.name
        return VStack(alignment:.leading,spacing:10) {
            HStack(alignment:.top,spacing:12) {
                Text(String(format:"%02d",index+1)).font(.caption.monospacedDigit()).foregroundStyle(palette.muted).accessibilityHidden(true)
                VStack(alignment:.leading,spacing:5) {
                    if index == 0 { Text(t("nearest")).font(.caption.weight(.semibold)).foregroundStyle(palette.pine) }
                    Text(name).font(.headline).fixedSize(horizontal:false,vertical:true)
                    if !pharmacy.address.isEmpty { Text(pharmacy.address).font(.subheadline).foregroundStyle(palette.muted) }
                    Text(pharmacy.hours.isEmpty ? t("missingHours") : t("hours")+": "+pharmacy.hours).font(.footnote).foregroundStyle(palette.muted)
                }
                Spacer(minLength:0)
            }
            VStack(alignment:.leading,spacing:6) {
                Text(formattedDistance(pharmacy.distance)).font(.title2.weight(.medium)).monospacedDigit()
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:16) { mapPreview(pharmacy,name:name); externalMap(pharmacy,name:name) }
                    VStack(alignment:.leading,spacing:0) { mapPreview(pharmacy,name:name); externalMap(pharmacy,name:name) }
                }
            }
        }
        .padding(14)
        .background(index == 0 ? palette.wash : Color.clear)
        .overlay(alignment:.leading) {
            if index == 0 { Rectangle().fill(palette.pine).frame(width:3).accessibilityHidden(true) }
        }
        .overlay(alignment:.bottom) { Rectangle().fill(palette.line).frame(height:1).accessibilityHidden(true) }
    }
    private func externalMap(_ pharmacy: Pharmacy,name:String) -> some View {
                Button {
                    let item=MKMapItem(placemark:MKPlacemark(coordinate:CLLocationCoordinate2D(latitude:pharmacy.point.lat,longitude:pharmacy.point.lon)))
                    item.name=name
                    item.openInMaps(launchOptions:nil)
                } label: {
                    Label(t("map"),systemImage:"arrow.up.right").font(.subheadline.weight(.semibold)).frame(minHeight:44)
                }.accessibilityLabel(t("map")+": "+name)
    }
    private func mapPreview(_ pharmacy: Pharmacy,name:String) -> some View {
        Button { selectedMap=pharmacy } label: { Label(t("mapHere"),systemImage:"map").font(.subheadline.weight(.semibold)).frame(minHeight:44) }
            .accessibilityLabel(t("mapHere")+": "+name).accessibilityHint(t("mapPrivacy"))
    }
    private var statusText: String {
        guard finder.status == "found",let result=finder.result else { return t(finder.status) }
        return "\(t("found")): \(result.pharmacies.count) · \(finder.origin == "device" ? t("device") : finder.origin). \(result.covered ? "" : t("limited")) \(result.pharmacies.count > 20 ? t("shown") : "")"
    }
    private func formattedDistance(_ meters:Double) -> String {
        let value=meters < 1000 ? Measurement(value:meters,unit:UnitLength.meters) : Measurement(value:meters/1000,unit:UnitLength.kilometers)
        let formatter=MeasurementFormatter()
        formatter.locale=Locale(identifier:language)
        formatter.unitOptions = .providedUnit
        formatter.numberFormatter.maximumFractionDigits=meters < 1000 ? 0 : 1
        return formatter.string(from:value)
    }
}

