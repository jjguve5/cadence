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
                HStack { Eyebrow(text: "Regular trips", icon: "tram.fill"); Spacer(); Button { editingCommute = RegularTrip(title: "") } label: { Image(systemName: "plus") }.tint(.water) }
                let commutes = store.all(RegularTrip.self)
                if commutes.isEmpty { Text("Trips you make every week, with door-to-door time: they block the plan and get a leave-by alert.").font(.geist(13)).foregroundStyle(Color.soft) }
                ForEach(commutes) { c in
                    Button { editingCommute = c } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).font(.geist(14.5, .semibold))
                                Text("Leave \(clock(c.leave)) · arrive \(clock(c.arrive)) · \(c.travel) min").font(.geist(12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            Text(c.weekdays.sorted { ($0 + 5) % 7 < ($1 + 5) % 7 }.map { ["S", "M", "T", "W", "T", "F", "S"][$0 - 1] }.joined()).font(.mono(12)).foregroundStyle(Color.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Card {
                HStack { Eyebrow(text: "Trips", icon: "airplane"); Spacer(); Button { editingTrip = Trip(destination: "", start: Day.add(14, to: Day.today), end: Day.add(18, to: Day.today)) } label: { Image(systemName: "plus") }.tint(.water) }
                ForEach(store.all(Trip.self).sorted { $0.start > $1.start }) { t in
                    NavigationLink { TripDetail(tripId: t.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t.destination).font(.geist(14.5, .semibold))
                                Text("\(Day.date(t.start).formatted(.dateTime.day().month())) – \(Day.date(t.end).formatted(.dateTime.day().month())) · \(t.nights) nights" + (t.hoursAhead != 0 ? " · \(t.hoursAhead > 0 ? "+" : "")\(t.hoursAhead) h" : "")).font(.geist(12)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            if t.end < Day.today { Chip(text: "done", color: .faint) }
                        }
                    }
                    .buttonStyle(.plain)
                }
                let year = String(Day.today.prefix(4))
                let away = store.all(Trip.self).filter { $0.start.hasPrefix(year) }.map(\.nights).reduce(0, +)
                Text("\(away) nights away in \(year)").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
        }
        .navigationTitle("Travel")
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
                TextField("Name (e.g. Uni)", text: $trip.title)
                TextField("Destination address", text: $trip.destination)
                HStack {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { wd in
                        let on = trip.weekdays.contains(wd)
                        Text(["S", "M", "T", "W", "T", "F", "S"][wd - 1]).frame(width: 32, height: 32).background(Circle().fill(on ? Color.water : .white.opacity(0.08)))
                            .onTapGesture { if on { trip.weekdays.removeAll { $0 == wd } } else { trip.weekdays.append(wd) } }
                    }
                }
                DatePicker("Be there by", selection: $arrive, displayedComponents: .hourAndMinute)
                Stepper("Door to door \(trip.travel) min", value: $trip.travel, in: 5...240, step: 5)
                Stepper("Buffer \(trip.buffer) min", value: $trip.buffer, in: 0...60, step: 5)
                Toggle("Public transport", isOn: $transit)
                Button(checking ? "Checking Apple Maps…" : "Use live travel time from here") {
                    checking = true
                    Task {
                        if let m = await TravelTime.shared.minutes(to: trip.destination, transit: transit) { trip.travel = m }
                        checking = false
                    }
                }
                .disabled(trip.destination.isEmpty || checking)
                if store.record(RegularTrip.self, trip.id) != nil { Button("Delete", role: .destructive) { store.remove(trip); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(trip.title.isEmpty ? "Regular trip" : trip.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { trip.arrive = Day.minuteOfDay(arrive); store.save(trip); Reminders.shared.reschedule(); dismiss() }.disabled(trip.title.isEmpty) }
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
                TextField("Destination", text: $trip.destination)
                DatePicker("Leave", selection: Binding(get: { Day.date(trip.start) }, set: { trip.start = Day.key($0) }), displayedComponents: .date)
                DatePicker("Back", selection: Binding(get: { Day.date(trip.end) }, set: { trip.end = Day.key($0) }), displayedComponents: .date)
                Stepper("Time difference \(trip.hoursAhead > 0 ? "+" : "")\(trip.hoursAhead) h", value: $trip.hoursAhead, in: -12...14)
                TextField("Budget € (optional)", value: $trip.budget, format: .number).keyboardType(.decimalPad)
                TextField("Notes", text: $trip.notes, axis: .vertical)
                if store.record(Trip.self, trip.id) != nil { Button("Delete", role: .destructive) { store.remove(trip); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(trip.destination.isEmpty ? "New trip" : trip.destination)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(trip); dismiss() }.disabled(trip.destination.isEmpty) }
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
                        Eyebrow(text: "Jet lag plan · \(t.hoursAhead > 0 ? "east" : "west"), \(abs(t.hoursAhead)) h", icon: "moon.zzz.fill", color: .sleep)
                        ForEach(plan, id: \.day) { step in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack { Text(Day.date(step.day).formatted(.dateTime.weekday(.wide).day())).font(.geist(13.5, .semibold)); Spacer(); Text("bed \(clock(step.bedtime))").font(.mono(13)) }
                                Text(step.note).font(.geist(12)).foregroundStyle(Color.soft)
                            }
                        }
                        Text("After you land, Cadence tracks how your sleep adapts.").font(.geist(11.5)).foregroundStyle(Color.faint)
                    }
                }
                Card {
                    Eyebrow(text: "Packing list", icon: "suitcase.fill")
                    ForEach(store.packingList(t), id: \.self) { item in
                        let packed = t.packed.contains(item)
                        Button {
                            var x = t
                            if packed { x.packed.removeAll { $0 == item } } else { x.packed.append(item) }
                            store.save(x)
                        } label: {
                            HStack { Image(systemName: packed ? "checkmark.circle.fill" : "circle").foregroundStyle(packed ? Color.good : Color.soft); Text(item).strikethrough(packed).font(.geist(14)); Spacer() }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let budget = t.budget {
                    let s = store.tripSpending(t)
                    Card(tint: Color(hex: 0xFFD166)) {
                        Eyebrow(text: "Budget", icon: "eurosign.circle", color: Color(hex: 0xFFD166))
                        HStack { Text("\(euro(s.spent)) of \(euro(budget))").font(.geist(15, .semibold)); Spacer(); if let d = s.perDay { Text("\(euro(d)) a day").font(.geist(12.5)).foregroundStyle(Color.soft) } }
                        Bar(progress: s.spent / max(1, budget), area: s.spent > budget ? .train : .fuel)
                    }
                }
                if !store.groomingBefore(t).isEmpty {
                    Card(tint: .fuel) {
                        Eyebrow(text: "Before you go", color: .fuel)
                        Text(store.groomingBefore(t).map(\.title).joined(separator: ", ")).font(.geist(14))
                    }
                }
            }
            .toolbar { Button("Edit") { editing = t } }
            .sheet(item: $editing) { TripEditor(trip: $0) }
        }
    }
}
