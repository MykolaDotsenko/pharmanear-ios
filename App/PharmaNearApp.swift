import SwiftUI
import CoreLocation
import MapKit

@main struct PharmaNearApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

@MainActor final class Finder: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var status = "idle"
    @Published var result: SearchResult?
    @Published var origin = ""
    private let manager = CLLocationManager()
    private var task: Task<Void,Never>?
    private var generation = 0
    private var awaitingLocation = false
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    var busy: Bool { status == "loading" || status == "locating" }
    func cancel() { generation += 1; task?.cancel(); task = nil; awaitingLocation = false; manager.stopUpdatingLocation(); result = nil; status = "cancelled" }
    func locate() {
        cancel(); status = "locating"; awaitingLocation = true; origin = "device"
        handleAuthorization()
        let id = generation
        task = Task { [weak self] in
            try? await Task.sleep(nanoseconds:15_000_000_000)
            guard !Task.isCancelled, let self, self.generation == id, self.awaitingLocation else { return }
            self.awaitingLocation = false; self.manager.stopUpdatingLocation(); self.status = "denied"
        }
    }
    private func handleAuthorization() {
        guard awaitingLocation else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse,.authorizedAlways: manager.requestLocation()
        default: awaitingLocation = false; task?.cancel(); status = "denied"
        }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { Task { @MainActor [weak self] in self?.handleAuthorization() } }
    nonisolated func locationManager(_ manager: CLLocationManager,didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last, location.horizontalAccuracy >= 0 else { return }
        let point = Point(lat:location.coordinate.latitude,lon:location.coordinate.longitude)
        Task { @MainActor [weak self] in guard let self, self.awaitingLocation else { return }; self.search(point, name:"device") }
    }
    nonisolated func locationManager(_ manager: CLLocationManager,didFailWithError error: Error) { Task { @MainActor [weak self] in guard let self,self.awaitingLocation else { return }; self.awaitingLocation = false;self.task?.cancel();self.status = "denied" } }
    func search(_ point: Point,name: String) {
        cancel(); origin = name; status = "loading"; let id = generation
        task = Task { [weak self] in
            do { let found = try await PharmacySearch.search(origin:point,fetch:{try await PharmacySearch.fetch(query:$0)}); guard let self, !Task.isCancelled,self.generation == id else{return};self.result = found;self.status = found.pharmacies.isEmpty ? "empty" : "found" }
            catch { guard let self,!Task.isCancelled,self.generation == id else{return};self.status = "error" }
        }
    }
}

// A quiet, native interpretation of the web design, not a web view.
private struct NordicPalette {
    let dark: Bool
    var paper: Color { dark ? Color(red:0.125,green:0.153,blue:0.141) : Color(red:0.965,green:0.957,blue:0.933) }
    var ink: Color { dark ? Color(red:0.945,green:0.941,blue:0.91) : Color(red:0.125,green:0.169,blue:0.157) }
    var muted: Color { dark ? Color(red:0.741,green:0.788,blue:0.757) : Color(red:0.322,green:0.376,blue:0.353) }
    var pine: Color { dark ? Color(red:0.682,green:0.835,blue:0.741) : Color(red:0.09,green:0.282,blue:0.239) }
    var onPine: Color { dark ? Color(red:0.09,green:0.18,blue:0.14) : .white }
    var line: Color { dark ? Color(red:0.275,green:0.341,blue:0.306) : Color(red:0.831,green:0.847,blue:0.808) }
    var wash: Color { dark ? Color(red:0.188,green:0.247,blue:0.212) : Color(red:0.906,green:0.929,blue:0.894) }
    var water: Color { dark ? Color(red:0.20,green:0.30,blue:0.29) : Color(red:0.804,green:0.863,blue:0.855) }
}

private struct NordicButton: ButtonStyle {
    let palette: NordicPalette
    let primary: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(primary ? palette.onPine : palette.pine)
            .padding(.horizontal,16).padding(.vertical,13)
            .frame(minHeight:48)
            .background(primary ? palette.pine : Color.clear, in:RoundedRectangle(cornerRadius:5))
            .overlay(RoundedRectangle(cornerRadius:5).strokeBorder(palette.pine,lineWidth:1))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration:0.16),value:configuration.isPressed)
    }
}

// Decorative contour graphic; intentionally not a map or a simulated location.
private struct ContourArt: View {
    let palette: NordicPalette
    var body: some View {
        Canvas { context,size in
            let w=size.width, h=size.height
            var water=Path()
            water.move(to:CGPoint(x:w*0.48,y:0))
            water.addCurve(to:CGPoint(x:w*0.35,y:h),control1:CGPoint(x:w*0.8,y:h*0.30),control2:CGPoint(x:w*0.02,y:h*0.58))
            water.addLine(to:CGPoint(x:w,y:h)); water.addLine(to:CGPoint(x:w,y:0)); water.closeSubpath()
            context.fill(water,with:.color(palette.water))
            for i in 0..<8 {
                let x=CGFloat(i)*w*0.13-w*0.28
                var line=Path()
                line.move(to:CGPoint(x:x,y:-10))
                line.addCurve(to:CGPoint(x:x+w*0.48,y:h+10),control1:CGPoint(x:x+w*0.7,y:h*0.24),control2:CGPoint(x:x+w*0.02,y:h*0.74))
                context.stroke(line,with:.color(palette.pine.opacity(0.30)),lineWidth:0.8)
            }
            let center=CGPoint(x:w*0.68,y:h*0.48)
            for r in [CGFloat(28),CGFloat(44)] {
                let ring=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:r*2,height:r*2))
                context.stroke(ring,with:.color(palette.pine.opacity(0.48)),lineWidth:1)
            }
            context.fill(Path(ellipseIn:CGRect(x:center.x-16,y:center.y-16,width:32,height:32)),with:.color(palette.pine))
            var cross=Path()
            cross.move(to:CGPoint(x:center.x-7,y:center.y));cross.addLine(to:CGPoint(x:center.x+7,y:center.y))
            cross.move(to:CGPoint(x:center.x,y:center.y-7));cross.addLine(to:CGPoint(x:center.x,y:center.y+7))
            context.stroke(cross,with:.color(palette.onPine),lineWidth:2)
        }
        .background(palette.wash)
        .overlay(Rectangle().strokeBorder(palette.line,lineWidth:1))
        .frame(height:128)
        .accessibilityHidden(true)
    }
}

@MainActor struct ContentView: View {
    @StateObject private var finder = Finder()
    @State private var city = 0
    @State private var language = "en"
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var palette: NordicPalette { NordicPalette(dark:colorScheme == .dark) }
    private func t(_ key: String) -> String { words[language]?[key] ?? words["en"]?[key] ?? key }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:24) {
                    hero
                    ContourArt(palette:palette)
                    results
                    VStack(alignment:.leading,spacing:8) {
                        Rectangle().fill(palette.line).frame(height:1).accessibilityHidden(true)
                        Text(t("disclaimer")).font(.footnote).foregroundStyle(palette.muted)
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
        .environment(\.locale,Locale(identifier:language))
    }
    private var hero: some View {
        VStack(alignment:.leading,spacing:15) {
            Text(t("eyebrow")).font(.caption.weight(.semibold)).tracking(1.7).foregroundStyle(palette.pine)
            Text(t("heading"))
                .font(.system(.largeTitle,design:.serif,weight:.regular))
                .accessibilityAddTraits(.isHeader)
                .fixedSize(horizontal:false,vertical:true)
            Text(t("intro")).font(.body).foregroundStyle(palette.muted)
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
            Text(t("privacy")).font(.footnote).foregroundStyle(palette.muted)
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
            if let result=finder.result, !result.pharmacies.isEmpty {
                LazyVStack(alignment:.leading,spacing:0) {
                    ForEach(Array(result.visiblePharmacies.enumerated()),id:\.element.id) { index,pharmacy in
                        pharmacyRow(pharmacy,index:index)
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration:0.22),value:finder.status)
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
                }
                Spacer(minLength:0)
            }
            HStack(alignment:.center,spacing:12) {
                Text(formattedDistance(pharmacy.distance)).font(.title2.weight(.medium)).monospacedDigit()
                Spacer(minLength:4)
                Button {
                    let item=MKMapItem(placemark:MKPlacemark(coordinate:CLLocationCoordinate2D(latitude:pharmacy.point.lat,longitude:pharmacy.point.lon)))
                    item.name=name
                    item.openInMaps(launchOptions:nil)
                } label: {
                    Label(t("map"),systemImage:"arrow.up.right").font(.subheadline.weight(.semibold)).frame(minHeight:44)
                }.accessibilityLabel(t("map")+": "+name)
            }
        }
        .padding(14)
        .background(index == 0 ? palette.wash : Color.clear)
        .overlay(alignment:.leading) {
            if index == 0 { Rectangle().fill(palette.pine).frame(width:3).accessibilityHidden(true) }
        }
        .overlay(alignment:.bottom) { Rectangle().fill(palette.line).frame(height:1).accessibilityHidden(true) }
    }
    private var statusText: String {
        guard finder.status == "found",let result=finder.result else { return t(finder.status) }
        return "\(t("found")): \(result.pharmacies.count) · \(finder.origin == "device" ? t("device") : finder.origin). \(result.covered ? "" : t("limited"))"
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

private let words: [String:[String:String]] = [
"en":["eyebrow":"PHARMACY FINDER","heading":"Find a pharmacy near you.","intro":"Find the closest mapped pharmacies by straight-line distance. No account needed.","locate":"Use my location","privacy":"Only a location rounded to two decimal places is sent to the Overpass service. Distances are calculated on your device.","city":"City centre","search":"Search","results":"Nearby pharmacies","cancel":"Cancel","idle":"Choose your location to start.","locating":"Getting your location…","loading":"Searching for pharmacies…","denied":"Location is unavailable or denied. Choose a city centre instead.","error":"Search is temporarily unavailable. Try again.","empty":"No mapped pharmacies found within the searched area.","found":"Mapped pharmacies found","device":"your location","limited":"Search coverage is limited.","nearest":"Closest mapped result","unnamed":"Unnamed pharmacy","map":"View on map","disclaimer":"Distances are not walking routes. Check opening hours before travelling. Map data can be incomplete.","language":"Language","cancelled":"Search cancelled."],
"fi":["eyebrow":"APTEEKKIHAKU","heading":"Löydä apteekki läheltäsi.","intro":"Löydä lähimmät kartalla olevat apteekit linnuntie-etäisyyden mukaan. Et tarvitse tiliä.","locate":"Käytä sijaintiani","privacy":"Overpass-palveluun lähetetään vain kahden desimaalin tarkkuuteen pyöristetty sijainti. Etäisyydet lasketaan laitteellasi.","city":"Kaupungin keskusta","search":"Hae","results":"Lähellä olevat apteekit","cancel":"Peruuta","idle":"Valitse sijainti aloittaaksesi.","locating":"Haetaan sijaintia…","loading":"Haetaan apteekkeja…","denied":"Sijaintia ei saatu. Valitse kaupungin keskusta.","error":"Haku ei ole juuri nyt käytettävissä. Yritä uudelleen.","empty":"Hakualueelta ei löytynyt kartalla olevia apteekkeja.","found":"Kartalta löytyneet apteekit","device":"oma sijainti","limited":"Haun kattavuus on rajallinen.","nearest":"Lähin karttatulos","unnamed":"Nimetön apteekki","map":"Näytä kartalla","disclaimer":"Etäisyydet eivät ole kävelyreittejä. Tarkista aukioloajat ennen lähtöä. Karttatiedot voivat olla puutteellisia.","language":"Kieli","cancelled":"Haku peruttu."],
"sv":["eyebrow":"APOTEKSSÖKNING","heading":"Hitta ett apotek nära dig.","intro":"Hitta närmaste kartlagda apotek enligt fågelvägsavstånd. Inget konto behövs.","locate":"Använd min plats","privacy":"Endast en position avrundad till två decimaler skickas till Overpass-tjänsten. Avstånd beräknas på din enhet.","city":"Stadscentrum","search":"Sök","results":"Apotek i närheten","cancel":"Avbryt","idle":"Välj en plats för att börja.","locating":"Hämtar din plats…","loading":"Söker apotek…","denied":"Platsen är otillgänglig. Välj ett stadscentrum.","error":"Sökningen är tillfälligt otillgänglig. Försök igen.","empty":"Inga kartlagda apotek hittades i sökområdet.","found":"Kartlagda apotek hittades","device":"din plats","limited":"Sökningens täckning är begränsad.","nearest":"Närmaste kartresultat","unnamed":"Namnlöst apotek","map":"Visa på karta","disclaimer":"Avstånden är inte promenadrutter. Kontrollera öppettiderna innan du åker. Kartdata kan vara ofullständiga.","language":"Språk","cancelled":"Sökningen avbröts."]]
