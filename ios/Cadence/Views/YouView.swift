// You: Pip and your level, the days you closed, promises, settings and credits. Life holds the areas still coming.
import AuthenticationServices
import CoreImage.CIFilterBuiltins
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
                                Text("Pip · \(store.pipMood().label)").font(.geist(17, .bold))
                                Text(store.pipLine()).font(.geist(13)).foregroundStyle(Color.soft).lineLimit(2)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Card {
                    Eyebrow(text: "Last 4 weeks", icon: "square.grid.3x3.fill")
                    DaysGrid()
                }
                NavigationLink { YouGrowthView() } label: {
                    Card(tint: .mind) {
                        HStack { Eyebrow(text: "Growth", icon: "chart.line.uptrend.xyaxis", color: .mind); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                        Text("Journal, mood, goals, experiments, weekly review, Cadence age, badges · this week: \(store.challenge().text.lowercased())").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .accessibilityIdentifier("you.growth")
                .buttonStyle(.plain)
                VStack(spacing: 0) {
                    link("Promises", "bell", PromisesView())
                    link("Learning", "graduationcap", LearningView())
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
                Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.geist(10)).foregroundStyle(Color.faint)
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

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @Environment(\.webAuthenticationSession) private var webAuth
    @State private var googleMessage: String?

    private func minuteBinding(_ key: WritableKeyPath<Profile, Int>) -> Binding<Date> {
        Binding(get: { Day.at(store.profile[keyPath: key], on: Day.today) }, set: { d in store.update { $0[keyPath: key] = Day.minuteOfDay(d) } })
    }

    var body: some View {
        Form {
            Section {
                NavigationLink { SmartSetup() } label: { Label("Smart setup: targets from your body and goal", systemImage: "wand.and.stars") }
                HStack { Text("Goal"); Spacer(); GoalMenu() }
            }
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
                Picker("Sleep and heart data", selection: Binding(get: { store.profile.healthSource }, set: { v in store.update { $0.healthSource = v }; Task { await store.refreshHealth(force: true) } })) {
                    Text("Fitbit").tag("fitbit")
                    Text("Apple Health only").tag("apple")
                }
                if let p = store.appleHealthProblem { Text(p).font(.footnote).foregroundStyle(Color.warn) }
                Button("Read Apple Health now") { Task { await store.refreshAppleHealth(everything: !store.profile.usesBand) } }
            } header: { Text("Health data") } footer: { Text(store.profile.usesBand ? "Sleep, HRV and steps come from the Air; weight and water also come from Apple Health. Weights you type always win." : "Everything comes from Apple Health: sleep, HRV, resting heart rate, steps, weight and water. An Apple Watch gives the best data.") }
            if store.profile.usesBand {
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
            }
            PeopleSection()
            Section {
                ForEach([("fuel", "Fuel and water"), ("training", "Training"), ("care", "Care and medicines"), ("money", "Money"), ("wardrobe", "Wardrobe and laundry"), ("kitchen", "Meal prep and shopping"), ("home", "Home and documents"), ("people", "People"), ("travel", "Travel"), ("learning", "Learning")], id: \.0) { key, name in
                    Toggle(name, isOn: Binding(get: { store.profile.on(key) }, set: { on in store.update { p in p.areasOff.removeAll { $0 == key }; if !on { p.areasOff.append(key) } } }))
                }
            } header: { Text("Areas") } footer: { Text("Start small and switch areas on when you want them. The score only counts what's on.") }
            Section {
                LabeledContent("Widgets", value: store.widgetsAvailable ? "working" : "not available with this signing")
            } footer: { Text(store.widgetsAvailable ? "Long-press the home screen and add Cadence." : "The widgets need an App Group, which this install didn't get.") }
            Section("Your data") {
                ShareLink(item: store.exportJSON(), preview: SharePreview("Cadence export.json")) { Label("Export everything (JSON)", systemImage: "square.and.arrow.up") }
            }
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
                Text("Cadence").font(.serif(38))
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

/// Owner only: the people who use this server, and a setup QR for someone new. Their data is separate from yours.
struct PeopleSection: View {
    @EnvironmentObject var store: Store
    struct Person: Decodable, Identifiable { var id: String; var name: String }
    struct Added: Decodable { var name: String; var setup: String }
    @State private var people: [Person]?
    @State private var name = ""
    @State private var added: Added?
    @State private var error: String?

    var body: some View {
        Group {
            if let people {
                Section {
                    ForEach(people) { p in Text(p.name) }
                    HStack {
                        TextField("Friend's name", text: $name)
                        Button("Invite") { Task { await add() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let added {
                        VStack(alignment: .center, spacing: 8) {
                            if let qr = Self.qr(added.setup) { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 200, height: 200) }
                            Text("\(added.name) scans this with the iPhone camera after installing Cadence. It's shown once.").font(.footnote).multilineTextAlignment(.center)
                            ShareLink(item: added.setup) { Label("Send the setup link", systemImage: "square.and.arrow.up") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.warn) }
                } header: { Text("People") } footer: { Text("Each person gets their own token and their own data on your server; nobody sees anyone else's.") }
            }
        }
        .task { await load() }
    }

    private func load() async {
        guard let req = store.request("people.php"), let (data, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200 else { return } // not the owner: hidden
        struct R: Decodable { var people: [Person] }
        people = (try? JSONDecoder().decode(R.self, from: data))?.people
    }

    private func add() async {
        guard let body = try? JSONEncoder().encode(["name": name]), let req = store.request("people.php", body: body),
              let (data, r) = try? await URLSession.shared.data(for: req), (r as? HTTPURLResponse)?.statusCode == 200,
              let a = try? JSONDecoder().decode(Added.self, from: data) else { error = "Couldn't add them: check the connection."; return }
        added = a
        name = ""
        error = nil
        await load()
    }

    static func qr(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
