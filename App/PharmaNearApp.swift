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

struct ContentView: View {
    @StateObject private var finder = Finder()
    @State private var city = 0
    @State private var language = "en"
    private let teal = Color(red:0.08,green:0.37,blue:0.31)
    private func t(_ key: String) -> String { words[language]?[key] ?? words["en"]?[key] ?? key }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:22) {
                    VStack(alignment:.leading,spacing:12) {
                        Label("PharmaNear",systemImage:"cross.case.fill").font(.headline).foregroundStyle(teal)
                        Text(t("heading")).font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                        Text(t("intro")).foregroundStyle(.secondary)
                        Button { finder.locate() } label: { Label(t("locate"),systemImage:"location.fill").frame(maxWidth:.infinity,minHeight:44) }.buttonStyle(.borderedProminent).tint(teal)
                        Text(t("privacy")).font(.footnote).foregroundStyle(.secondary)
                        Picker(t("city"),selection:$city) { ForEach(PharmacySearch.cities.indices,id:\.self) { Text(PharmacySearch.cities[$0].0).tag($0) } }.pickerStyle(.menu)
                        Button(t("search")) { let selected = PharmacySearch.cities[city];finder.search(selected.1,name:selected.0) }.buttonStyle(.bordered).frame(minHeight:44)
                    }.padding(20).background(.thinMaterial,in:RoundedRectangle(cornerRadius:24))
                    HStack { Text(t("results")).font(.title2.bold()).accessibilityAddTraits(.isHeader); Spacer(); if finder.busy { Button(t("cancel")) { finder.cancel() }.frame(minHeight:44) } }
                    if finder.busy { ProgressView(t(finder.status)) } else { Text(statusText).foregroundStyle(.secondary).accessibilityLabel(statusText) }
                    if let result = finder.result, !result.pharmacies.isEmpty {
                        ForEach(Array(result.pharmacies.prefix(20))) { pharmacy in
                            VStack(alignment:.leading,spacing:8) {
                                if pharmacy.id == result.pharmacies.first?.id { Text(t("nearest")).font(.caption.bold()).foregroundStyle(teal) }
                                Text(pharmacy.name.isEmpty ? t("unnamed") : pharmacy.name).font(.headline)
                                Text(formattedDistance(pharmacy.distance)).font(.subheadline.bold())
                                if !pharmacy.address.isEmpty { Text(pharmacy.address).font(.subheadline).foregroundStyle(.secondary) }
                                Button { let item = MKMapItem(placemark:MKPlacemark(coordinate:CLLocationCoordinate2D(latitude:pharmacy.point.lat,longitude:pharmacy.point.lon))); item.name = pharmacy.name; item.openInMaps(launchOptions:nil) } label: { Label(t("map"),systemImage:"map").frame(minHeight:44) }.accessibilityLabel(t("map") + ": " + (pharmacy.name.isEmpty ? t("unnamed") : pharmacy.name))
                            }.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(Color(uiColor:.secondarySystemGroupedBackground),in:RoundedRectangle(cornerRadius:16))
                        }
                    }
                    Text(t("disclaimer")).font(.footnote).foregroundStyle(.secondary)
                    Link("© OpenStreetMap contributors",destination:URL(string:"https://www.openstreetmap.org/copyright")!).font(.footnote)
                }.padding()
            }.background(Color(uiColor:.systemGroupedBackground)).navigationTitle("PharmaNear").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement:.navigationBarTrailing) { Picker(t("language"),selection:$language) { Text("English").tag("en");Text("Suomi").tag("fi");Text("Svenska").tag("sv") }.pickerStyle(.menu).accessibilityLabel(t("language")) } }
        }.environment(\.locale,Locale(identifier:language))
    }
    private var statusText: String { guard finder.status == "found",let result = finder.result else { return t(finder.status) };return "\(t("found")): \(result.pharmacies.count) · \(finder.origin == "device" ? t("device") : finder.origin). \(result.covered ? "" : t("limited"))" }
    private func formattedDistance(_ meters:Double) -> String { let value = meters < 1000 ? Measurement(value:meters,unit:UnitLength.meters) : Measurement(value:meters/1000,unit:UnitLength.kilometers);let formatter = MeasurementFormatter();formatter.locale = Locale(identifier:language);formatter.unitOptions = .providedUnit;formatter.numberFormatter.maximumFractionDigits = meters < 1000 ? 0 : 1;return formatter.string(from:value) }
}
private let words: [String:[String:String]] = [
"en":["heading":"Find a pharmacy near you.","intro":"Find the closest mapped pharmacies by straight-line distance. No account needed.","locate":"Use my location","privacy":"Only a location rounded to two decimal places is sent to the Overpass service. Distances are calculated on your device.","city":"City centre","search":"Search","results":"Nearby pharmacies","cancel":"Cancel","idle":"Choose your location to start.","locating":"Getting your location…","loading":"Searching for pharmacies…","denied":"Location is unavailable or denied. Choose a city centre instead.","error":"Search is temporarily unavailable. Try again.","empty":"No mapped pharmacies found within the searched area.","found":"Mapped pharmacies found","device":"your location","limited":"Search coverage is limited.","nearest":"Closest mapped result","unnamed":"Unnamed pharmacy","map":"View on map","disclaimer":"Distances are not walking routes. Check opening hours before travelling. Map data can be incomplete.","language":"Language","cancelled":"Search cancelled."],
"fi":["heading":"Löydä apteekki läheltäsi.","intro":"Löydä lähimmät kartalla olevat apteekit linnuntie-etäisyyden mukaan. Et tarvitse tiliä.","locate":"Käytä sijaintiani","privacy":"Overpass-palveluun lähetetään vain kahden desimaalin tarkkuuteen pyöristetty sijainti. Etäisyydet lasketaan laitteellasi.","city":"Kaupungin keskusta","search":"Hae","results":"Lähellä olevat apteekit","cancel":"Peruuta","idle":"Valitse sijainti aloittaaksesi.","locating":"Haetaan sijaintia…","loading":"Haetaan apteekkeja…","denied":"Sijaintia ei saatu. Valitse kaupungin keskusta.","error":"Haku ei ole juuri nyt käytettävissä. Yritä uudelleen.","empty":"Hakualueelta ei löytynyt kartalla olevia apteekkeja.","found":"Kartalta löytyneet apteekit","device":"oma sijainti","limited":"Haun kattavuus on rajallinen.","nearest":"Lähin karttatulos","unnamed":"Nimetön apteekki","map":"Näytä kartalla","disclaimer":"Etäisyydet eivät ole kävelyreittejä. Tarkista aukioloajat ennen lähtöä. Karttatiedot voivat olla puutteellisia.","language":"Kieli","cancelled":"Haku peruttu."],
"sv":["heading":"Hitta ett apotek nära dig.","intro":"Hitta närmaste kartlagda apotek enligt fågelvägsavstånd. Inget konto behövs.","locate":"Använd min plats","privacy":"Endast en position avrundad till två decimaler skickas till Overpass-tjänsten. Avstånd beräknas på din enhet.","city":"Stadscentrum","search":"Sök","results":"Apotek i närheten","cancel":"Avbryt","idle":"Välj en plats för att börja.","locating":"Hämtar din plats…","loading":"Söker apotek…","denied":"Platsen är otillgänglig. Välj ett stadscentrum.","error":"Sökningen är tillfälligt otillgänglig. Försök igen.","empty":"Inga kartlagda apotek hittades i sökområdet.","found":"Kartlagda apotek hittades","device":"din plats","limited":"Sökningens täckning är begränsad.","nearest":"Närmaste kartresultat","unnamed":"Namnlöst apotek","map":"Visa på karta","disclaimer":"Avstånden är inte promenadrutter. Kontrollera öppettiderna innan du åker. Kartdata kan vara ofullständiga.","language":"Språk","cancelled":"Sökningen avbröts."]]
