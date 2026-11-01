// Money screens: safe to spend, the review inbox, ins and outs, wallets, goals, the 72-hour list, recap and setup.
import SwiftUI
import VisionKit

struct MoneyView: View {
    @EnvironmentObject var store: Store
    @State private var editingRecurring: Recurring?
    @State private var editingWallet: Wallet?
    @State private var editingGoal: SavingsGoal?
    @State private var addingTx: Transaction?
    @State private var wish = ""
    @State private var wishPrice = ""
    @State private var scanning = false

    var body: some View {
        Screen(glow: Color(hex: 0xFFD166)) {
            safeSection
            inboxSection
            actionsSection
            recurringSection
            walletsSection
            goalsSection
            wishesSection
            watchSection
            MoneyExtras()
            NavigationLink { RecapView() } label: { Text("Monthly recap · \(store.noSpendDays()) no-spend days this month").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color(hex: 0xFFD166)) }
            NavigationLink { MoneySetupView() } label: { Text("Bank sync and Apple Pay setup").font(.system(size: 13)).foregroundStyle(Color.soft) }
        }
        .navigationTitle("Money")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.pullBank() }
        .sheet(item: $editingRecurring) { RecurringEditor(item: $0) }
        .sheet(item: $editingWallet) { WalletEditor(wallet: $0) }
        .sheet(item: $editingGoal) { GoalEditor(goal: $0) }
        .sheet(item: $addingTx) { TransactionEditor(tx: $0) }
        .sheet(isPresented: $scanning) {
            QRScanner { text in
                scanning = false
                if let r = ReceiptQR(text) { addingTx = Transaction(date: r.date, amount: -r.total, merchant: "NIF \(r.nif)", source: "receipt", nif: r.nif, vat: r.vat) }
            }
            .ignoresSafeArea()
        }
    }

    private var safeSection: some View {
        Group {
            let m = store.moneyMonth()
            Card(tint: Color(hex: 0xFFD166)) {
                Eyebrow(text: "Safe to spend", icon: "eurosign.circle.fill", color: Color(hex: 0xFFD166))
                HStack(alignment: .firstTextBaseline) {
                    Text(euro(m.safePerDay)).font(.system(size: 34, weight: .bold))
                    Text("a day · \(m.daysLeft) days left").font(.system(size: 13)).foregroundStyle(Color.soft)
                }
                row("Income this month", euro(m.income))
                row("Fixed outs", "−" + euro(m.fixed))
                row("Into goals", "−" + euro(m.goals))
                row("Spent so far", "−" + euro(m.spent))
                row("On track to save", euro(m.projectedSaving), color: m.projectedSaving >= m.goals ? .good : .warn)
                if m.income == 0 { Text("Add your salary and fixed outs below to see this properly.").font(.system(size: 12)).foregroundStyle(Color.soft) }
            }
        }
    }

    private var inboxSection: some View {
        Group {
            let inbox = store.reviewInbox
            if !inbox.isEmpty {
                NavigationLink { ReviewInbox() } label: {
                    Card(tint: .warn) {
                        HStack { Eyebrow(text: "Review inbox", icon: "tray.full.fill", color: .warn); Spacer(); Chip(text: "\(inbox.count)", color: .warn) }
                        Text(inbox.prefix(3).map { "\($0.merchant) \(euro(-$0.amount, decimals: true))" }.joined(separator: " · ")).font(.system(size: 13)).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionsSection: some View {
        Group {
            HStack {
                SoftButton(title: "Add", icon: "plus") { addingTx = Transaction(amount: 0, merchant: "") }
                SoftButton(title: "Receipt QR", icon: "qrcode.viewfinder") { scanning = true }
                    .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                SoftButton(title: "Bank", icon: "building.columns") { Task { await store.pullBank() } }
            }
        }
    }

    private var recurringSection: some View {
        Group {
            Card {
                HStack { Eyebrow(text: "Monthly ins and outs", icon: "arrow.left.arrow.right"); Spacer(); Button { editingRecurring = Recurring(title: "", amount: -10) } label: { Image(systemName: "plus") }.tint(Color(hex: 0xFFD166)) }
                ForEach(store.all(Recurring.self).sorted { $0.amount > $1.amount }) { r in
                    Button { editingRecurring = r } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.system(size: 14, weight: .medium))
                                Text((r.everyWeeks > 0 ? "every \(r.everyWeeks) weeks" : r.everyMonths == 1 ? "monthly" : "every \(r.everyMonths) months") + " · next \(Day.date(r.occurrences(from: Day.today, to: Day.add(400, to: Day.today)).first ?? r.next).formatted(.dateTime.day().month()))").font(.system(size: 11.5)).foregroundStyle(Color.faint)
                            }
                            Spacer()
                            Text((r.amount > 0 ? "+" : "") + euro(r.amount, decimals: true)).font(.system(size: 13.5, weight: .semibold, design: .monospaced)).foregroundStyle(r.amount > 0 ? Color.good : Color.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(store.upcomingRenewals.filter { Day.between(Day.today, $0.1) <= $0.0.remindDays && $0.0.amount < 0 }, id: \.0.id) { r, d in
                    Text("\(r.title) renews \(Day.date(d).formatted(.dateTime.weekday(.wide)))" + (r.cancelBy.map { ": cancel by \(Day.date($0).formatted(.dateTime.day().month())) if you don't need it" } ?? "")).font(.system(size: 12)).foregroundStyle(Color.warn)
                }
            }
        }
    }

    private var walletsSection: some View {
        Group {
            Card(tint: .mint) {
                HStack { Eyebrow(text: "Benefit wallets · not your cash", icon: "creditcard.fill", color: .mint); Spacer(); Button { editingWallet = Wallet(name: "", balance: 0) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(Wallet.self)) { w in
                    Button { editingWallet = w } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) { Text(w.name).font(.system(size: 14, weight: .medium)); Text("for \(w.spendsOn.lowercased())" + (w.useBy.map { " · use by \(Day.date($0).formatted(.dateTime.day().month()))" } ?? "")).font(.system(size: 11.5)).foregroundStyle(Color.faint) }
                            Spacer()
                            Text(euro(w.balance, decimals: true)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                    }
                    .buttonStyle(.plain)
                }
                if store.all(Wallet.self).contains(where: { $0.balance > 0 }) { Text("Spend these first: groceries and meals from the meal card keep your own money for goals.").font(.system(size: 12)).foregroundStyle(Color.soft) }
            }
        }
    }

    private var goalsSection: some View {
        Group {
            Card {
                HStack { Eyebrow(text: "Saving for", icon: "target"); Spacer(); Button { editingGoal = SavingsGoal(title: "", price: 100) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(SavingsGoal.self)) { g in
                    Button { editingGoal = g } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("\(g.title) · \(euro(g.price))").font(.system(size: 14, weight: .medium)); Spacer(); Text("\(euro(g.saved))" + (g.by.map { " · \(Day.date($0).formatted(.dateTime.month(.abbreviated)))" } ?? "")).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.soft) }
                            Bar(progress: g.saved / max(1, g.price), area: .mint)
                            if let by = g.by, g.saved < g.price { Text("\(euro((g.price - g.saved) / Double(max(1, Day.between(Day.today, by) / 30)))) a month gets you there").font(.system(size: 11.5)).foregroundStyle(Color.faint) }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var wishesSection: some View {
        Group {
            Card {
                Eyebrow(text: "Worth it? · 72-hour cool-off", icon: "hourglass")
                HStack {
                    TextField("Something you want", text: $wish)
                    TextField("€", text: $wishPrice).keyboardType(.decimalPad).frame(width: 60)
                    Button("Add") { if let p = Double(wishPrice.replacingOccurrences(of: ",", with: ".")) { store.save(WishItem(title: wish, price: p)); wish = ""; wishPrice = "" } }.disabled(wish.isEmpty)
                }
                ForEach(store.all(WishItem.self).filter { $0.decision == nil }) { WishRow(item: $0) }
                let skipped = store.all(WishItem.self).filter { $0.decision == "skipped" }.map(\.price).reduce(0, +)
                if skipped > 0 { Text("Skipped after waiting: \(euro(skipped)) kept").font(.system(size: 12)).foregroundStyle(Color.good) }
            }
        }
    }

    private var watchSection: some View {
        Group {
            let watch = store.subscriptionWatch()
            if !watch.isEmpty {
                Card(tint: .warn) {
                    Eyebrow(text: "Subscription watch", icon: "eye.fill", color: .warn)
                    ForEach(watch, id: \.self) { Text($0).font(.system(size: 13)) }
                }
            }
        }
    }

    private func row(_ name: String, _ value: String, color: Color = .ink) -> some View {
        HStack { Text(name).font(.system(size: 13.5)).foregroundStyle(Color.soft); Spacer(); Text(value).font(.system(size: 13.5, weight: .semibold, design: .monospaced)).foregroundStyle(color) }
    }
}

struct WishRow: View {
    @EnvironmentObject var store: Store
    var item: WishItem
    var body: some View {
        HStack {
            Text("\(item.title) · \(euro(item.price))").font(.system(size: 13.5))
            Spacer()
            if item.ready {
                Button("Skip") { decide("skipped") }.tint(Color.good)
                Button("Buy") { decide("bought") }.tint(Color.soft)
            } else {
                Text("wait \(item.hoursLeft) h").font(.system(size: 12)).foregroundStyle(Color.faint)
            }
        }
    }
    private func decide(_ d: String) {
        var x = item
        x.decision = d
        store.save(x)
    }
}

struct ReviewInbox: View {
    @EnvironmentObject var store: Store
    var body: some View {
        List {
            ForEach(store.reviewInbox) { t in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        VStack(alignment: .leading) { Text(t.merchant); Text("\(Day.date(t.date).formatted(.dateTime.day().month())) · \(t.source)").font(.caption).foregroundStyle(Color.soft) }
                        Spacer()
                        Text(euro(t.amount, decimals: true)).monospaced()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            let guess = store.category(for: t)
                            ForEach([guess] + moneyCategories.filter { $0 != guess }, id: \.self) { c in
                                Chip(text: c, color: c == guess ? Color(hex: 0x2B1A05) : .ink, fill: c == guess ? Color(hex: 0xFFD166) : .white.opacity(0.08)).onTapGesture { store.categorize(t, c) }
                            }
                        }
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { store.remove(t) } }
            }
        }
        .cadenceList()
        .navigationTitle("Review")
    }
}

struct RecapView: View {
    @EnvironmentObject var store: Store
    @State private var month = String(Day.today.prefix(7))
    var body: some View {
        let r = store.recap(month: month)
        Screen(glow: Color(hex: 0xFFD166)) {
            Picker("Month", selection: $month) {
                ForEach(0..<6, id: \.self) { i in
                    let m = String(Day.key(Day.calendar.date(byAdding: .month, value: -i, to: Date()) ?? Date()).prefix(7))
                    Text(Day.date(m + "-01").formatted(.dateTime.month(.wide).year())).tag(m)
                }
            }
            .tint(Color(hex: 0xFFD166))
            Card {
                Eyebrow(text: "Spent")
                Text(euro(r.total)).font(.system(size: 30, weight: .bold))
                ForEach(r.top, id: \.0) { c, v in HStack { Text(c).font(.system(size: 14)); Spacer(); Text(euro(v)).font(.system(size: 14, design: .monospaced)) } }
            }
            Card {
                Eyebrow(text: "Against your 3-month average")
                ForEach(r.vsAverage, id: \.0) { c, d in HStack { Text(c).font(.system(size: 14)); Spacer(); Text((d > 0 ? "+" : "") + euro(d)).font(.system(size: 14, design: .monospaced)).foregroundStyle(d > 0 ? Color.warn : Color.good) } }
                if let biggest = r.vsAverage.first(where: { $0.1 > 20 }) { Text("The one lever: \(biggest.0.lowercased()) is \(euro(biggest.1)) above usual.").font(.system(size: 13)).foregroundStyle(Color.soft) }
            }
        }
        .navigationTitle("Recap")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MoneySetupView: View {
    @EnvironmentObject var store: Store
    @State private var banks: [String] = []
    @State private var connected: String?
    @Environment(\.webAuthenticationSession) private var webAuth

    var body: some View {
        List {
            Section {
                Text("1. Create a free personal application at enablebanking.com and download its private key.\n2. Put the key on your server as data/enablebanking.pem and the application id in config.php (enable_app_id).\n3. Pick your bank below and consent; it lasts about 180 days.").font(.footnote)
                Button("Load banks") { Task { await loadBanks() } }
                ForEach(banks, id: \.self) { b in Button(b) { Task { await connect(b) } } }
                if let connected { Text(connected).foregroundStyle(Color.good) }
            } header: { Text("Bank sync · Enable Banking") }
            Section {
                Text("In Shortcuts → Automation → New → Wallet → \"When I tap any card\": add \"Get contents of URL\" with your server's /tx.php, method POST, header X-Cadence-Token with your token, and JSON fields amount (Shortcut Input → Amount) and merchant (Merchant). Turn off \"Ask before running\".").font(.footnote)
                LabeledContent("URL", value: store.connection.server + "/tx.php").font(.footnote)
            } header: { Text("Instant Apple Pay entries") }
        }
        .cadenceList()
        .navigationTitle("Setup")
    }

    private func loadBanks() async {
        guard let req = store.request("bank.php?banks=1"), let (data, _) = try? await URLSession.shared.data(for: req) else { return }
        struct R: Decodable { var banks: [String]? ; var error: String? }
        if let r = try? JSONDecoder().decode(R.self, from: data) { banks = r.banks ?? []; connected = r.error }
    }

    private func connect(_ bank: String) async {
        var c = URLComponents(string: store.connection.server + "/bank.php")
        c?.queryItems = [URLQueryItem(name: "token", value: store.connection.token), URLQueryItem(name: "bank", value: bank)]
        guard let url = c?.url else { return }
        if let back = try? await webAuth.authenticate(using: url, callbackURLScheme: "cadence"), back.absoluteString.contains("ok=1") {
            connected = "\(bank) connected"
            await store.pullBank()
        }
    }
}

struct TransactionEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var tx: Transaction
    @State private var amount = ""
    @State private var out = true
    var body: some View {
        NavigationStack {
            Form {
                TextField("Merchant or what", text: $tx.merchant)
                HStack { Picker("", selection: $out) { Text("Out").tag(true); Text("In").tag(false) }.pickerStyle(.segmented).frame(width: 120); TextField("Amount €", text: $amount).keyboardType(.decimalPad) }
                DatePicker("Date", selection: Binding(get: { Day.date(tx.date) }, set: { tx.date = Day.key($0) }), displayedComponents: .date)
                Picker("Category", selection: Binding(get: { tx.category ?? store.category(for: tx) }, set: { tx.category = $0 })) { ForEach(moneyCategories, id: \.self) { Text($0).tag($0) } }
                Picker("Paid from", selection: $tx.wallet) {
                    Text("My money").tag(String?.none)
                    ForEach(store.all(Wallet.self)) { Text($0.name).tag(Optional($0.id)) }
                }
                if let v = tx.vat, v > 0 { LabeledContent("VAT", value: euro(v, decimals: true)) }
            }
            .cadenceList()
            .navigationTitle("Transaction")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let v = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
                        tx.amount = out ? -abs(v) : abs(v)
                        tx.reviewed = true
                        if tx.merchant.isEmpty { tx.merchant = tx.category ?? "Spending" }
                        store.save(tx)
                        if let wid = tx.wallet, var w = store.record(Wallet.self, wid) { w.balance = max(0, w.balance + tx.amount); store.save(w) }
                        dismiss()
                    }
                }
            }
            .onAppear { if tx.amount != 0 { amount = String(format: "%.2f", abs(tx.amount)); out = tx.amount < 0 } }
        }
    }
}

struct RecurringEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var item: Recurring
    @State private var amount = ""
    @State private var incoming = false
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (salary, house loan, gym…)", text: $item.title)
                HStack { Picker("", selection: $incoming) { Text("Out").tag(false); Text("In").tag(true) }.pickerStyle(.segmented).frame(width: 120); TextField("€", text: $amount).keyboardType(.decimalPad) }
                Picker("Every", selection: Binding(get: { item.everyWeeks > 0 ? "w\(item.everyWeeks)" : "m\(item.everyMonths)" }, set: { v in
                    if v.hasPrefix("w") { item.everyWeeks = Int(v.dropFirst()) ?? 4 } else { item.everyWeeks = 0; item.everyMonths = Int(v.dropFirst()) ?? 1 }
                })) {
                    Text("Month").tag("m1"); Text("2 months").tag("m2"); Text("3 months").tag("m3"); Text("6 months").tag("m6"); Text("Year").tag("m12")
                    Text("Week").tag("w1"); Text("2 weeks").tag("w2"); Text("4 weeks").tag("w4")
                }
                DatePicker("Next on", selection: Binding(get: { Day.date(item.next) }, set: { item.next = Day.key($0) }), displayedComponents: .date)
                Picker("Category", selection: $item.category) { ForEach(moneyCategories, id: \.self) { Text($0).tag($0) } }
                Toggle("Subscription", isOn: $item.subscription)
                Stepper("Remind \(item.remindDays) days before", value: $item.remindDays, in: 0...30)
                Toggle("Cancel-by date", isOn: Binding(get: { item.cancelBy != nil }, set: { item.cancelBy = $0 ? Day.add(-2, to: item.next) : nil }))
                if item.cancelBy != nil { DatePicker("Cancel by", selection: Binding(get: { Day.date(item.cancelBy ?? Day.today) }, set: { item.cancelBy = Day.key($0) }), displayedComponents: .date) }
                if store.record(Recurring.self, item.id) != nil { Button("Delete", role: .destructive) { store.remove(item); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(item.title.isEmpty ? "In or out" : item.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let v = Double(amount.replacingOccurrences(of: ",", with: ".")) { item.amount = incoming ? abs(v) : -abs(v) }
                        store.save(item); Reminders.shared.reschedule(); dismiss()
                    }.disabled(item.title.isEmpty)
                }
            }
            .onAppear { amount = String(format: "%.2f", abs(item.amount)); incoming = item.amount > 0 }
        }
    }
}

struct WalletEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var wallet: Wallet
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (Coverflex meal card…)", text: $wallet.name)
                TextField("Balance €", value: $wallet.balance, format: .number).keyboardType(.decimalPad)
                TextField("Pays for", text: $wallet.spendsOn)
                TextField("Monthly top-up €", value: $wallet.topUp, format: .number).keyboardType(.decimalPad)
                Toggle("Use-by date", isOn: Binding(get: { wallet.useBy != nil }, set: { wallet.useBy = $0 ? Day.add(90, to: Day.today) : nil }))
                if wallet.useBy != nil { DatePicker("Use by", selection: Binding(get: { Day.date(wallet.useBy ?? Day.today) }, set: { wallet.useBy = Day.key($0) }), displayedComponents: .date) }
                if store.record(Wallet.self, wallet.id) != nil { Button("Delete", role: .destructive) { store.remove(wallet); dismiss() } }
            }
            .cadenceList()
            .navigationTitle("Wallet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(wallet); dismiss() }.disabled(wallet.name.isEmpty) }
            }
        }
    }
}

struct GoalEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var goal: SavingsGoal
    @State private var add = ""
    var body: some View {
        NavigationStack {
            Form {
                TextField("What (headphones, trip…)", text: $goal.title)
                TextField("Price €", value: $goal.price, format: .number).keyboardType(.decimalPad)
                Toggle("Target date", isOn: Binding(get: { goal.by != nil }, set: { goal.by = $0 ? Day.add(120, to: Day.today) : nil }))
                if goal.by != nil { DatePicker("By", selection: Binding(get: { Day.date(goal.by ?? Day.today) }, set: { goal.by = Day.key($0) }), displayedComponents: .date) }
                HStack { Text("Saved \(euro(goal.saved))"); Spacer(); TextField("+ €", text: $add).keyboardType(.decimalPad).frame(width: 70); Button("Add") { if let v = Double(add.replacingOccurrences(of: ",", with: ".")) { goal.saved += v; add = "" } } }
                if store.record(SavingsGoal.self, goal.id) != nil { Button("Delete", role: .destructive) { store.remove(goal); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(goal.title.isEmpty ? "Saving for" : goal.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(goal); dismiss() }.disabled(goal.title.isEmpty) }
            }
        }
    }
}

struct QRScanner: UIViewControllerRepresentable {
    var found: (String) -> Void
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], qualityLevel: .accurate, isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }
    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(found: found) }
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var found: (String) -> Void
        var done = false
        init(found: @escaping (String) -> Void) { self.found = found }
        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in addedItems { if case .barcode(let b) = item, let s = b.payloadStringValue { done = true; found(s); return } }
        }
    }
}
