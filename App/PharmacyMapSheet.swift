import SwiftUI
import MapKit

struct PharmacyMapSheet: View {
    let pharmacy: Pharmacy
    let title: String
    let close: String
    let disclosure: String
    let unnamed: String
    @Environment(\.dismiss) private var dismiss
    @State private var region: MKCoordinateRegion
    init(pharmacy:Pharmacy,title:String,close:String,disclosure:String,unnamed:String) {
        self.pharmacy=pharmacy;self.title=title;self.close=close;self.disclosure=disclosure;self.unnamed=unnamed
        _region=State(initialValue:MKCoordinateRegion(center:CLLocationCoordinate2D(latitude:pharmacy.point.lat,longitude:pharmacy.point.lon),span:MKCoordinateSpan(latitudeDelta:0.018,longitudeDelta:0.025)))
    }
    var body: some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:12) {
                Text(pharmacy.name.isEmpty ? unnamed : pharmacy.name).font(.headline)
                Text(disclosure).font(.footnote).foregroundStyle(.secondary)
                Map(coordinateRegion:$region,showsUserLocation:false,annotationItems:[pharmacy]) { p in
                    MapMarker(coordinate:CLLocationCoordinate2D(latitude:p.point.lat,longitude:p.point.lon),tint:.green)
                }
                .accessibilityLabel(title+" "+(pharmacy.name.isEmpty ? unnamed : pharmacy.name))
                .frame(maxWidth:.infinity,maxHeight:.infinity)
                if !pharmacy.address.isEmpty { Text(pharmacy.address).font(.subheadline) }
            }.padding().navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button(close) { dismiss() } } }
        }
    }
}
