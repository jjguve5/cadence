// What to say to a friend: suggestions composed from hand-written parts, in European Portuguese and English. Each
// person has their own shuffle and their own place in it, kept in a synced record, so a suggestion never comes back
// for the same person. A suggestion counts as seen from the moment it's drawn; the ones on screen stay until they're
// replaced or used, so nothing is lost by closing the screen. Different friends can get the same line.
import SwiftUI
import UIKit

enum FriendLanguage: String, CaseIterable, Identifiable, Sendable {
    case pt, en
    var id: String { rawValue }
    var label: String { self == .pt ? "Português" : "English" }
}

enum FriendCategory: String, CaseIterable, Sendable {
    case checkIn, beenAWhile, plan, share, askAbout, birthday, encouragement

    func pool(_ language: FriendLanguage) -> PhrasePool {
        switch language {
        case .pt:
            switch self {
            case .checkIn: return FriendLinesPT.checkIn
            case .beenAWhile: return FriendLinesPT.beenAWhile
            case .plan: return FriendLinesPT.plan
            case .share: return FriendLinesPT.share
            case .askAbout: return FriendLinesPT.askAbout
            case .birthday: return FriendLinesPT.birthday
            case .encouragement: return FriendLinesPT.encouragement
            }
        case .en:
            switch self {
            case .checkIn: return FriendLinesEN.checkIn
            case .beenAWhile: return FriendLinesEN.beenAWhile
            case .plan: return FriendLinesEN.plan
            case .share: return FriendLinesEN.share
            case .askAbout: return FriendLinesEN.askAbout
            case .birthday: return FriendLinesEN.birthday
            case .encouragement: return FriendLinesEN.encouragement
            }
        }
    }
}

/// One suggestion drawn for one person. Only its place in the shuffle is stored; the text is worked out when shown.
struct FriendSuggestion: Codable, Equatable, Identifiable {
    var category: String
    var language: String
    var position: Int
    var used = false
    var id: String { "\(language).\(category).\(position)" }
}

/// Per person: the chosen language, how far each shuffle has gone, and what's on screen.
struct FriendLedger: Codable, Equatable {
    var language: String?
    var positions: [String: Int] = [:]
    var draws: [String: Int] = [:]
    var showing: [String: [FriendSuggestion]] = [:]
}

/// Where the ledgers live: the store on the phone, a dictionary in the tests.
@MainActor
protocol FriendLedgerStore {
    func friendLedger(_ personId: String) -> FriendLedger?
    func saveFriendLedger(_ ledger: FriendLedger, _ personId: String)
}

extension Store: FriendLedgerStore {
    func friendLedger(_ personId: String) -> FriendLedger? { records(FriendMessages.recordType)[personId]?.decode(FriendLedger.self) }

    func saveFriendLedger(_ ledger: FriendLedger, _ personId: String) {
        guard let value = JSONValue.from(ledger) else { return }
        put(FriendMessages.recordType, personId, value)
    }
}

enum FriendMessages {
    static let recordType = "friendSay"
    static let showCount = 3

    // MARK: Reading

    @MainActor
    static func language(for personId: String, in ledgers: FriendLedgerStore) -> FriendLanguage {
        ledgers.friendLedger(personId)?.language.flatMap(FriendLanguage.init(rawValue:)) ?? .pt
    }

    @MainActor
    static func showing(for personId: String, language: FriendLanguage, in ledgers: FriendLedgerStore) -> [FriendSuggestion] {
        ledgers.friendLedger(personId)?.showing[language.rawValue] ?? []
    }

    /// The words of a suggestion for this person. Pure, so it's safe while a view draws.
    static func text(_ suggestion: FriendSuggestion, personId: String, name: String) -> String {
        guard let category = FriendCategory(rawValue: suggestion.category), let language = FriendLanguage(rawValue: suggestion.language) else { return "" }
        return line(category, language, position: suggestion.position, personId: personId, name: name)
    }

    /// Which kinds of message make sense for this person today: "it's been a while" only after a while, birthday
    /// lines only around their birthday.
    static func categories(for person: Person, today: String = Day.today) -> [FriendCategory] {
        var out: [FriendCategory] = [.checkIn, .plan, .share, .askAbout, .encouragement]
        let since = person.lastContact.map { Day.between($0, today) } ?? 999
        if since >= 14 { out.append(.beenAWhile) }
        if let birthday = person.birthday, let year = Int(today.prefix(4)) {
            let near = [year - 1, year, year + 1].contains { abs(Day.between(today, "\($0)-\(birthday)")) <= 10 }
            if near { out.append(.birthday) }
        }
        return out
    }

    // MARK: Changing

    @MainActor
    static func setLanguage(_ language: FriendLanguage, for personId: String, in ledgers: FriendLedgerStore) {
        var ledger = ledgers.friendLedger(personId) ?? FriendLedger()
        guard ledger.language != language.rawValue else { return }
        ledger.language = language.rawValue
        ledgers.saveFriendLedger(ledger, personId)
    }

    /// The next unseen suggestion for this person. It goes on top of the ones on screen and pushes out the oldest.
    @discardableResult
    @MainActor
    static func next(for personId: String, language: FriendLanguage, categories: [FriendCategory] = FriendCategory.allCases, in ledgers: FriendLedgerStore) -> FriendSuggestion {
        var ledger = ledgers.friendLedger(personId) ?? FriendLedger()
        let suggestion = draw(&ledger, personId: personId, language: language, categories: categories)
        var list = ledger.showing[language.rawValue] ?? []
        list.insert(suggestion, at: 0)
        ledger.showing[language.rawValue] = Array(list.prefix(showCount))
        ledgers.saveFriendLedger(ledger, personId)
        return suggestion
    }

    /// Replaces what's been used and tops up to `showCount`. Call it from onAppear or a button, not from a view's
    /// body: it writes to the store. Writes nothing when there's nothing to change.
    @MainActor
    static func fill(for personId: String, language: FriendLanguage, categories: [FriendCategory] = FriendCategory.allCases, in ledgers: FriendLedgerStore) {
        var ledger = ledgers.friendLedger(personId) ?? FriendLedger()
        let before = ledger.showing[language.rawValue] ?? []
        var list = before.filter { !$0.used }
        while list.count < showCount {
            list.append(draw(&ledger, personId: personId, language: language, categories: categories))
        }
        guard list != before else { return }
        ledger.showing[language.rawValue] = list
        ledgers.saveFriendLedger(ledger, personId)
    }

    /// Copied or shared: it stays visible for now and is replaced the next time this person's suggestions open.
    @MainActor
    static func markUsed(_ suggestion: FriendSuggestion, for personId: String, in ledgers: FriendLedgerStore) {
        guard var ledger = ledgers.friendLedger(personId), var list = ledger.showing[suggestion.language],
              let at = list.firstIndex(where: { $0.id == suggestion.id }), !list[at].used else { return }
        list[at].used = true
        ledger.showing[suggestion.language] = list
        ledgers.saveFriendLedger(ledger, personId)
    }

    // MARK: Library

    /// Every line of a language, for counting in the tests. Only ever built there.
    static func allLines(_ language: FriendLanguage, name: String = "Ana") -> [String] {
        var out: [String] = []
        for category in FriendCategory.allCases {
            for position in 0..<category.pool(language).count {
                out.append(line(category, language, position: position, personId: "library", name: name))
            }
        }
        return out
    }

    static func poolSize(_ language: FriendLanguage) -> Int {
        FriendCategory.allCases.reduce(0) { $0 + $1.pool(language).count }
    }

    private static func draw(_ ledger: inout FriendLedger, personId: String, language: FriendLanguage, categories: [FriendCategory]) -> FriendSuggestion {
        let wanted = categories.isEmpty ? FriendCategory.allCases : categories
        let positions = ledger.positions
        func hasRoom(_ category: FriendCategory) -> Bool { (positions[slot(category, language)] ?? 0) < category.pool(language).count }
        // Takes turns through the kinds of message, starting somewhere different for each person
        let turn = ledger.draws[language.rawValue] ?? 0
        let offset = Int(PhrasePool.stableHash(personId) % UInt64(wanted.count))
        var chosen: FriendCategory?
        for i in 0..<wanted.count where chosen == nil {
            let candidate = wanted[(turn + offset + i) % wanted.count]
            if hasRoom(candidate) { chosen = candidate }
        }
        if chosen == nil { chosen = FriendCategory.allCases.first(where: hasRoom) }
        if chosen == nil {
            // Every line for this person, in this language, has been shown: only now can they start over
            for category in FriendCategory.allCases { ledger.positions[slot(category, language)] = 0 }
            chosen = wanted[(turn + offset) % wanted.count]
        }
        let category = chosen ?? .checkIn
        let position = ledger.positions[slot(category, language)] ?? 0
        ledger.positions[slot(category, language)] = position + 1
        ledger.draws[language.rawValue] = turn + 1
        return FriendSuggestion(category: category.rawValue, language: language.rawValue, position: position)
    }

    private static func slot(_ category: FriendCategory, _ language: FriendLanguage) -> String { "\(language.rawValue).\(category.rawValue)" }

    private static func line(_ category: FriendCategory, _ language: FriendLanguage, position: Int, personId: String, name: String) -> String {
        let pool = category.pool(language)
        let seed = PhrasePool.stableHash("\(personId)|\(language.rawValue)|\(category.rawValue)")
        let pick = pool.pick(position, seed: seed)
        let parts: [String?] = [pick.opener.map { fillName($0, name) }, pick.body, pick.closer]
        return parts.compactMap { $0 }.joined(separator: " ")
    }

    /// First name only. With no name, "Olá, {name}, tudo bem?" just becomes "Olá, tudo bem?"
    private static func fillName(_ part: String, _ name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        if first.isEmpty {
            return part.replacingOccurrences(of: ", {name}", with: "").replacingOccurrences(of: " {name}", with: "")
        }
        return part.replacingOccurrences(of: "{name}", with: first)
    }
}

// MARK: - The screen

/// Several things to say to one person, with their language, "Another one", copy and share.
struct FriendSuggestionsSheet: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    let person: Person
    @State private var copied: String? = nil
    private let accent = Color(hex: 0xFF9FBF)

    var body: some View {
        let language = FriendMessages.language(for: person.id, in: store)
        NavigationStack {
            Screen(glow: accent) {
                Picker("Language", selection: Binding(get: { language }, set: { choose($0) })) {
                    ForEach(FriendLanguage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("friend.language")
                ForEach(FriendMessages.showing(for: person.id, language: language, in: store)) { s in
                    row(s)
                }
                SoftButton(title: "Another one", icon: "arrow.triangle.2.circlepath") {
                    FriendMessages.next(for: person.id, language: language, categories: FriendMessages.categories(for: person), in: store)
                }
                .accessibilityIdentifier("friend.another")
                Text("Each one shows up once for \(person.name). Copy it, change it, make it yours.").font(.geist(11.5)).foregroundStyle(Color.faint)
            }
            .navigationTitle(person.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
        .onAppear { FriendMessages.fill(for: person.id, language: language, categories: FriendMessages.categories(for: person), in: store) }
    }

    private func row(_ s: FriendSuggestion) -> some View {
        let text = FriendMessages.text(s, personId: person.id, name: person.name)
        return Card {
            Text(text).font(.geist(14)).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("friend.suggestion")
            HStack(spacing: 14) {
                Button {
                    UIPasteboard.general.string = text
                    copied = s.id
                    FriendMessages.markUsed(s, for: person.id, in: store)
                } label: {
                    Label(copied == s.id ? "Copied" : "Copy", systemImage: copied == s.id ? "checkmark" : "doc.on.doc").font(.geist(12.5, .semibold))
                }
                .accessibilityIdentifier("friend.copy")
                ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up").font(.geist(12.5, .semibold)) }
                    .simultaneousGesture(TapGesture().onEnded { FriendMessages.markUsed(s, for: person.id, in: store) })
                    .accessibilityIdentifier("friend.share")
                Spacer()
            }
            .tint(accent)
        }
    }

    private func choose(_ language: FriendLanguage) {
        FriendMessages.setLanguage(language, for: person.id, in: store)
        FriendMessages.fill(for: person.id, language: language, categories: FriendMessages.categories(for: person), in: store)
    }
}

// MARK: - The parts, European Portuguese

/// Casual pt-PT with "tu". Nothing about the sender's gender, since these get sent as they are.
enum FriendLinesPT {
    static let openers: [String] = [
        "Olá, {name}, tudo bem?", "Olá, {name}!", "Ei, {name}!", "Boas, {name}!", "Então, {name}, tudo bem?",
        "Então, {name}, como vai isso?", "Ora viva, {name}!", "Viva, {name}!", "Como estás, {name}?", "Como vais, {name}?"
    ]
    static let closers: [String] = [
        "Um abraço!", "Abraço grande!", "Fica bem!", "Dá notícias!", "Até breve!", "Cuida-te!",
        "Sem pressa para responder.", "Responde quando puderes.", "Diz coisas!"
    ]

    static let checkIn = PhrasePool(openers: openers, bodies: [
        "Lembrei-me de ti e decidi mandar mensagem.",
        "Só queria saber como estás.",
        "Como tens andado?",
        "Como vão as coisas por aí?",
        "Há novidades por aí?",
        "Só a passar para dizer olá.",
        "O que tens feito de bom?",
        "Como tem sido a tua semana?",
        "Anda tudo a correr bem por aí?",
        "Estava aqui a pensar em ti e achei que devia dizer alguma coisa.",
        "Não tenho nada de especial para dizer, só queria saber de ti.",
        "Como vai a vida?",
        "Como te tens aguentado?",
        "Apeteceu-me saber de ti.",
        "Dá-me um resumo da tua vida, pode ser em três linhas.",
        "Como correu o teu dia?",
        "Diz-me só que anda tudo como deve ser.",
        "Tens estado bem?",
        "Tens tido tempo para ti?",
        "Que tal tem sido este mês?",
        "Por aqui vai andando, e por aí?",
        "Por aqui anda tudo calmo. E contigo?",
        "Queria só saber se andas bem.",
        "Vim só cuscar como estás."
    ], closers: closers)

    static let beenAWhile = PhrasePool(openers: openers, bodies: [
        "Há quanto tempo!",
        "Já não falamos há imenso tempo.",
        "Já passou tempo demais desde a última vez que falámos.",
        "Tenho saudades de falar contigo.",
        "Reparei que já não falávamos há uma eternidade.",
        "Passou demasiado tempo, e a culpa é minha.",
        "Sei que tenho andado longe.",
        "Peço desculpa por este silêncio.",
        "Este silêncio já durou demais.",
        "Não sei como passou tanto tempo.",
        "Pareceu-me que já era altura de dar sinal de vida.",
        "Aqui estou eu a dar sinal de vida.",
        "Temos de pôr a conversa em dia.",
        "Temos muita conversa para pôr em dia.",
        "Há tanto tempo que não sei nada de ti.",
        "Perdi-te o rasto e não gosto nada disso.",
        "Vi a nossa última conversa e assustei-me com a data.",
        "O tempo passa demasiado depressa, não é?",
        "Antes tarde do que nunca, certo?",
        "Ainda te lembras de mim?",
        "Já lá vão uns bons meses, acho eu.",
        "Faz-me falta falar contigo.",
        "Que é feito de ti?",
        "Por onde tens andado?"
    ], closers: closers)

    static let plan = PhrasePool(openers: openers, bodies: [
        "Vamos tomar um café um dia destes?",
        "Tens tempo para um café esta semana?",
        "Vamos combinar um jantar?",
        "Que tal um almoço para a semana?",
        "Temos de combinar alguma coisa.",
        "Estás livre este fim de semana?",
        "Apetece-te dar uma volta um destes dias?",
        "Vamos marcar qualquer coisa antes que passe mais um mês.",
        "Diz-me um dia bom para ti e eu trato do resto.",
        "Vamos beber um copo?",
        "Bora combinar qualquer coisa?",
        "Tens planos para sexta?",
        "Se passares por cá, avisa, que vamos beber um café.",
        "E uma caminhada no domingo?",
        "Que tal um jantar cá em casa?",
        "Queres vir cá um dia destes?",
        "Tenho um fim de semana livre e lembrei-me de ti.",
        "Se quiseres, posso ir ter contigo.",
        "Vamos ver um filme um dia destes?",
        "Arranjamos uma horinha para pôr a conversa em dia?",
        "Podíamos juntar o pessoal outra vez.",
        "Se tiveres uma tarde livre, avisa.",
        "Uma chamada rápida esta semana, que achas?",
        "Escolhe tu o sítio, eu apareço."
    ], closers: closers)

    static let share = PhrasePool(openers: openers, bodies: [
        "Vi uma coisa hoje que me fez lembrar de ti.",
        "Ouvi hoje uma música que me fez pensar em ti.",
        "Passei hoje por um sítio que me lembrou de ti.",
        "Estou a ver uma série que ias adorar.",
        "Li uma coisa de que acho que ias gostar.",
        "Tenho uma história para te contar, vais rir-te.",
        "Aconteceu-me uma coisa hoje a que só tu ias achar piada.",
        "Encontrei uma foto nossa antiga e dei uma gargalhada.",
        "Comi hoje uma coisa que tens mesmo de provar.",
        "Descobri um sítio novo que tens de conhecer.",
        "Lembrei-me hoje daquela vez em que nos rimos até não poder mais.",
        "Tenho uma novidade, mas só conto ao vivo.",
        "Hoje alguém disse uma coisa que só podia ter saído da tua boca.",
        "Vi um livro que tem tudo a ver contigo.",
        "Ouvi uma piada péssima e pensei logo em ti.",
        "Tenho uma recomendação para ti, é só dizeres.",
        "Vi um filme que tens mesmo de ver.",
        "Há um podcast de que acho que ias gostar.",
        "Encontrei uma receita que tem o teu nome.",
        "Hoje passou na rádio aquela música, sabes qual.",
        "Tenho de te mostrar uma coisa que encontrei.",
        "Hoje lembrei-me dos nossos tempos.",
        "Tenho uma história ótima da semana passada.",
        "Vi uma coisa tão parva que tive de me lembrar de ti."
    ], closers: closers)

    static let askAbout = PhrasePool(openers: openers, bodies: [
        "Como vai o trabalho?",
        "E a família, está toda bem?",
        "Como correu aquilo de que me falaste?",
        "O que tens andado a ver ou a ler?",
        "O que tens feito ao fim de semana?",
        "Já foste de férias este ano?",
        "Tens viagens à vista?",
        "Qual foi a melhor coisa que te aconteceu este mês?",
        "O que te tem dado mais alegrias ultimamente?",
        "O que anda a ocupar-te a cabeça?",
        "Alguma novidade lá no trabalho?",
        "Tens algum plano para os próximos tempos?",
        "Ainda continuas com aquele projeto?",
        "Como vão os teus?",
        "Há música nova que me recomendes?",
        "Que série estás a ver agora?",
        "Tens feito desporto?",
        "Tens conseguido descansar?",
        "Como anda a tua cabeça, está tudo tranquilo?",
        "Qual é a tua grande novidade?",
        "O que anda a fazer-te rir?",
        "Conta-me uma coisa boa da tua semana.",
        "Conta-me o que tens feito.",
        "O que é que te apetece fazer nos próximos tempos?"
    ], closers: closers)

    /// Written to work a few days before or after the date, since that's when these are offered
    static let birthday = PhrasePool(openers: openers, bodies: [
        "Anda por aí uma data importante, não anda?",
        "Por esta altura do ano lembro-me sempre de ti.",
        "Mais um ano, é isso?",
        "Não me esqueci do teu aniversário.",
        "O teu aniversário anda aqui perto e eu sei.",
        "Aniversário à porta ou acabadinho de passar, merece um brinde na mesma.",
        "Temos de festejar o teu aniversário como deve ser.",
        "Devo-te um bolo, ou pelo menos uma fatia.",
        "Que tal um café para festejar mais um ano?",
        "Há planos para celebrar?",
        "Como é que se festeja o teu aniversário este ano?",
        "Diz-me que há bolo.",
        "Mais um ano, e cada vez melhor, suponho.",
        "Espero que esta altura do ano te esteja a tratar bem.",
        "Os aniversários são uma boa desculpa para falar contigo.",
        "Tenho um brinde em atraso para ti.",
        "Vamos celebrar, com ou sem velas?",
        "Prometo que não canto os parabéns ao telefone.",
        "Parabéns adiantados ou atrasados, escolhe tu.",
        "Já estou a pensar no que te oferecer.",
        "Diz-me o que queres de presente, sem exageros.",
        "Esta semana pede um brinde em tua honra.",
        "Quantas velas são, afinal? Podes mentir.",
        "Mereces um dia bom esta semana, com bolo incluído."
    ], closers: closers)

    static let encouragement = PhrasePool(openers: openers, bodies: [
        "Só para dizer que estou a torcer por ti.",
        "Sei que tens tido muita coisa em cima. Força!",
        "Se precisares de alguma coisa, estou aqui.",
        "Tenho muito orgulho em ti.",
        "Tu consegues, nunca tive dúvidas.",
        "Estou aqui para o que precisares.",
        "Sempre que precisares de desabafar, é só dizer.",
        "Não te esqueças do quanto já conseguiste.",
        "És das pessoas mais fortes que conheço.",
        "Acredito mesmo em ti.",
        "Força nisso, vai correr bem.",
        "Um dia de cada vez, que isso passa.",
        "Se o dia estiver a ser difícil, lembra-te de que tens aqui alguém.",
        "Lembrei-me de ti e quis mandar-te boa energia.",
        "Tens feito um trabalho incrível com tudo.",
        "Vou estar a pensar em ti.",
        "Só queria que soubesses que estou aqui.",
        "Tens-te saído muito bem, mesmo que não pareça.",
        "Não tens de fazer tudo por tua conta.",
        "Merecias ouvir isto mais vezes: és uma pessoa incrível.",
        "Se quiseres companhia, é só dizer.",
        "Estou contente por te ter na minha vida.",
        "Vai correr tudo bem, e se não correr, pago eu o café.",
        "Conta comigo, para o que der e vier."
    ], closers: closers)
}

// MARK: - The parts, English

enum FriendLinesEN {
    static let openers: [String] = [
        "Hey {name}!", "Hi {name}!", "Hello {name}!", "Hiya {name}!", "Hey there {name}!",
        "Hey {name}, how are you?", "Hi {name}, how's it going?", "How are you, {name}?", "What's up, {name}?", "How's life, {name}?"
    ]
    static let closers: [String] = [
        "Take care!", "Big hug!", "Talk soon!", "Speak soon!", "Hope you're well!", "Let me know how you are.",
        "No rush to reply.", "Reply whenever you can.", "Say hi to everyone for me."
    ]

    static let checkIn = PhrasePool(openers: openers, bodies: [
        "You crossed my mind, so I thought I'd send a message.",
        "Just wanted to see how you're doing.",
        "How have you been?",
        "How are things over there?",
        "Any news on your side?",
        "Just stopping by to say hello.",
        "What have you been up to?",
        "How's your week been?",
        "Is everything going well over there?",
        "I was thinking about you and figured I should say something.",
        "Nothing special to report, I just wanted to hear from you.",
        "How's everything going?",
        "How are you holding up?",
        "I felt like checking in on you.",
        "Give me a summary of your life, three lines is fine.",
        "How did your day go?",
        "Just tell me all is as it should be.",
        "Have you been keeping well?",
        "Have you had any time for yourself lately?",
        "How has this month been treating you?",
        "Things are ticking along here. How about you?",
        "All quiet on my side. What about yours?",
        "Just wanted to make sure you're good.",
        "I'm only here to be nosy about how you are."
    ], closers: closers)

    static let beenAWhile = PhrasePool(openers: openers, bodies: [
        "It's been ages!",
        "We haven't talked in forever.",
        "It's been far too long since we last talked.",
        "I miss talking to you.",
        "I just noticed it's been an eternity since we spoke.",
        "Too much time has gone by, and that's on me.",
        "I know I've been a bit far away.",
        "Sorry about the long silence.",
        "This silence has gone on long enough.",
        "I don't know how so much time went by.",
        "It seemed about time I showed some signs of life.",
        "Here I am, showing signs of life.",
        "We really need to catch up.",
        "We've got so much catching up to do.",
        "It's been so long since I've heard anything from you.",
        "I've lost track of you, and I don't like it.",
        "I saw our last chat and the date scared me.",
        "Time goes way too fast, doesn't it?",
        "Better late than never, right?",
        "Do you still remember me?",
        "It's been a good few months, I think.",
        "I've missed our chats.",
        "What's become of you?",
        "Where have you been hiding?"
    ], closers: closers)

    static let plan = PhrasePool(openers: openers, bodies: [
        "Shall we get a coffee one of these days?",
        "Do you have time for a coffee this week?",
        "Let's plan a dinner?",
        "How about lunch next week?",
        "We should make a plan.",
        "Are you free this weekend?",
        "Fancy going for a walk sometime soon?",
        "Let's book something before another month goes by.",
        "Tell me a day that works and I'll sort out the rest.",
        "Shall we go for a drink?",
        "Want to put something in the calendar?",
        "Any plans for Friday?",
        "If you're ever around, let me know and we'll get a coffee.",
        "What about a walk on Sunday?",
        "How about dinner at my place?",
        "Want to come over one of these days?",
        "I've got a free weekend and I thought of you.",
        "If you like, I can come to you.",
        "Shall we see a film sometime?",
        "Can we find an hour to catch up?",
        "We could get the group together again.",
        "If you get a free afternoon, tell me.",
        "A quick call this week, what do you think?",
        "You pick the place, I'll turn up."
    ], closers: closers)

    static let share = PhrasePool(openers: openers, bodies: [
        "I saw something today that reminded me of you.",
        "I heard a song today that made me think of you.",
        "I walked past a place today that reminded me of you.",
        "I'm watching a series you'd love.",
        "I read something I think you'd like.",
        "I've got a story for you, you'll laugh.",
        "Something happened today that only you would find funny.",
        "I found an old photo of us and burst out laughing.",
        "I ate something today that you absolutely have to try.",
        "I found a new place you need to see.",
        "I remembered that time we couldn't stop laughing.",
        "I have some news, but I'm only telling it in person.",
        "Someone said something today that could only have come from you.",
        "I saw a book that has your name all over it.",
        "I heard a terrible joke and immediately thought of you.",
        "I have a recommendation for you, just say the word.",
        "I saw a film you really have to watch.",
        "There's a podcast I think you'd like.",
        "I found a recipe that has your name on it.",
        "That song came on the radio today, you know the one.",
        "I need to show you something I found.",
        "Today I got a bit nostalgic about the old days.",
        "I have a great story from last week.",
        "I saw something so silly that I had to think of you."
    ], closers: closers)

    static let askAbout = PhrasePool(openers: openers, bodies: [
        "How's work going?",
        "How's the family doing?",
        "How did that thing you told me about go?",
        "What have you been watching or reading?",
        "What have you been doing with your weekends?",
        "Have you been on holiday this year?",
        "Any trips coming up?",
        "What's the best thing that's happened to you this month?",
        "What's been making you happy lately?",
        "What's been on your mind?",
        "Any news at work?",
        "Do you have anything planned for the coming months?",
        "Are you still working on that project?",
        "How are your people?",
        "Any new music you'd recommend?",
        "What series are you watching right now?",
        "Have you been doing any sport?",
        "Have you been getting some rest?",
        "How's your head, all calm in there?",
        "What's your big news?",
        "What's been making you laugh?",
        "Tell me one good thing from your week.",
        "Tell me what you've been up to.",
        "What do you feel like doing next?"
    ], closers: closers)

    /// Written to work a few days before or after the date, since that's when these are offered
    static let birthday = PhrasePool(openers: openers, bodies: [
        "There's an important date around here somewhere, isn't there?",
        "I always think of you around this time of year.",
        "Another year, is that right?",
        "I haven't forgotten your birthday.",
        "Your birthday's right around here, and I know it.",
        "Birthday coming up or just gone, it deserves a toast either way.",
        "We have to celebrate your birthday properly.",
        "I owe you a cake, or at least a slice.",
        "How about a coffee to celebrate another year?",
        "Any plans to celebrate?",
        "How are we celebrating your birthday this year?",
        "Tell me there's cake.",
        "Another year, and better every time, I assume.",
        "I hope this time of year is treating you well.",
        "Birthdays are a good excuse to talk to you.",
        "I owe you a toast.",
        "Shall we celebrate, with or without candles?",
        "I promise not to sing over the phone.",
        "Happy early or belated birthday, you choose.",
        "I'm already thinking about what to get you.",
        "Tell me what you want as a present, within reason.",
        "This week calls for a toast in your honour.",
        "How many candles is it now? You may lie.",
        "You deserve a good day this week, cake included."
    ], closers: closers)

    static let encouragement = PhrasePool(openers: openers, bodies: [
        "Just to say I'm rooting for you.",
        "I know you've had a lot on your plate. Hang in there!",
        "If you need anything, I'm here.",
        "I'm really proud of you.",
        "You've got this, I never doubted it.",
        "I'm here for whatever you need.",
        "Whenever you need to vent, just say so.",
        "Don't forget how much you've already pulled off.",
        "You're one of the strongest people I know.",
        "I really do believe in you.",
        "Keep at it, it's going to go well.",
        "One day at a time, this will pass.",
        "If today's a hard one, remember you've got someone here.",
        "You came to mind and I wanted to send some good energy.",
        "You've been doing an incredible job with everything.",
        "I'll be thinking of you.",
        "I just wanted you to know I'm here.",
        "You've been doing really well, even if it doesn't feel that way.",
        "You don't have to do it all on your own.",
        "You should hear this more often: you're an amazing person.",
        "If you want company, just say so.",
        "I'm glad you're in my life.",
        "It'll all go fine, and if it doesn't, the coffee's on me.",
        "Count on me, come what may."
    ], closers: closers)
}
