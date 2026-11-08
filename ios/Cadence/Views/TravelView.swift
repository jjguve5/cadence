// Travel: regular trips (blocked in the plan, with a leave-by alert from live Apple Maps travel time) and one-off
// trips with the jet lag plan, packing list and a budget.
import CoreLocation
import MapKit
import SwiftUI

struct TravelView: View {
    @EnvironmentObject var store: Store
    @State private var editingCommute: RegularTrip?
    @State private var editingTrip: Trip?

    var body: some View {
        Screen(glow: Color(hex: 0x6CC4FF)) {
            Card {
                HStack { Eyebrow(text: "Deslocações regulares", icon: "tram.fill"); Spacer(); Button { editingCommute = RegularTrip(title: "") } label: { Image(systemName: "plus") }.tint(.water) }
                let commutes = store.all(RegularTrip.self)
                if commutes.isEmpty { Text("Deslocações que fazes todas as semanas, com o tempo porta a porta: ocupam o plano e têm um aviso da hora de saída.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(commutes) { c in
                    Button { editingCommute = c } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.geist(14.5, .semibold))
                                Text("Saída \(clock(c.leave)) · chegada \(clock(c.arrive)) · \(c.travel) min").font(.geist(12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            Text(c.weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { ["D", "S", "T", "Q", "Q", "S", "S"][$0 - 1] }.joined()).font(.mono(12)).foregroundStyle(Color.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Card {
                HStack { Eyebrow(text: "Viagens", icon: "airplane"); Spacer(); Button { editingTrip = Trip(destination: "", start: Day.add(14, to: Day.today), end: Day.add(18, to: Day.today)) } label: { Image(systemName: "plus") }.tint(.water) }
                ForEach(store.all(Trip.self).sorted { $0.start > $1.start }) { t in
                    NavigationLink { TripDetail(tripId: t.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.destination).font(.geist(14.5, .semibold))
                                Text("\(Day.date(t.start).formatted(.dateTime.day().month())) – \(Day.date(t.end).formatted(.dateTime.day().month())) · \(t.nights) \(t.nights == 1 ? "noite" : "noites")" + (t.hoursAhead != 0 ? " · \(t.hoursAhead > 0 ? "+" : "")\(t.hoursAhead) h" : "")).font(.geist(12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            if t.end < Day.today { Chip(text: "feita", color: .faint) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                let year = String(Day.today.prefix(4))
                let away = store.all(Trip.self).filter { $0.start.hasPrefix(year) }.map(\.nights).reduce(0, +)
                Text("\(away) \(away == 1 ? "noite" : "noites") fora em \(year)").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("Viagens")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingCommute) { CommuteEditor(trip: $0) }
        .sheet(item: $editingTrip) { TripEditor(trip: $0) }
    }
}

@MainActor
final class TravelTime: NSObject, CLLocationManagerDelegate {
    static let shared = TravelTime()
    private let manager = CLLocationManager()

    /// Door-to-door minutes by car or transit from here, from Apple Maps
    func minutes(to address: String, transit: Bool) async -> Int? {
        manager.requestWhenInUseAuthorization()
        guard let placemark = try? await CLGeocoder().geocodeAddressString(address).first, let loc = placemark.location else { return nil }
        let request = MKDirections.Request()
        request.source = MKMapItem.forCurrentLocation()
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: loc.coordinate))
        request.transportType = transit ? .transit : .automobile
        guard let eta = try? await MKDirections(request: request).calculateETA() else { return nil }
        return Int((eta.expectedTravelTime / 60).rounded(.up))
    }
}

struct CommuteEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var trip: RegularTrip
    @State private var arrive = Date()
    @State private var checking = false
    @State private var transit = true

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nome (ex.: Faculdade)", text: $trip.title)
                TextField("Morada de destino", text: $trip.destination)
                HStack {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                        let on = trip.weekdays.contains(wd)
                        Text(["D", "S", "T", "Q", "Q", "S", "S"][wd - 1]).frame(width: 32, height: 32).background(Circle().fill(on ? Color.water : .white.opacity(0.08)))
                            .onTapGesture { if on { trip.weekdays.removeAll { $0 == wd } } else { trip.weekdays.append(wd) } }
                    }
                }
                DatePicker("Chegar até às", selection: $arrive, displayedComponents: .hourAndMinute)
                Stepper("Porta a porta \(trip.travel) min", value: $trip.travel, in: 5...240, step: 5)
                Stepper("Margem \(trip.buffer) min", value: $trip.buffer, in: 0...60, step: 5)
                Toggle("Transportes públicos", isOn: $transit)
                Button(checking ? "A consultar o Apple Maps…" : "Usar o tempo de viagem real a partir daqui") {
                    checking = true
                    Task {
                        if let m = await TravelTime.shared.minutes(to: trip.destination, transit: transit) { trip.travel = m }
                        checking = false
                    }
                }
                .disabled(trip.destination.isEmpty || checking)
                if store.record(RegularTrip.self, trip.id) != nil { Button("Apagar", role: .destructive) { store.remove(trip); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(trip.title.isEmpty ? "Deslocação regular" : trip.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { trip.arrive = Day.minuteOfDay(arrive); store.save(trip); Reminders.shared.reschedule(); dismiss() }.disabled(trip.title.isEmpty) }
            }
            .onAppear { arrive = Day.at(trip.arrive, on: Day.today) }
        }
    }
}

struct TripEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var trip: Trip
    var body: some View {
        NavigationStack {
            Form {
                TextField("Destino", text: $trip.destination)
                DatePicker("Partida", selection: Binding(get: { Day.date(trip.start) }, set: { trip.start = Day.key($0) }), displayedComponents: .date)
                DatePicker("Regresso", selection: Binding(get: { Day.date(trip.end) }, set: { trip.end = Day.key($0) }), displayedComponents: .date)
                Stepper("Diferença horária \(trip.hoursAhead > 0 ? "+" : "")\(trip.hoursAhead) h", value: $trip.hoursAhead, in: -12...14)
                TextField("Orçamento € (opcional)", value: $trip.budget, format: .number).keyboardType(.decimalPad)
                TextField("Notas", text: $trip.notes, axis: .vertical)
                if store.record(Trip.self, trip.id) != nil { Button("Apagar", role: .destructive) { store.remove(trip); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(trip.destination.isEmpty ? "Nova viagem" : trip.destination)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(trip); dismiss() }.disabled(trip.destination.isEmpty) }
            }
        }
    }
}

struct TripDetail: View {
    @EnvironmentObject var store: Store
    var tripId: String
    @State private var editing: Trip?

    var body: some View {
        if let t = store.record(Trip.self, tripId) {
            Screen(glow: .water) {
                Title(eyebrow: "\(Day.date(t.start).formatted(.dateTime.day().month(.wide))) – \(Day.date(t.end).formatted(.dateTime.day().month(.wide)))", title: t.destination)
                let plan = store.jetLagPlan(t)
                if !plan.isEmpty {
                    Card(tint: .sleep) {
                        Eyebrow(text: "Plano de jet lag · \(t.hoursAhead > 0 ? "leste" : "oeste"), \(abs(t.hoursAhead)) h", icon: "moon.zzz.fill", color: .sleep)
                        ForEach(plan, id: \.day) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(Day.date(step.day).formatted(.dateTime.weekday(.wide).day())).font(.geist(13.5, .semibold)); Spacer(); Text("deitar \(clock(step.bedtime))").font(.mono(13)) }
                                Text(step.note).font(.geist(12)).foregroundStyle(Color.soft)
                            }
                        }
                        Text("Depois de aterrares, o Cadence acompanha como o teu sono se adapta.").font(.geist(11.5)).foregroundStyle(Color.faint)
                    }
                }
                Card {
                    Eyebrow(text: "Lista para a mala", icon: "suitcase.fill")
                    ForEach(store.packingList(t), id: \.self) { item in
                        let packed = t.packed.contains(item)
                        Button {
                            var x = t
                            if packed { x.packed.removeAll { $0 == item } } else { x.packed.append(item) }
                            store.save(x)
                        } label: {
                            HStack { Image(systemName: packed ? "checkmark.circle.fill" : "circle").foregroundStyle(packed ? Color.good : Color.soft); Text(packingLabel(item)).strikethrough(packed).font(.geist(14)); Spacer() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let budget = t.budget {
                    let s = store.tripSpending(t)
                    Card(tint: Color(hex: 0xFFD166)) {
                        Eyebrow(text: "Orçamento", icon: "eurosign.circle", color: Color(hex: 0xFFD166))
                        HStack { Text("\(euro(s.spent)) de \(euro(budget))").font(.geist(15, .semibold)); Spacer(); if let d = s.perDay { Text("\(euro(d)) por dia").font(.geist(12.5)).foregroundStyle(Color.soft) } }
                        Bar(progress: s.spent / max(1, budget), area: s.spent > budget ? .train : .fuel)
                    }
                }
                if !store.groomingBefore(t).isEmpty {
                    Card(tint: .fuel) {
                        Eyebrow(text: "Antes de ires", color: .fuel)
                        Text(store.groomingBefore(t).map(\.title).joined(separator: ", ")).font(.geist(14))
                    }
                }
            }
            .toolbar { Button("Editar") { editing = t } }
            .sheet(item: $editing) { TripEditor(trip: $0) }
        }
    }
}
