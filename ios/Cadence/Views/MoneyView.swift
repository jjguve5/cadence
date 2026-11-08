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
    @State private var bankMessage: String?

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
            NavigationLink { RecapView() } label: { Text("Resumo do mês · \(store.noSpendDays()) dias sem gastos este mês").font(.geist(14, .semibold)).foregroundStyle(Color(hex: 0xFFD166)) }
            NavigationLink { MoneySetupView() } label: { Text("Configurar o banco e o Apple Pay").font(.geist(13)).foregroundStyle(Color.soft) }
        }
        .navigationTitle("Dinheiro")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.pullBank() }
        .alert("Banco", isPresented: Binding(get: { bankMessage != nil }, set: { if !$0 { bankMessage = nil } })) { Button("OK") { bankMessage = nil } } message: { Text(bankMessage ?? "") }
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
                Eyebrow(text: "Livre para gastar", icon: "eurosign.circle.fill", color: Color(hex: 0xFFD166))
                HStack(alignment: .firstTextBaseline) {
                    Text(euro(m.safePerDay)).font(.geist(34, .bold))
                    Text("por dia · faltam \(m.daysLeft) dias").font(.geist(13)).foregroundStyle(Color.soft)
                }
                row("Rendimentos deste mês", euro(m.income))
                row("Saídas fixas", "−" + euro(m.fixed))
                row("Para objetivos", "−" + euro(m.goals))
                row("Gasto até agora", "−" + euro(m.spent))
                row("A caminho de poupar", euro(m.projectedSaving), color: m.projectedSaving >= m.goals ? .good : .warn)
                if m.income == 0 { Text("Adiciona o teu salário e as saídas fixas abaixo para veres isto como deve ser.").font(.geist(12)).foregroundStyle(Color.soft) }
            }
        }
    }

    private var inboxSection: some View {
        Group {
            let inbox = store.reviewInbox
            if !inbox.isEmpty {
                NavigationLink { ReviewInbox() } label: {
                    Card(tint: .warn) {
                        HStack { Eyebrow(text: "Por rever", icon: "tray.full.fill", color: .warn); Spacer(); Chip(text: "\(inbox.count)", color: .warn) }
                        Text(inbox.prefix(3).map { "\($0.merchant) \(euro(-$0.amount, decimals: true))" }.joined(separator: " · ")).font(.geist(13)).lineLimit(2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var actionsSection: some View {
        Group {
            HStack {
                SoftButton(title: "Adicionar", icon: "plus") { addingTx = Transaction(amount: 0, merchant: "") }
                SoftButton(title: "QR da fatura", icon: "qrcode.viewfinder") { scanning = true }
                    .disabled(!(DataScannerViewController.isSupported && DataScannerViewController.isAvailable))
                SoftButton(title: "Banco", icon: "building.columns") { Task { bankMessage = await store.pullBank() } }
            }
        }
    }

    private var recurringSection: some View {
        Group {
            Card {
                HStack { Eyebrow(text: "Entradas e saídas mensais", icon: "arrow.left.arrow.right"); Spacer(); Button { editingRecurring = Recurring(title: "", amount: -10) } label: { Image(systemName: "plus") }.tint(Color(hex: 0xFFD166)) }
                ForEach(store.all(Recurring.self).sorted { $0.amount > $1.amount }) { r in
                    Button { editingRecurring = r } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.geist(14, .medium))
                                Text((r.everyWeeks > 0 ? "a cada \(r.everyWeeks) semanas" : r.everyMonths == 1 ? "mensal" : "a cada \(r.everyMonths) meses") + " · próxima a \(Day.date(r.occurrences(from: Day.today, to: Day.add(400, to: Day.today)).first ?? r.next).formatted(.dateTime.day().month()))").font(.geist(11.5)).foregroundStyle(Color.faint)
                            }
                            Spacer()
                            Text((r.amount > 0 ? "+" : "") + euro(r.amount, decimals: true)).font(.mono(13.5, .semibold)).foregroundStyle(r.amount > 0 ? Color.good : Color.ink)
                        }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(store.upcomingRenewals.filter { Day.between(Day.today, $0.1) <= $0.0.remindDays && $0.0.amount < 0 }, id: \.0.id) { r, d in
                    Text("\(r.title) renova-se \(Day.date(d).formatted(.dateTime.weekday(.wide)))" + (r.cancelBy.map { ": cancela até \(Day.date($0).formatted(.dateTime.day().month())) se não precisares" } ?? "")).font(.geist(12)).foregroundStyle(Color.warn)
                }
            }
        }
    }

    private var walletsSection: some View {
        Group {
            Card(tint: .mint) {
                HStack { Eyebrow(text: "Benefícios · não é dinheiro teu", icon: "creditcard.fill", color: .mint); Spacer(); Button { editingWallet = Wallet(name: "", balance: 0) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(Wallet.self)) { w in
                    Button { editingWallet = w } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) { Text(w.name).font(.geist(14, .medium)); Text("para \(w.spendsOn.lowercased())" + (w.useBy.map { " · usar até \(Day.date($0).formatted(.dateTime.day().month()))" } ?? "")).font(.geist(11.5)).foregroundStyle(Color.faint) }
                            Spacer()
                            Text(euro(w.balance, decimals: true)).font(.mono(14, .semibold))
                        }
                    }
                    .buttonStyle(.plain)
                }
                if store.all(Wallet.self).contains(where: { $0.balance > 0 }) { Text("Gasta estes primeiro: as compras e refeições pagas com o cartão refeição deixam o teu dinheiro para os objetivos.").font(.geist(12)).foregroundStyle(Color.soft) }
            }
        }
    }

    private var goalsSection: some View {
        Group {
            Card {
                HStack { Eyebrow(text: "A poupar para", icon: "target"); Spacer(); Button { editingGoal = SavingsGoal(title: "", price: 100) } label: { Image(systemName: "plus") }.tint(.mint) }
                ForEach(store.all(SavingsGoal.self)) { g in
                    Button { editingGoal = g } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text("\(g.title) · \(euro(g.price))").font(.geist(14, .medium)); Spacer(); Text("\(euro(g.saved))" + (g.by.map { " · \(Day.date($0).formatted(.dateTime.month(.abbreviated)))" } ?? "")).font(.mono(12)).foregroundStyle(Color.soft) }
                            Bar(progress: g.saved / max(1, g.price), area: .mint)
                            if let by = g.by, g.saved < g.price { Text("\(euro((g.price - g.saved) / Double(max(1, Day.between(Day.today, by) / 30)))) por mês e chegas lá").font(.geist(11.5)).foregroundStyle(Color.faint) }
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
                Eyebrow(text: "Vale a pena? · 72 horas para pensar", icon: "hourglass")
                HStack {
                    TextField("Algo que queres", text: $wish)
                    TextField("€", text: $wishPrice).keyboardType(.decimalPad).frame(width: 60)
                    Button("Adicionar") { if let p = Double(wishPrice.replacingOccurrences(of: ",", with: ".")) { store.save(WishItem(title: wish, price: p)); wish = ""; wishPrice = "" } }.disabled(wish.isEmpty)
                }
                ForEach(store.all(WishItem.self).filter { $0.decision == nil }) { WishRow(item: $0) }
                let skipped = store.all(WishItem.self).filter { $0.decision == "skipped" }.map(\.price).reduce(0, +)
                if skipped > 0 { Text("Não compraste depois de esperar: \(euro(skipped)) poupados").font(.geist(12)).foregroundStyle(Color.good) }
            }
        }
    }

    private var watchSection: some View {
        Group {
            let watch = store.subscriptionWatch()
            if !watch.isEmpty {
                Card(tint: .warn) {
                    Eyebrow(text: "Vigiar subscrições", icon: "eye.fill", color: .warn)
                    ForEach(watch, id: \.self) { Text($0).font(.geist(13)) }
                }
            }
        }
    }

    private func row(_ name: String, _ value: String, color: Color = .ink) -> some View {
        HStack { Text(name).font(.geist(13.5)).foregroundStyle(Color.soft); Spacer(); Text(value).font(.mono(13.5, .semibold)).foregroundStyle(color) }
    }
}

struct WishRow: View {
    @EnvironmentObject var store: Store
    var item: WishItem
    var body: some View {
        HStack {
            Text("\(item.title) · \(euro(item.price))").font(.geist(13.5))
            Spacer()
            if item.ready {
                Button("Desistir") { decide("skipped") }.tint(Color.good)
                Button("Comprar") { decide("bought") }.tint(Color.soft)
            } else {
                Text("espera \(item.hoursLeft) h").font(.geist(12)).foregroundStyle(Color.faint)
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
                        VStack(alignment: .leading) { Text(t.merchant); Text("\(Day.date(t.date).formatted(.dateTime.day().month())) · \(transactionSourceLabel(t.source))").font(.caption).foregroundStyle(Color.soft) }
                        Spacer()
                        Text(euro(t.amount, decimals: true)).monospaced()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            let guess = store.category(for: t)
                            ForEach([guess] + moneyCategories.filter { $0 != guess }, id: \.self) { c in
                                Chip(text: moneyCategoryLabel(c), color: c == guess ? Color(hex: 0x2B1A05) : .ink, fill: c == guess ? Color(hex: 0xFFD166) : .white.opacity(0.08)).onTapGesture { store.categorize(t, c) }
                            }
                        }
                    }
                }
                .swipeActions { Button("Apagar", role: .destructive) { store.remove(t) } }
            }
        }
        .cadenceList()
        .navigationTitle("Rever")
    }
}

struct RecapView: View {
    @EnvironmentObject var store: Store
    @State private var month = String(Day.today.prefix(7))
    var body: some View {
        let r = store.recap(month: month)
        Screen(glow: Color(hex: 0xFFD166)) {
            Picker("Mês", selection: $month) {
                ForEach(0..<6, id: \.self) { i in
                    let m = String(Day.key(Day.calendar.date(byAdding: .month, value: -i, to: Date()) ?? Date()).prefix(7))
                    Text(Day.date(m + "-01").formatted(.dateTime.month(.wide).year())).tag(m)
                }
            }
            .tint(Color(hex: 0xFFD166))
            Card {
                Eyebrow(text: "Gasto")
                Text(euro(r.total)).font(.geist(30, .bold))
                ForEach(r.top, id: \.0) { c, v in HStack { Text(moneyCategoryLabel(c)).font(.geist(14)); Spacer(); Text(euro(v)).font(.mono(14)) } }
            }
            Card {
                Eyebrow(text: "Face à tua média de 3 meses")
                ForEach(r.vsAverage, id: \.0) { c, d in HStack { Text(moneyCategoryLabel(c)).font(.geist(14)); Spacer(); Text((d > 0 ? "+" : "") + euro(d)).font(.mono(14)).foregroundStyle(d > 0 ? Color.warn : Color.good) } }
                if let biggest = r.vsAverage.first(where: { $0.1 > 20 }) { Text("Onde mexer: \(moneyCategoryLabel(biggest.0).lowercased()) está \(euro(biggest.1)) acima do habitual.").font(.geist(13)).foregroundStyle(Color.soft) }
            }
        }
        .navigationTitle("Resumo")
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
                Text("1. Cria uma aplicação pessoal gratuita em enablebanking.com e descarrega a chave privada.\n2. Põe a chave no teu servidor como data/enablebanking.pem e o id da aplicação em config.php (enable_app_id).\n3. Escolhe o teu banco abaixo e dá autorização; dura cerca de 180 dias.").font(.footnote)
                Button("Carregar bancos") { Task { await loadBanks() } }
                ForEach(banks, id: \.self) { b in Button(b) { Task { await connect(b) } } }
                if let connected { Text(connected).foregroundStyle(Color.good) }
            } header: { Text("Sincronização bancária · Enable Banking") }
            Section {
                Text("Em Atalhos → Automatização → Nova → Wallet → «Quando toco em qualquer cartão»: adiciona «Obter conteúdo do URL» com o /tx.php do teu servidor, método POST, cabeçalho X-Cadence-Token com o teu token e os campos JSON amount (Entrada do atalho → Montante) e merchant (Comerciante). Desliga «Perguntar antes de executar».").font(.footnote)
                LabeledContent("URL", value: store.connection.server + "/tx.php").font(.footnote)
            } header: { Text("Entradas instantâneas do Apple Pay") }
        }
        .cadenceList()
        .navigationTitle("Configuração")
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
            connected = "\(bank) ligado"
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
                TextField("Comerciante ou o quê", text: $tx.merchant)
                HStack { Picker("", selection: $out) { Text("Saída").tag(true); Text("Entrada").tag(false) }.pickerStyle(.segmented).frame(width: 120); TextField("Valor €", text: $amount).keyboardType(.decimalPad) }
                DatePicker("Data", selection: Binding(get: { Day.date(tx.date) }, set: { tx.date = Day.key($0) }), displayedComponents: .date)
                Picker("Categoria", selection: Binding(get: { tx.category ?? store.category(for: tx) }, set: { tx.category = $0 })) { ForEach(moneyCategories, id: \.self) { Text(moneyCategoryLabel($0)).tag($0) } }
                Picker("Pago com", selection: $tx.wallet) {
                    Text("O meu dinheiro").tag(String?.none)
                    ForEach(store.all(Wallet.self)) { Text($0.name).tag(Optional($0.id)) }
                }
                if let v = tx.vat, v > 0 { LabeledContent("IVA", value: euro(v, decimals: true)) }
            }
            .cadenceList()
            .navigationTitle("Transação")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        guard let v = Double(amount.replacingOccurrences(of: ",", with: ".")) else { return }
                        tx.amount = out ? -abs(v) : abs(v)
                        tx.reviewed = true
                        if tx.merchant.isEmpty { tx.merchant = tx.category.map(moneyCategoryLabel) ?? "Gasto" }
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
                TextField("Nome (salário, crédito à habitação, ginásio…)", text: $item.title)
                HStack { Picker("", selection: $incoming) { Text("Saída").tag(false); Text("Entrada").tag(true) }.pickerStyle(.segmented).frame(width: 120); TextField("€", text: $amount).keyboardType(.decimalPad) }
                Picker("A cada", selection: Binding(get: { item.everyWeeks > 0 ? "w\(item.everyWeeks)" : "m\(item.everyMonths)" }, set: { v in
                    if v.hasPrefix("w") { item.everyWeeks = Int(v.dropFirst()) ?? 4 } else { item.everyWeeks = 0; item.everyMonths = Int(v.dropFirst()) ?? 1 }
                })) {
                    Text("Mês").tag("m1"); Text("2 meses").tag("m2"); Text("3 meses").tag("m3"); Text("6 meses").tag("m6"); Text("Ano").tag("m12")
                    Text("Semana").tag("w1"); Text("2 semanas").tag("w2"); Text("4 semanas").tag("w4")
                }
                DatePicker("Próxima a", selection: Binding(get: { Day.date(item.next) }, set: { item.next = Day.key($0) }), displayedComponents: .date)
                Picker("Categoria", selection: $item.category) { ForEach(moneyCategories, id: \.self) { Text(moneyCategoryLabel($0)).tag($0) } }
                Toggle("Subscrição", isOn: $item.subscription)
                Stepper("Lembrar \(item.remindDays) dias antes", value: $item.remindDays, in: 0...30)
                Toggle("Data limite para cancelar", isOn: Binding(get: { item.cancelBy != nil }, set: { item.cancelBy = $0 ? Day.add(-2, to: item.next) : nil }))
                if item.cancelBy != nil { DatePicker("Cancelar até", selection: Binding(get: { Day.date(item.cancelBy ?? Day.today) }, set: { item.cancelBy = Day.key($0) }), displayedComponents: .date) }
                if store.record(Recurring.self, item.id) != nil { Button("Apagar", role: .destructive) { store.remove(item); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(item.title.isEmpty ? "Entrada ou saída" : item.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
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
                TextField("Nome (cartão refeição Coverflex…)", text: $wallet.name)
                TextField("Saldo €", value: $wallet.balance, format: .number).keyboardType(.decimalPad)
                TextField("Serve para", text: $wallet.spendsOn)
                TextField("Carregamento mensal €", value: $wallet.topUp, format: .number).keyboardType(.decimalPad)
                Toggle("Data limite de uso", isOn: Binding(get: { wallet.useBy != nil }, set: { wallet.useBy = $0 ? Day.add(90, to: Day.today) : nil }))
                if wallet.useBy != nil { DatePicker("Usar até", selection: Binding(get: { Day.date(wallet.useBy ?? Day.today) }, set: { wallet.useBy = Day.key($0) }), displayedComponents: .date) }
                if store.record(Wallet.self, wallet.id) != nil { Button("Apagar", role: .destructive) { store.remove(wallet); dismiss() } }
            }
            .cadenceList()
            .navigationTitle("Carteira")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(wallet); dismiss() }.disabled(wallet.name.isEmpty) }
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
                TextField("O quê (auscultadores, viagem…)", text: $goal.title)
                TextField("Preço €", value: $goal.price, format: .number).keyboardType(.decimalPad)
                Toggle("Data alvo", isOn: Binding(get: { goal.by != nil }, set: { goal.by = $0 ? Day.add(120, to: Day.today) : nil }))
                if goal.by != nil { DatePicker("Até", selection: Binding(get: { Day.date(goal.by ?? Day.today) }, set: { goal.by = Day.key($0) }), displayedComponents: .date) }
                HStack { Text("Poupado \(euro(goal.saved))"); Spacer(); TextField("+ €", text: $add).keyboardType(.decimalPad).frame(width: 70); Button("Adicionar") { if let v = Double(add.replacingOccurrences(of: ",", with: ".")) { goal.saved += v; add = "" } } }
                if store.record(SavingsGoal.self, goal.id) != nil { Button("Apagar", role: .destructive) { store.remove(goal); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(goal.title.isEmpty ? "A poupar para" : goal.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(goal); dismiss() }.disabled(goal.title.isEmpty) }
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
