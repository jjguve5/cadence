// Money: transactions (bank sync, Apple Pay, receipt QR, typed), monthly ins and outs on any rhythm, benefit wallets
// that don't count as your money, savings goals, the 72-hour list, and the rules on top: safe to spend, on track to
// save, subscription watch, the monthly recap.
import Foundation

struct Transaction: Record, Equatable {
    static let kind = "tx"
    var id = UUID().uuidString
    var date = Day.today
    var minute = Day.minuteOfDay()
    var amount: Double // negative = out
    var merchant: String
    var category: String?
    var account: String?
    var source = "manual" // bank, applepay, receipt, manual
    var reviewed = false
    var wallet: String? // paid from a benefit wallet: not your cash
    var nif: String?
    var vat: Double?
    var matched: String? // the Apple Pay entry a bank line confirmed
}

struct Recurring: Record, Equatable {
    static let kind = "recurring"
    var id = UUID().uuidString
    var title: String
    var amount: Double // positive in, negative out
    var everyMonths = 1
    var everyWeeks = 0 // when set, overrides months (gym every 4 weeks)
    var next: String = Day.today
    var category = "Bills"
    var remindDays = 3
    var cancelBy: String?
    var subscription = false

    func occurrences(from: String, to: String) -> [String] {
        var out: [String] = []
        var d = next
        var guardCount = 0
        // walk back to before `from`
        while d > from && guardCount < 400 { d = step(d, -1); guardCount += 1 }
        while d <= to && guardCount < 800 {
            if d >= from { out.append(d) }
            d = step(d, 1); guardCount += 1
        }
        return out
    }

    private func step(_ d: String, _ sign: Int) -> String {
        if everyWeeks > 0 { return Day.add(7 * everyWeeks * sign, to: d) }
        return Day.key(Day.calendar.date(byAdding: .month, value: everyMonths * sign, to: Day.date(d)) ?? Day.date(d))
    }
}

struct Wallet: Record, Equatable {
    static let kind = "wallet"
    var id = UUID().uuidString
    var name: String // Coverflex meal card, flexible benefits
    var balance: Double
    var spendsOn = "Comida" // what it can pay for: free text, only shown
    var topUp: Double = 0 // monthly
    var useBy: String?
}

struct SavingsGoal: Record, Equatable {
    static let kind = "goal"
    var id = UUID().uuidString
    var title: String
    var price: Double
    var saved: Double = 0
    var by: String?
    var created = Day.today
}

struct WishItem: Record, Equatable {
    static let kind = "wish"
    var id = UUID().uuidString
    var title: String
    var price: Double
    var added = nowMs()
    var decision: String? // bought, skipped
    var goalId: String?

    private static let wait: Double = 72 * 3600 * 1000
    var ready: Bool { nowMs() - added >= WishItem.wait }
    var hoursLeft: Int { Int((WishItem.wait - (nowMs() - added)) / 3_600_000) }
}

struct CategoryRule: Record, Equatable {
    static let kind = "rule"
    var id: String // merchant key
    var category: String
}

let moneyCategories = ["Groceries", "Eating out", "Delivery", "Transport", "Bills", "Rent / house", "Gym", "Subscriptions", "Clothes", "Health", "Fun", "Travel", "Gifts", "Income", "Transfer", "Other"]

/// The categories stay stored in English (Transaction.category, Recurring.category, CategoryRule and the rules that
/// compare them); this is the name shown
func moneyCategoryLabel(_ category: String) -> String {
    ["Groceries": "Supermercado", "Eating out": "Restaurantes", "Delivery": "Entregas", "Transport": "Transportes", "Bills": "Contas",
     "Rent / house": "Renda / casa", "Gym": "Ginásio", "Subscriptions": "Subscrições", "Clothes": "Roupa", "Health": "Saúde", "Fun": "Lazer",
     "Travel": "Viagens", "Gifts": "Presentes", "Income": "Rendimentos", "Transfer": "Transferências", "Other": "Outros"][category] ?? category
}

/// Transaction.source stays "bank", "applepay", "receipt" or "manual"; this is the word shown
func transactionSourceLabel(_ source: String) -> String {
    ["bank": "banco", "applepay": "Apple Pay", "receipt": "fatura", "manual": "manual"][source] ?? source
}

func euro(_ v: Double, decimals: Bool = false) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "EUR"
    f.locale = Locale(identifier: "pt_PT")
    f.maximumFractionDigits = decimals ? 2 : 0
    return f.string(from: NSNumber(value: v)) ?? "€\(Int(v))"
}

func merchantKey(_ s: String) -> String {
    s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count > 2 && Int($0) == nil }.prefix(2).joined(separator: " ")
}

/// The QR on Portuguese receipts (Portaria 195/2020): "A:NIF*B:NIF*...*F:date*...*N:VAT*O:total*...*H:ATCUD"
struct ReceiptQR {
    var nif: String
    var date: String
    var total: Double
    var vat: Double

    init?(_ text: String) {
        var f: [String: String] = [:]
        for part in text.split(separator: "*") {
            let kv = part.split(separator: ":", maxSplits: 1).map(String.init)
            if kv.count == 2 { f[kv[0]] = kv[1] }
        }
        guard let a = f["A"], let o = f["O"], let total = Double(o), let d = f["F"], d.count == 8 else { return nil }
        nif = a
        date = "\(d.prefix(4))-\(d.dropFirst(4).prefix(2))-\(d.suffix(2))"
        self.total = total
        vat = Double(f["N"] ?? "") ?? 0
    }
}

struct MoneyMonth {
    var income: Double
    var fixed: Double
    var goals: Double
    var spent: Double
    var safePerDay: Double
    var freeLeft: Double
    var projectedSaving: Double
    var daysLeft: Int
}

@MainActor
extension Store {
    var transactions: [Transaction] { all(Transaction.self).sorted { ($0.date, $0.minute) > ($1.date, $1.minute) } }

    func category(for t: Transaction) -> String {
        if let c = t.category { return c }
        if t.amount > 0 { return "Income" }
        return record(CategoryRule.self, merchantKey(t.merchant))?.category ?? "Other"
    }

    var reviewInbox: [Transaction] { transactions.filter { !$0.reviewed && $0.matched == nil } }

    func categorize(_ t: Transaction, _ category: String) {
        var x = t
        x.category = category
        x.reviewed = true
        save(x)
        // Every swipe teaches the rules
        let key = merchantKey(t.merchant)
        if !key.isEmpty { save(CategoryRule(id: key, category: category)) }
    }

    /// A bank line that matches an Apple Pay entry (same amount within 3 days) confirms it
    func matchApplePay() {
        let pays = transactions.filter { $0.source == "applepay" && $0.matched == nil }
        for b in transactions where b.source == "bank" && b.amount < 0 {
            if let p = pays.first(where: { abs($0.amount - b.amount) < 0.01 && abs(Day.between($0.date, b.date)) <= 3 }), !transactions.contains(where: { $0.matched == p.id }) {
                var x = b
                x.matched = p.id
                x.category = x.category ?? p.category
                x.reviewed = x.reviewed || p.reviewed
                save(x)
                remove(p)
            }
        }
    }

    func monthRange(_ day: String = Day.today) -> (String, String) {
        let start = String(day.prefix(7)) + "-01"
        let next = Day.key(Day.calendar.date(byAdding: .month, value: 1, to: Day.date(start)) ?? Day.date(start))
        return (start, Day.add(-1, to: next))
    }

    func spending(from: String, to: String) -> [Transaction] {
        transactions.filter { $0.date >= from && $0.date <= to && $0.amount < 0 && $0.wallet == nil && !["Transfer", "Income"].contains(category(for: $0)) }
    }

    /// Income minus fixed outs, goal money and what's spent, as a daily amount for the rest of the month
    func moneyMonth() -> MoneyMonth {
        let (start, end) = monthRange()
        let recurring = all(Recurring.self)
        let income = recurring.filter { $0.amount > 0 }.map { $0.amount * Double($0.occurrences(from: start, to: end).count) }.reduce(0, +)
        let fixed = recurring.filter { $0.amount < 0 }.map { -$0.amount * Double($0.occurrences(from: start, to: end).count) }.reduce(0, +)
        let goalMoney = all(SavingsGoal.self).filter { $0.saved < $0.price }.compactMap { g -> Double? in
            guard let by = g.by else { return nil }
            let months = max(1, Day.between(Day.today, by) / 30)
            return (g.price - g.saved) / Double(months)
        }.reduce(0, +)
        // Spending that isn't one of the fixed outs
        let fixedNames = Set(recurring.map { merchantKey($0.title) })
        let spent = spending(from: start, to: end).filter { !fixedNames.contains(merchantKey($0.merchant)) }.map { -$0.amount }.reduce(0, +)
        let daysLeft = max(1, Day.between(Day.today, end) + 1)
        let free = income - fixed - goalMoney - spent
        let daysGone = max(1, Day.between(start, Day.today) + 1)
        let projected = income - fixed - spent / Double(daysGone) * Double(daysGone + daysLeft - 1)
        return MoneyMonth(income: income, fixed: fixed, goals: goalMoney, spent: spent, safePerDay: max(0, free) / Double(daysLeft), freeLeft: free, projectedSaving: projected, daysLeft: daysLeft)
    }

    var upcomingRenewals: [(Recurring, String)] {
        all(Recurring.self).compactMap { r in r.occurrences(from: Day.today, to: Day.add(30, to: Day.today)).first.map { (r, $0) } }.sorted { $0.1 < $1.1 }
    }

    /// Charges that repeat monthly and aren't in your list yet; price rises on known ones
    func subscriptionWatch() -> [String] {
        var out: [String] = []
        let outs = transactions.filter { $0.amount < 0 && Day.between($0.date, Day.today) <= 100 }
        let byMerchant = Dictionary(grouping: outs) { merchantKey($0.merchant) }
        let known = Set(all(Recurring.self).map { merchantKey($0.title) })
        for (key, list) in byMerchant where !key.isEmpty && list.count >= 2 {
            let months = Set(list.map { $0.date.prefix(7) })
            let amounts = list.map { -$0.amount }
            guard months.count >= 2, let lo = amounts.min(), let hi = amounts.max(), hi - lo < max(1, lo * 0.15) else { continue }
            if !known.contains(key) { out.append("\(list[0].merchant): \(euro(hi, decimals: true)) todos os meses, fora da tua lista") }
        }
        for r in all(Recurring.self) where r.amount < 0 {
            if let last = byMerchant[merchantKey(r.title)]?.max(by: { $0.date < $1.date }), -last.amount > -r.amount + 0.5 {
                out.append("\(r.title) subiu: \(euro(-last.amount, decimals: true)) em vez de \(euro(-r.amount, decimals: true))")
            }
        }
        return out
    }

    func recap(month: String) -> (total: Double, top: [(String, Double)], vsAverage: [(String, Double)]) {
        let start = month + "-01"
        let (_, end) = monthRange(start)
        let spend = spending(from: start, to: end)
        let total = spend.map { -$0.amount }.reduce(0, +)
        let byCat = Dictionary(grouping: spend) { category(for: $0) }.mapValues { $0.map { -$0.amount }.reduce(0, +) }
        let top = byCat.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
        var prev: [String: Double] = [:]
        for i in 1...3 {
            let m = Day.key(Day.calendar.date(byAdding: .month, value: -i, to: Day.date(start)) ?? Day.date(start))
            let (s, e) = monthRange(m)
            for t in spending(from: s, to: e) { prev[category(for: t), default: 0] += -t.amount / 3 }
        }
        let diff = byCat.map { ($0.key, $0.value - (prev[$0.key] ?? 0)) }.sorted { abs($0.1) > abs($1.1) }.prefix(3).map { $0 }
        return (total, top, diff)
    }

    /// Days this month with no discretionary spending: they grow Pip's sprout
    func noSpendDays() -> Int {
        let (start, _) = monthRange()
        let spentDays = Set(spending(from: start, to: Day.today).filter { !["Bills", "Rent / house", "Gym", "Subscriptions", "Groceries"].contains(category(for: $0)) }.map(\.date))
        return (0...max(0, Day.between(start, Day.today))).filter { !spentDays.contains(Day.add($0, to: start)) }.count
    }

    /// Pulls new bank transactions and says what happened
    @discardableResult
    func pullBank() async -> String {
        guard let req = request("bank.php?pull=1") else { return "Sem ligação ao teu servidor." }
        guard let (data, resp) = try? await URLSession.shared.data(for: req) else { return "Sem ligação: tenta mais tarde." }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        struct R: Decodable { var added: Int?; var banks: [String: String]?; var error: String? }
        let r = try? JSONDecoder().decode(R.self, from: data)
        if code == 409 { return "A sincronização bancária ainda não está configurada. Precisa de uma aplicação gratuita da Enable Banking no teu servidor: vê «Configurar o banco e o Apple Pay», no fundo." }
        guard code == 200, let r else { return r?.error ?? "O banco não respondeu (\(code))." }
        await sync()
        matchApplePay()
        if (r.banks ?? [:]).isEmpty { return "Ainda não há nenhum banco ligado: liga um na configuração, no fundo." }
        return "\(r.added ?? 0) \((r.added ?? 0) == 1 ? "transação nova" : "transações novas"). " + (r.banks ?? [:]).map { "\($0.key): \($0.value)" }.joined(separator: " · ")
    }
}
