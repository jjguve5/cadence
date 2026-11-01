// You: Pip and your level, the days you closed, promises, settings and credits. Life holds the areas still coming.
import AuthenticationServices
import SwiftUI

struct YouView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Screen(glow: .mind) {
                Title(eyebrow: "Level \(store.level.level) · \(store.totalPoints.formatted()) points", title: "You")
                    .padding(.top, 8)
                NavigationLink { PipPage() } label: {
                    Card(tint: .fuel) {
                        HStack(spacing: 14) {
                            PipHead(mood: store.pipMood(), size: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Pip · \(store.pipMood().label)").font(.system(size: 17, weight: .bold))
                                Text(store.pipLine()).font(.system(size: 13)).foregroundStyle(Color.soft).lineLimit(2)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Card {
                    Eyebrow(text: "Last 4 weeks", icon: "square.grid.3x3.fill")
                    DaysGrid()
                }
                VStack(spacing: 0) {
                    link("Promises", "bell", PromisesView())
                    link("Settings", "gearshape", SettingsView())
                    link("Credits", "heart", CreditsView())
                }
                .background(RoundedRectangle(cornerRadius: 22).fill(.white.opacity(0.055)))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func link<D: View>(_ title: String, _ icon: String, _ dest: D) -> some View {
        NavigationLink { dest } label: {
            HStack { Image(systemName: icon).frame(width: 24).foregroundStyle(Color.mint); Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                .padding(14).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A month of days coloured by score: the start of "year in pixels"
struct DaysGrid: View {
    @EnvironmentObject var store: Store
    var body: some View {
        let start = Day.add(-27, to: Day.weekStart(Day.today) == Day.today ? Day.today : Day.weekStart(Day.today))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
            ForEach(["M", "T", "W", "T", "F", "S", "S"].indices, id: \.self) { i in
                Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.system(size: 10)).foregroundStyle(Color.faint)
            }
            ForEach(0..<35, id: \.self) { i in
                let d = Day.add(i, to: start)
                let future = d > Day.today
                let s = store.days[d]?.score ?? (d == Day.today ? store.score() : nil)
                RoundedRectangle(cornerRadius: 6)
                    .fill(future ? Color.clear : s.map { Color.mint.opacity(0.15 + 0.85 * Double($0) / 100) } ?? Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(d == Day.today ? Color.ink : .clear, lineWidth: 1))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
    }
}

struct LifeView: View {
    var body: some View {
        NavigationStack {
            Screen(glow: Color(hex: 0x7FB8FF)) {
                Title(eyebrow: "Money, wardrobe, home, people", title: "Life")
                    .padding(.top, 8)
                ForEach([("Money", "creditcard.fill", "Bank sync, Apple Pay entries, safe to spend, savings goals"),
                         ("Wardrobe and laundry", "tshirt.fill", "Outfit of the day from the weather, laundry loads"),
                         ("Home and documents", "house.fill", "Freshness bars, plants, expiry dates"),
                         ("People", "person.2.fill", "Birthdays, gift ideas, keeping in touch")], id: \.0) { name, icon, detail in
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Color(hex: 0x7FB8FF)).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name).font(.system(size: 15, weight: .semibold))
                                Text(detail).font(.system(size: 12.5)).foregroundStyle(Color.soft)
                            }
                            Spacer()
                            Chip(text: "soon", color: .soft)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var googleMessage: String?

    private func minuteBinding(_ key: WritableKeyPath<Profile, Int>) -> Binding<Date> {
        Binding(get: { Day.at(store.profile[keyPath: key], on: Day.today) }, set: { d in store.update { $0[keyPath: key] = Day.minuteOfDay(d) } })
    }

    var body: some View {
        Form {
            Section("You") {
                TextField("Name", text: Binding(get: { store.profile.name }, set: { v in store.update { $0.name = v } }))
                DatePicker("Wake time", selection: minuteBinding(\.wakeMinute), displayedComponents: .hourAndMinute)
                Stepper("Sleep need \(duration(store.profile.sleepNeed))", value: Binding(get: { store.profile.sleepNeed }, set: { v in store.update { $0.sleepNeed = v } }), in: 360...600, step: 15)
                Stepper("Wind-down \(store.profile.windDownLead) min before bed", value: Binding(get: { store.profile.windDownLead }, set: { v in store.update { $0.windDownLead = v } }), in: 15...90, step: 15)
                Stepper("Step goal \(store.profile.stepGoal.formatted())", value: Binding(get: { store.profile.stepGoal }, set: { v in store.update { $0.stepGoal = v } }), in: 2000...20000, step: 500)
            }
            Section {
                DatePicker("Quiet from", selection: minuteBinding(\.quietStart), displayedComponents: .hourAndMinute)
                DatePicker("Quiet until", selection: minuteBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                Stepper("Up to \(store.profile.notificationBudget) a day", value: Binding(get: { store.profile.notificationBudget }, set: { v in store.update { $0.notificationBudget = v } }), in: 3...30)
            } header: { Text("Notifications") } footer: { Text("Must-dos, medicines and leave-by alerts always get through; everything else is ranked and waits.") }
            Section {
                Button("Connect Google Health") { Task { await connectGoogle() } }
                if let googleMessage { Text(googleMessage).font(.footnote).foregroundStyle(Color.soft) }
                if let d = store.device {
                    LabeledContent("Tracker", value: d.name ?? "–")
                    LabeledContent("Battery", value: d.battery.map { "\($0)%" } ?? "–")
                }
                LabeledContent("Days of data", value: "\(store.health.count)")
                if !store.healthErrors.isEmpty {
                    ForEach(store.healthErrors.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("\(k): \(v)").font(.caption2).foregroundStyle(Color.warn) }
                }
            } header: { Text("Fitbit Air") } footer: { Text("While the Google app is in testing, its sign-in lasts 7 days: connect again when Today asks.") }
            Section("Server") {
                LabeledContent("Address", value: store.connection.server)
                Button("Sync now") { Task { await store.refreshAll(); await store.refreshHealth(force: true) } }
                if let e = store.syncError { Text(e).font(.footnote).foregroundStyle(Color.warn) }
                Button("Forget this server", role: .destructive) { store.connection = Connection() }
            }
        }
        .cadenceList()
        .navigationTitle("Settings")
    }

    private func connectGoogle() async {
        guard let url = store.googleURL() else { return }
        do {
            let back = try await webAuth.authenticate(using: url, callbackURLScheme: "cadence")
            if back.absoluteString.contains("ok=1") { googleMessage = "Connected."; store.googleConnected() } else { googleMessage = "Not connected. Try again." }
        } catch {
            googleMessage = "Cancelled."
        }
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("Pip") { Text("An original character for Cadence, animated in After Effects and played with Lottie.") }
            Section("Exercise data") { Text("Exercise data by RepDB (repdb.co)") }
            Section("Body map") { Text("Based on GymMane by InlitX (GPL-3.0)") }
            Section("Science") {
                Text("Readiness against your own 14-day baseline; sleep regularity from Windred et al., Sleep 2024; illness signs from Natarajan et al., npj Digital Medicine 2020.")
            }
        }
        .cadenceList()
        .navigationTitle("Credits")
    }
}

/// First run: scan the setup QR code (it opens cadence://setup) or paste the server and token
struct SetupView: View {
    @EnvironmentObject var store: Store
    @State private var server = "https://"
    @State private var token = ""

    var body: some View {
        Screen(glow: .mint) {
            VStack(spacing: 10) {
                PipAnimation(mood: .happy).frame(width: 200, height: 200)
                Text("Cadence").font(.system(size: 38, weight: .bold, design: .serif))
                Text("Scan the setup QR code with the Camera app, or paste your server's address and token.").multilineTextAlignment(.center).foregroundStyle(Color.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            Card {
                TextField("Server address", text: $server).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Divider()
                SecureField("Token", text: $token)
            }
            PrimaryButton(title: "Connect") {
                store.connection = Connection(server: server.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "/")), token: token.trimmingCharacters(in: .whitespaces))
                Task { await store.refreshAll() }
            }
        }
    }
}
