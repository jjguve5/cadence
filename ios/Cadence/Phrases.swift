// Pip's voice. Lines are composed: an optional opener, a body and an optional closer, all hand-written so any opener
// works with any body and any closer. Nothing is built up front: a line is worked out from its number when needed.
// A per-install shuffle walks each situation's pool once, so a line can't come back until the pool has run out, and
// a body can't come back until every other body of that situation has been used.
import Foundation

// MARK: - Composition

/// Parts of one situation. Shared with the friend suggestions (FriendMessages.swift).
struct PhrasePool: Sendable {
    let openers: [String]
    let bodies: [String]
    let closers: [String]

    /// "No opener" and "no closer" count as options, which is also what varies the rhythm of the lines
    var count: Int { (openers.count + 1) * bodies.count * (closers.count + 1) }

    struct Pick: Equatable {
        var opener: String?
        var openerIndex: Int // openers.count when there's no opener
        var body: String
        var closer: String?
        var named: Bool // Pip uses the person's name in this one
    }

    /// The `position`th line of this pool's shuffle. Every position below `count` gives a different pick:
    /// each round uses every body once, and a body meets a different opener and closer pair every round.
    func pick(_ position: Int, seed: UInt64) -> Pick {
        let bodyCount = bodies.count
        let pairs = (openers.count + 1) * (closers.count + 1)
        let at = max(0, position) % count
        let round = at / bodyCount
        let step = at % bodyCount
        let start = Int(seed % UInt64(bodyCount))
        let stride = PhrasePool.coprimeStride(bodyCount, seed: seed >> 8)
        let bodyIndex = (start + step * stride) % bodyCount
        let spread = Int((seed >> 32) % UInt64(pairs)) | 1
        let shift = Int((seed >> 16) % UInt64(pairs))
        let pair = (round + bodyIndex * spread + shift) % pairs
        let openerIndex = pair % (openers.count + 1)
        let closerIndex = pair / (openers.count + 1)
        return Pick(opener: openerIndex < openers.count ? openers[openerIndex] : nil,
                    openerIndex: openerIndex,
                    body: bodies[bodyIndex],
                    closer: closerIndex < closers.count ? closers[closerIndex] : nil,
                    named: (round + bodyIndex) % 5 == 0)
    }

    private static func coprimeStride(_ n: Int, seed: UInt64) -> Int {
        var s = 1 + Int(seed % UInt64(max(1, n - 1)))
        while gcd(s, n) != 1 { s += 1 }
        return s
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a, y = b
        while y != 0 { (x, y) = (y, x % y) }
        return x
    }

    /// A hash that stays the same across launches and devices, unlike `hashValue`
    static func stableHash(_ text: String) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        for byte in text.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        return h
    }
}

// MARK: - Situations

enum PipSituation: String, CaseIterable, Sendable {
    case morning, sleepShort, sleepGood, recoveryLow, recoveryHigh, trainingDone, trainedLowDay, trainingSkipped
    case waterBehind, proteinBehind, fruitGoal, soupGoal, shower, brushing, reading, promisesDone, streak
    case eveningClose, windDown, minimumDayDone, minimumDayOpen, comeback, mustDoOpen, routineLate, goodDay, generic, focusing

    var pool: PhrasePool {
        switch self {
        case .morning: return PipLines.morning
        case .sleepShort: return PipLines.sleepShort
        case .sleepGood: return PipLines.sleepGood
        case .recoveryLow: return PipLines.recoveryLow
        case .recoveryHigh: return PipLines.recoveryHigh
        case .trainingDone: return PipLines.trainingDone
        case .trainedLowDay: return PipLines.trainedLowDay
        case .trainingSkipped: return PipLines.trainingSkipped
        case .waterBehind: return PipLines.waterBehind
        case .proteinBehind: return PipLines.proteinBehind
        case .fruitGoal: return PipLines.fruitGoal
        case .soupGoal: return PipLines.soupGoal
        case .shower: return PipLines.shower
        case .brushing: return PipLines.brushing
        case .reading: return PipLines.reading
        case .promisesDone: return PipLines.promisesDone
        case .streak: return PipLines.streak
        case .eveningClose: return PipLines.eveningClose
        case .windDown: return PipLines.windDown
        case .minimumDayDone: return PipLines.minimumDayDone
        case .minimumDayOpen: return PipLines.minimumDayOpen
        case .comeback: return PipLines.comeback
        case .mustDoOpen: return PipLines.mustDoOpen
        case .routineLate: return PipLines.routineLate
        case .goodDay: return PipLines.goodDay
        case .generic: return PipLines.generic
        case .focusing: return PipLines.focusing
        }
    }
}

// MARK: - What Pip says

enum Pip {
    enum Period { case hour, day }

    private static let seedKey = "pip.seed"
    private static let cursorsKey = "pip.cursors"
    private static let stableKey = "pip.stable"

    /// The next unseen line of a situation. Use it for one-off moments; a view that redraws wants `stable`.
    /// `what` fills {what} and {What}; `lead` is a sentence of facts that goes first and replaces the opener;
    /// `tail` goes last. `maxLength` drops the opener, then the closer, for places that show two lines.
    @MainActor
    static func say(_ situation: PipSituation, store: Store, what: String? = nil, lead: String? = nil, tail: String? = nil, maxLength: Int? = nil) -> String {
        say(situation, name: store.profile.name, what: what, lead: lead, tail: tail, maxLength: maxLength)
    }

    /// The same line for a whole hour or day, so the text doesn't change on every SwiftUI redraw. Writes only to
    /// UserDefaults, never to the store, so calling it while a view draws is safe. `key` keeps separate lines for
    /// separate things in one situation, like two different must-dos.
    @MainActor
    static func stable(_ situation: PipSituation, store: Store, per period: Period = .hour, key: String = "", what: String? = nil, lead: String? = nil, tail: String? = nil, maxLength: Int? = nil) -> String {
        stable(situation, name: store.profile.name, per: period, key: key, what: what, lead: lead, tail: tail, maxLength: maxLength)
    }

    static func say(_ situation: PipSituation, name: String, what: String? = nil, lead: String? = nil, tail: String? = nil, maxLength: Int? = nil, defaults: UserDefaults = .standard) -> String {
        let position = advance(situation, defaults: defaults)
        return line(situation, position: position, seed: seed(situation, defaults: defaults), name: name, what: what, lead: lead, tail: tail, maxLength: maxLength)
    }

    static func stable(_ situation: PipSituation, name: String, per period: Period = .hour, key: String = "", what: String? = nil, lead: String? = nil, tail: String? = nil, maxLength: Int? = nil, defaults: UserDefaults = .standard, now: Date = Date()) -> String {
        let label = periodLabel(period, now: now)
        let slot = situation.rawValue + "|" + key
        var held = defaults.dictionary(forKey: stableKey) as? [String: String] ?? [:]
        let position: Int
        if let entry = held[slot], entry.hasPrefix(label + "="), let kept = Int(entry.dropFirst(label.count + 1)) {
            position = kept
        } else {
            position = advance(situation, defaults: defaults)
            // Entries from an earlier period are never read again
            let hour = periodLabel(.hour, now: now), day = periodLabel(.day, now: now)
            held = held.filter { $0.value.hasPrefix(hour + "=") || $0.value.hasPrefix(day + "=") }
            held[slot] = label + "=\(position)"
            defaults.set(held, forKey: stableKey)
        }
        return line(situation, position: position, seed: seed(situation, defaults: defaults), name: name, what: what, lead: lead, tail: tail, maxLength: maxLength)
    }

    /// Builds one line. No state: the tests use this to count a pool.
    static func line(_ situation: PipSituation, position: Int, seed: UInt64, name: String, what: String? = nil, lead: String? = nil, tail: String? = nil, maxLength: Int? = nil) -> String {
        let pool = situation.pool
        let pick = pool.pick(position, seed: seed)
        let first = name.split(separator: " ").first.map(String.init) ?? ""
        var opener = pick.opener
        if pick.named, !first.isEmpty { opener = PipLines.named[pick.openerIndex].replacingOccurrences(of: "{name}", with: first) }
        if lead != nil { opener = nil }
        var closer = pick.closer
        let fill: (String) -> String = { fillWhat($0, what) }
        func joined() -> String {
            let parts: [String?] = [lead, opener, fill(pick.body), closer.map(fill), tail]
            return parts.compactMap { $0 }.joined(separator: " ")
        }
        if let maxLength {
            if joined().count > maxLength { opener = nil }
            if joined().count > maxLength { closer = nil }
        }
        return joined()
    }

    /// Which situation a routine's title belongs to, for wording that fits it
    static func situation(forTitle title: String, fallback: PipSituation) -> PipSituation {
        let t = title.lowercased()
        if t.contains("brush") || t.contains("teeth") || t.contains("floss") { return .brushing }
        if t.contains("shower") { return .shower }
        if t.contains("read") || t.contains("book") { return .reading }
        return fallback
    }

    private static func fillWhat(_ part: String, _ what: String?) -> String {
        guard part.contains("{") else { return part }
        return part
            .replacingOccurrences(of: "{what}", with: what?.lowercased() ?? "isso")
            .replacingOccurrences(of: "{What}", with: what ?? "Isso")
    }

    private static func periodLabel(_ period: Period, now: Date) -> String {
        let day = Day.key(now)
        switch period {
        case .day: return day
        case .hour: return day + "T\(Day.minuteOfDay(now) / 60)"
        }
    }

    /// Hands out the next position and remembers it. Positions wrap only when the whole pool has been shown.
    private static func advance(_ situation: PipSituation, defaults: UserDefaults) -> Int {
        var cursors = defaults.dictionary(forKey: cursorsKey) as? [String: Int] ?? [:]
        let position = cursors[situation.rawValue] ?? 0
        cursors[situation.rawValue] = (position + 1) % situation.pool.count
        defaults.set(cursors, forKey: cursorsKey)
        return position
    }

    /// One random number per install, mixed with the situation, so the order isn't the same for everyone
    private static func seed(_ situation: PipSituation, defaults: UserDefaults) -> UInt64 {
        var install = defaults.integer(forKey: seedKey)
        if install == 0 {
            install = Int.random(in: 1...Int.max)
            defaults.set(install, forKey: seedKey)
        }
        return PhrasePool.stableHash("\(install)|\(situation.rawValue)")
    }
}

// MARK: - The parts

/// Written by hand. Rules for anyone adding to these: each part is a full sentence or two, makes sense next to any
/// other part of its situation, and has no em dashes, medical claims or guilt.
enum PipLines {
    /// Replaces the opener now and then. One per possible opener index, so using the name can't make two lines equal.
    static let named: [String] = [
        "Olá, {name}.", "Ora bem, {name}.", "Psst, {name}.", "Ouve, {name}.", "Pronto, {name}.", "Então, {name}.",
        "Só uma coisa, {name}.", "Viva, {name}.", "Olha, {name}.", "Ah, {name}.", "Ei, {name}.", "Ora então, {name}."
    ]

    static let morning = PhrasePool(
        openers: ["Bom dia.", "Muito bom dia.", "Já de pé, estou a ver.", "Ah, já cá estás.", "Acabou de chegar mais um dia.", "Ora viva."],
        bodies: [
            "Vamos fazer o dia valer a pena.",
            "Já espreitei o dia de hoje e parece-me que se faz.",
            "O dia de hoje ainda está intacto.",
            "Ainda nada correu mal, o que já é um ótimo começo.",
            "O dia está em aberto. Escolhes tu primeiro.",
            "Eu já acordei há horas. Bem, há um minuto.",
            "Vamos escolher uma coisa e fazê-la como deve ser.",
            "A lista está ali para quando quiseres, sem pressa.",
            "Não tens de ganhar a manhã. Basta apareceres.",
            "Primeiro o café, se é assim que funciona por aqui.",
            "Hoje há espaço de sobra. Vamos usar um bocadinho.",
            "Vamos começar por pouco e ver no que dá.",
            "Tenho um bom pressentimento sobre hoje, e normalmente só me engano em metade.",
            "Uma página em branco, e a caneta está contigo.",
            "Corresse como corresse, ontem já está arquivado.",
            "Vamos repetir o dia. Dizem que da última vez correu bem.",
            "Primeiro o mais importante: acordar. Feito.",
            "Apareceste, por isso o mais difícil já está feito."
        ],
        closers: ["Estou aqui mesmo.", "Com calma.", "Vamos lá.", "Vai à frente.", "Eu vou atrás de ti.", "Vamos ver o que se consegue."]
    )

    static let sleepShort = PhrasePool(
        openers: ["Noite curta.", "Pouco sono, estou a ver.", "Bem, foi uma noite breve.", "A noite foi um bocadinho pequena.", "Bom dia, cara de sono.", "Então a noite soube a pouco."],
        bodies: [
            "Vamos fazer um dia suave.",
            "Fazemos o importante e deixamos os heroísmos para outro dia.",
            "Hoje pode ser um dia mais pequeno. Ninguém está a ver.",
            "Vamos apontar ao suficiente e contar isso como vitória.",
            "Escolhe a coisa que importa e deixa o resto em paz.",
            "Não são precisos grandes planos. Só a próxima coisa pequena.",
            "Hoje vamos a passo.",
            "Deitar cedo hoje à noite é uma ideia que sabe bem.",
            "Hoje também ando devagar, por isso combinamos.",
            "Não te vamos pedir muito antes do almoço.",
            "Mesmo assim, dá para ter um dia perfeitamente decente.",
            "Devagar e sempre já é um plano inteiro para hoje.",
            "Nada disto precisa de ser impressionante.",
            "Vamos baixar a fasquia até se passar por cima dela sem esforço.",
            "São coisas que acontecem. Trabalhamos com o que há.",
            "Então é um dia tranquilo.",
            "Trata-te bem hoje. Eu também te vou tratar bem.",
            "Hoje podemos ir pelo caminho mais bonito."
        ],
        closers: ["Eu mantenho as coisas simples.", "Devagarinho.", "Uma coisa de cada vez.", "Nós damos conta disto, devagar.", "Esta noite há outra oportunidade.", "Da minha parte, zero pressão."]
    )

    static let sleepGood = PhrasePool(
        openers: ["Uma noite completa.", "Sono em dia.", "Olha-me só esse descanso.", "Isso é que foi uma noite.", "Belo sono, esse.", "Dormiste. Como deve ser."],
        bodies: [
            "O dia é teu.",
            "Hoje tens o depósito cheio.",
            "Eu gastava isso em algo que te importe mesmo.",
            "Aquilo que tens adiado, hoje é um bom dia para isso.",
            "A tua cama fez um bom trabalho. Agora é a tua vez.",
            "É deste tipo de começo que eu gosto.",
            "Pareces a postos, e não digo isto por dizer.",
            "Não vamos desperdiçar uma manhã destas.",
            "Hoje dá para um pouco mais do que o costume.",
            "Escolhe algo um pouco ambicioso. Podes dar-te a esse luxo.",
            "Isto impressiona-me, e eu tenho um rebento na cabeça, por isso já vi muita coisa.",
            "É uma coisa feita antes mesmo de te levantares.",
            "Devíamos aproveitar isto enquanto está fresco.",
            "Todos os sistemas parecem estar de bom humor.",
            "É isto que ganhas em apagar as luzes a horas.",
            "Se fosse a ti, gabava-me disto."
        ],
        closers: ["Aproveita.", "Vá, então.", "Muito bem.", "Continua assim.", "Vamos a isso.", "Estou a tomar notas."]
    )

    static let recoveryLow = PhrasePool(
        openers: ["Dia de bateria fraca.", "Os teus números andam tímidos hoje.", "A prontidão está em baixo.", "Hoje vai-se numa mudança mais baixa, acho eu.", "Não é o teu dia mais carregado.", "A pulseira diz para ir com calma."],
        bodies: [
            "Vamos com calma onde der.",
            "Hoje, uma caminhada já é mais do que suficiente.",
            "É um bom dia para fazer menos e fazer bem.",
            "Se treinares, faz uma coisa leve e chama-lhe bom senso.",
            "Não há mal nenhum num dia mais lento, faz parte.",
            "As coisas grandes podem ficar para amanhã.",
            "O trabalho de hoje é sobretudo não exagerar.",
            "Se calhar hoje não é dia para bater recordes.",
            "Ainda dá para fazer coisas, só que com menos drama.",
            "Escolhe a versão fácil do que estiver na lista.",
            "Vamos guardar alguma energia para o resto da semana.",
            "Um pouco de descanso seria tempo bem gasto.",
            "É só a leitura de um dia, não é um veredicto.",
            "Hoje sobe-se um degrau de cada vez.",
            "Fazer as coisas pequenas também conta hoje.",
            "Vamos em ponto morto um bocadinho. É permitido."
        ],
        closers: ["Está tudo bem.", "Amanhã há um número novo.", "Eu também vou devagar.", "Não são precisos heroísmos.", "Ninguém sabe melhor do que tu.", "Com jeitinho."]
    )

    static let recoveryHigh = PhrasePool(
        openers: ["A prontidão está em alta.", "Tudo verde.", "Bateria cheia hoje.", "Bons números esta manhã.", "A pulseira está contente.", "Hoje tens margem."],
        bodies: [
            "Se estavas à espera de um dia para puxar, é hoje.",
            "Um treino mais puxado encaixava bem hoje.",
            "Tens espaço para algo ambicioso.",
            "Hoje dá para mais do que o habitual, se te apetecer.",
            "É um bom dia para escolher a coisa pesada.",
            "Aquilo que tens evitado ficou sem desculpas.",
            "Eu aproveitava antes que passe.",
            "Vamos fazer alguma coisa com isso tudo.",
            "Hoje até dava para uma sessão longa.",
            "A tarefa difícil da lista não vai ter melhor dia.",
            "Considera isto um sinal verde, não uma ordem.",
            "Mereceste um dia assim.",
            "Hoje há capacidade. Gasta um pouco.",
            "O teu eu do futuro vai gostar que aproveites este dia.",
            "Eu começava pela coisa mais difícil e depois passava às mais fáceis.",
            "Hoje nada te trava, tanto quanto vejo."
        ],
        closers: ["Diverte-te.", "Vai a isso.", "Eu faço a claque.", "A decisão é tua, claro.", "Aproveita bem.", "Quero ver isso."]
    )

    static let trainingDone = PhrasePool(
        openers: ["Treino feito.", "Sessão garantida.", "Treinaste.", "Treino despachado.", "Bela sessão.", "Olha quem se mexeu hoje."],
        bodies: [
            "Isso já ninguém te tira.",
            "Podes ficar contente contigo durante um bocado.",
            "Era a parte difícil do dia, e já ficou para trás.",
            "Agora é altura de comida e de um bocadinho de descanso.",
            "Tudo o resto hoje é bónus.",
            "Vi tudo do princípio ao fim e preciso de uma sesta.",
            "O teu eu de amanhã fica a dever-te um obrigado.",
            "É assim que isto funciona. Uma sessão de cada vez.",
            "Ainda bem que o fizeste, custasse o que custasse.",
            "O sofá já foi avisado de que o mereceste.",
            "Bom trabalho. Batia palmas, mas as minhas patas são muito pequenas.",
            "Nem toda a gente fez isso hoje. Tu fizeste.",
            "É mais um para a pilha, e a pilha está a crescer.",
            "Disseste que ias fazer e fizeste. Raro e excelente.",
            "Hora de comer qualquer coisa e de te gabares um bocadinho.",
            "Isto conta hoje, e vai continuar a contar no mês que vem."
        ],
        closers: ["Muito bem.", "Tenho orgulho em ti.", "Descansa bem.", "Aproveita a sensação.", "Até à próxima.", "É assim mesmo."]
    )

    static let trainedLowDay = PhrasePool(
        openers: ["Treinaste num dia em baixo.", "Um dia fraco, e mesmo assim treinaste.", "Números baixos, e foste na mesma.", "No papel não era o teu melhor dia, e treinaste à mesma.", "Foste mesmo num dia mais parado.", "Prontidão baixa, sessão feita."],
        bodies: [
            "Aparecer conta.",
            "Isso tem mérito, e eu reparei.",
            "São essas as sessões que constroem o hábito.",
            "Não tem de ser o teu melhor para valer a pena.",
            "Já fizeste bastante, agora podes não fazer nada, à vontade.",
            "É o tipo de coisa que eu punha num troféu pequenino.",
            "Calma para o resto do dia, diria eu.",
            "Treino suave num dia suave, é mesmo isso.",
            "O resto do dia pode ser levezinho.",
            "Os dias bons são fáceis. Este foi do outro tipo.",
            "A consistência é muito parecida com isto.",
            "No meu livro, este conta a dobrar, e o livro é meu."
        ],
        closers: ["Boa.", "Eu vi.", "Agora descansa.", "Respeito.", "Bem jogado.", "Agora põe os pés para cima."]
    )

    static let trainingSkipped = PhrasePool(
        openers: ["Hoje não há treino.", "Então saltamos a sessão.", "Dia de descanso, então.", "O treino ficou de fora.", "Sessão saltada, anotado.", "O treino de hoje foi cancelado."],
        bodies: [
            "É permitido. Vai continuar lá para a próxima.",
            "Uma sessão não muda quase nada.",
            "Conheces o teu dia melhor do que eu.",
            "Vamos aproveitar o tempo extra e voltar à carga na próxima.",
            "Uma caminhada sabia bem, se te apetecer. Se não, também está bem.",
            "Seguimos em frente. Sem drama.",
            "Os pesos não vão levar a mal.",
            "Ainda falta muita semana.",
            "Às vezes é a decisão certa.",
            "Não estou a contar pontos nesta. Bem, a app está, mas com carinho.",
            "Encontramos o próximo horário livre e ficamos por aí.",
            "É mais tempo para o resto da tua vida.",
            "É um dia, e tens muitos desses.",
            "Amanhã continua a ter o teu nome.",
            "Nada se perdeu que não se possa recuperar depois.",
            "Chamamos-lhe descanso planeado e seguimos."
        ],
        closers: ["Tudo bem.", "Não é grave.", "Próximo assunto.", "Fica para a próxima.", "Por mim, está ótimo.", "Continua."]
    )

    static let waterBehind = PhrasePool(
        openers: ["Ponto da situação: água.", "Uma palavra sobre a água.", "A água está um pouco atrasada.", "Isto está a ficar um bocadinho seco por aqui.", "Psst, água.", "Estado do copo: quase vazio."],
        bodies: [
            "Um copo grande agora põe-te de novo no ritmo.",
            "Podes beber um copo, só para me fazeres a vontade?",
            "A torneira está mesmo ali e tem um preço muito simpático.",
            "Um copo grande e deixo de falar nisto.",
            "Vá, bebe um copo bem cheio.",
            "A tua garrafa parece tão sozinha.",
            "Vamos recuperar com um copo ou dois.",
            "Tenho um rebento na cabeça, por isso penso muito em água.",
            "Considera isto um toquezinho no ombro por causa da água.",
            "Uns goles grandes e já contamos como progresso.",
            "Enche um copo da próxima vez que passares pela cozinha.",
            "É a coisa mais fácil da lista, e está na lista.",
            "A água não se bebe sozinha. Já a vi tentar.",
            "Mais um copo e ficas em dia.",
            "Se calhar põe um copo na secretária, onde o vejas.",
            "Só um copo. Não estou a pedir uma piscina.",
            "Bebe um pouco de água, tens tido muito que fazer.",
            "O próximo copo é por conta da casa."
        ],
        closers: ["Saúde.", "Obrigado.", "É tudo da minha parte.", "Eu fico de olho, com carinho.", "À tua.", "Sem pressa, mas em breve."]
    )

    static let proteinBehind = PhrasePool(
        openers: ["Ponto da situação: proteína.", "Um recado da cozinha.", "Sobre a proteína.", "Ideia para o jantar.", "Assunto: comida.", "Quanto à proteína."],
        bodies: [
            "Um batido ou uma dose do frigorífico resolve a maior parte.",
            "Algo com ovos ou frango resolvia isto.",
            "O jantar pode fazer a maior parte do trabalho.",
            "Um iogurte ou uma lata de atum já fazia boa diferença.",
            "Ainda há tempo, e ainda há comida.",
            "Que a próxima coisa que comeres conte um bocadinho mais.",
            "Está mais perto do que parece. Uma dose a sério faz muito.",
            "Uma boa colherada de algo rico em proteína, talvez?",
            "Espreita o frigorífico. Pode surpreender-te.",
            "Uma fácil: um batido, e estás quase lá.",
            "Um lanche com alguma substância ajudava.",
            "A sobremesa podia ser um iogurte, numa jogada esperta.",
            "Não precisa de ser perfeito, só um pouco mais perto.",
            "Não tens de chegar ao fim, basta dar-lhe um empurrãozinho.",
            "O queijo cottage existe, e é só isso que digo.",
            "Isto resolve-se a comer, que é o melhor tipo de problema."
        ],
        closers: ["Aproveita.", "É só uma ideia.", "Tu decides.", "Bom apetite.", "Fico por aqui.", "Falta pouco."]
    )

    static let fruitGoal = PhrasePool(
        openers: ["Ponto da situação: fruta.", "Pelas minhas contas, ainda não houve fruta.", "Um recado da fruteira.", "Sobre a fruta.", "Pensamento do dia: fruta.", "Foi a fruteira que me mandou."],
        bodies: [
            "Uma maçã ficava mesmo bem.",
            "Uma banana leva dez segundos e nenhum talento.",
            "Come uma laranja. Está praticamente descascada. Não está, mas vá lá.",
            "Uma peça e a fruta de hoje está resolvida.",
            "Algo doce e vindo de uma árvore, talvez?",
            "Uma pera depois do almoço seria um toque civilizado.",
            "Apanha uma de passagem, nem precisas de parar.",
            "A fruta conta como lanche e como pequena vitória.",
            "O que estiver da época e tiver ar simpático.",
            "As uvas também contam, e não é preciso descascar.",
            "É o objetivo mais fácil do quadro, e o mais saboroso.",
            "Põe uma na secretária e deixa-te tentar.",
            "Sobremesa resolvida, se pensares bem.",
            "Vamos comer uma antes que o dia fuja.",
            "Aquela fruteira não é só decoração.",
            "Um pouco de fruta sabia bem agora, não sabia?"
        ],
        closers: ["Esta é fácil.", "Aproveita.", "É tudo o que tenho.", "Nham.", "Sem descascar. Às vezes.", "Força."]
    )

    static let soupGoal = PhrasePool(
        openers: ["Ponto da situação: sopa.", "Uma palavra sobre sopa.", "Já houve sopa hoje?", "Pensamento sobre sopa.", "Assunto muito sério de sopa.", "A questão da sopa."],
        bodies: [
            "Um prato ao almoço ou ao jantar resolvia.",
            "Um bom prato de sopa e o objetivo está cumprido.",
            "Legumes na sua versão mais simpática.",
            "Quente, fácil e praticamente uma tradição.",
            "Só precisa de um prato e de uma colher, e tu tens os dois.",
            "Começa o jantar com um prato de sopa e está resolvido.",
            "Se houver alguma no frigorífico, chegou a hora dela.",
            "Uma panela dá para vários dias.",
            "Um caldo verde contava, e eu ficava com inveja.",
            "A sopa é só uma refeição a ser simpática contigo.",
            "Serve qualquer coisa com legumes e uma colher.",
            "A tua avó aprovava este lembrete.",
            "Um prato pequeno também conta. Fui ver.",
            "Dava para aquecer uma no tempo que levaste a ler isto.",
            "Vamos a uma antes que a hora de deitar chegue de mansinho.",
            "É difícil estar de mau humor com uma tigela de sopa nas mãos."
        ],
        closers: ["Que bom.", "Colher a postos.", "Bom proveito.", "Guarda-me uma colherada.", "É só isto que tenho a dizer.", "Calorosos cumprimentos."]
    )

    static let shower = PhrasePool(
        openers: ["Pensamento de duche.", "Sobre aquele duche.", "O duche está livre, já agora.", "A casa de banho está à tua espera.", "Uma pequena sugestão.", "Hora do duche, mais ou menos."],
        bodies: [
            "Uns minutos de água quente e o dia fica arrumado.",
            "É uma boa forma de pôr um ponto final no dia.",
            "Vais sentir-te outra pessoa, ou pelo menos uma mais limpa.",
            "Também é um bom sítio para ter ideias.",
            "Cinco minutos e está feito por hoje.",
            "Água quente, sem telemóvel, um negócio excelente.",
            "Canta qualquer coisa. Eu não conto a ninguém.",
            "Agora podia ser uma boa altura, antes que a noite fuja.",
            "Dava para encaixar um antes de te instalares no sofá.",
            "É melhor do que fazê-lo meio a dormir.",
            "A água está pronta quando tu quiseres.",
            "Considera-o umas férias muito curtas.",
            "É das vitórias mais fáceis que há.",
            "Toalha, água, feito. Três passos.",
            "Se hoje já for tarde, amanhã de manhã também serve.",
            "Leva menos tempo do que decidir se vale a pena."
        ],
        closers: ["Aproveita.", "Sem pressa.", "É só uma ideia.", "Depois agradeces-me.", "Eu espero aqui.", "Vai lá."]
    )

    static let brushing = PhrasePool(
        openers: ["Dentes.", "Hora de lavar os dentes.", "Uma nota sobre os teus dentes.", "A escova de dentes está a chamar.", "Uma coisa pequena.", "Boletim dentário rápido."],
        bodies: [
            "Dois minutos e não precisas de voltar a pensar nisso hoje.",
            "A tua escova está ali de pé o dia todo, à espera.",
            "Já sabes como isto funciona.",
            "Dois minutos, mais uma dancinha se quiseres.",
            "É a tarefa mais curta da lista.",
            "Os teus dentes pediram-me para falar nisto.",
            "Põe uma música e acabas antes de ela terminar.",
            "É rápido, e depois voltas ao que estavas a fazer.",
            "Nunca ninguém se arrependeu desta.",
            "Consegues fazer isto de olhos fechados. Experimenta.",
            "É uma tarefa pequenina com final a menta.",
            "Pega na escova quando passares por lá.",
            "Conselho dentário do Pip: sim.",
            "O telemóvel fica para depois. Escovar e fazer scroll não dá. Ou dá?",
            "Casa de banho, escova, feito, liberdade.",
            "É coisa tão pequena que dá para fazer já."
        ],
        closers: ["Sabor a menta.", "É só isto.", "Já está quase.", "Vai lá.", "O teu sorriso agradece.", "Vitória fácil."]
    )

    static let reading = PhrasePool(
        openers: ["Hora do livro.", "O teu livro ligou.", "Uma ideia sobre o teu livro.", "O cantinho da leitura está aberto.", "O livro tem perguntado por ti.", "Na mesa de cabeceira."],
        bodies: [
            "Dez páginas chegavam.",
            "Umas páginas contam. Contam sempre.",
            "Deve ser melhor do que o que está no telemóvel.",
            "Descobre o que acontece a seguir. Eu também quero saber.",
            "Só um capítulo, e estou a falar a sério, acho eu.",
            "Telemóvel em baixo, livro na mão.",
            "Deixaste alguém a meio de uma frase.",
            "Vinte minutos, e podes dizer que leste hoje.",
            "A história não saiu do sítio desde que a deixaste.",
            "Uma página chega para começar.",
            "É uma maneira muito barata de ir a outro sítio.",
            "Adormeces a saber mais, é esse o meu argumento todo.",
            "Está mesmo onde o deixaste, sem julgar nada.",
            "Uma cadeira confortável e umas páginas parecem-me bem.",
            "Lê até os olhos pedirem para parar.",
            "Não precisas de o acabar, só de o visitar."
        ],
        closers: ["Aproveita.", "Eu não faço barulho.", "Boas leituras.", "Depois conta-me como acaba.", "Vai lá.", "Os livros são boa companhia."]
    )

    static let promisesDone = PhrasePool(
        openers: ["Tudo feito.", "É tudo.", "A lista está vazia.", "Tudo despachado por hoje.", "Fizeste tudo.", "Já não sobra nada no quadro."],
        bodies: [
            "Tenho orgulho em ti.",
            "Estou a fazer uma dancinha por causa disso.",
            "Agora podes parar. É mesmo uma opção.",
            "O resto do dia é pura decoração.",
            "É assim que fica quando cumpres a tua palavra.",
            "Fiquei sem coisas para te chatear.",
            "Disseste que fazias, e fizeste. Comportamento exemplar.",
            "Hora de fazer uma coisa completamente inútil. Mereceste.",
            "Sinceramente, nada mal.",
            "Hoje facilitaste-me muito o trabalho.",
            "Tudo, e num dia normal.",
            "Este é o lado bom de não haver nada para fazer.",
            "A tua versão de hoje está imparável.",
            "Dava-te uma medalha, mas preciso dela para o meu roupeiro.",
            "Agora vai e aproveita ser alguém sem nada para fazer.",
            "Quase me deixaste sem palavras."
        ],
        closers: ["Muito bem.", "Vai descansar.", "Belo trabalho.", "Isto é que é um bom dia.", "Aproveita o fim do dia.", "Obrigado por isso."]
    )

    static let streak = PhrasePool(
        openers: ["Olha-me isto.", "Ora, ora.", "Que belo embalo.", "Continua assim e eu ainda me emociono.", "Tenho andado a contar.", "Reparei."],
        bodies: [
            "É assim que os hábitos pegam.",
            "Isto já não é sorte. És mesmo tu.",
            "Fazes isto parecer fácil, e eu sei que não é.",
            "Mais um bocadinho disto e já nem vais ter de pensar nisso.",
            "Coisas pequenas, repetidas vezes sem conta. Tudo soma.",
            "Esta é a parte aborrecida que faz tudo funcionar.",
            "Que fique registado que nunca duvidei de ti.",
            "Estás a tornar-te alguém que faz isto.",
            "Aos poucos, isto está a tornar-se uma coisa tua.",
            "A maioria das pessoas fala disto. Tu continuas a fazê-lo.",
            "Não olhes para baixo, é sempre a andar.",
            "Esse número chegou lá um dia normal de cada vez.",
            "Trabalho muito constante. Gosto de constância.",
            "Não tem de ser perfeito para seguir em frente, e está a seguir.",
            "Construíste aqui uma coisa, e está cada vez mais sólida.",
            "Se um dia falhar, seguimos na mesma. Mas olha-me só para isto."
        ],
        closers: ["Boa.", "Segue assim.", "Impressionante.", "Em frente.", "É assim mesmo.", "Que bom."]
    )

    static let eveningClose = PhrasePool(
        openers: ["Fim do dia.", "Reta final.", "O dia está a acabar.", "Está quase na hora de dar o dia por terminado.", "Foi isto o dia de hoje.", "Ora boa noite."],
        bodies: [
            "Fecha o dia quando quiseres. Demora um minuto.",
            "Conta-me como correu. Fiquei a pensar nisso.",
            "Um minuto para arrumar o dia como deve ser?",
            "Dá uma nota ao dia e escolhe as três prioridades de amanhã. Depois ficas livre.",
            "Vamos apontar o que aconteceu e ficamos por aí.",
            "Fosse como fosse, o dia de hoje já dá para fechar.",
            "Hora de pôr a tampa no dia.",
            "Sabe bem acabar um dia de propósito.",
            "Vamos arrumar o dia e deixar um bilhete ao de amanhã.",
            "Uma olhadela para trás, e depois não se pensa mais nisso.",
            "As três prioridades de amanhã escolhem-se melhor hoje à noite.",
            "Os dias bons e os dias estranhos fecham-se da mesma maneira.",
            "O dia está feito. Só falta dizê-lo.",
            "Não é preciso escrever um texto. Bastam uns toques.",
            "Eu trato da pontuação. Tu só me dizes como te soube.",
            "Diz-me uma coisa boa, se tiver havido alguma."
        ],
        closers: ["Depois descansa.", "Estou a ouvir.", "Sem pressa.", "Depois é hora de sofá.", "Está quase.", "A cama já não tarda."]
    )

    static let windDown = PhrasePool(
        openers: ["Hora de desacelerar.", "Está a ficar tarde.", "Hora de começar a abrandar.", "O serão está quase no fim.", "O dia está a fechar a loja.", "Chegou a hora do sono."],
        bodies: [
            "Ecrãs de lado, livro na mão.",
            "Ecrãs de lado, luzes baixas.",
            "O amanhã pode esperar até amanhã.",
            "Luz fraca, pés para cima.",
            "O que sobrar pode ir para a lista de amanhã.",
            "Já estou a bocejar, e o meu rebento está a murchar.",
            "Um livro e um candeeiro fraquinho sabem mesmo bem agora.",
            "O teu telemóvel sobrevive sem ti durante um bocado.",
            "Esta é a parte em que já não tem de acontecer mais nada.",
            "Vamos começar a aterragem.",
            "Dentes, almofada, o caminho do costume.",
            "Hora de deixar de ser útil por hoje.",
            "A internet ainda vai lá estar de manhã. É pena, a sério.",
            "Pôr-te confortável é a única tarefa que falta.",
            "Vamos baixar o ritmo mais um pouco.",
            "Agora estás de folga."
        ],
        closers: ["Boa noite daqui a pouco.", "O sono vem a caminho.", "Até amanhã.", "Eu também já me vou deitar.", "Bons sonhos, quase.", "Toca a ir para a cama."]
    )

    static let minimumDayDone = PhrasePool(
        openers: ["Dia leve.", "O essencial está feito.", "Dia mínimo, feito.", "Foi esta a lista curta de hoje.", "Dia fácil, terminado.", "A lista pequena está vazia."],
        bodies: [
            "Já é um dia completo.",
            "O dia de hoje não precisava de ser mais do que isto.",
            "Não é preciso mais nada. Fui confirmar.",
            "As regras de hoje dizem que ganhaste.",
            "Fizeste o que o dia pedia. Podes parar aí, se quiseres.",
            "Um dia pequeno bem feito é um bom dia.",
            "Agora podes descansar, e isso conta como cumprir o plano.",
            "O resto é opcional, e digo isto a sério.",
            "Tudo o resto pode esperar por um dia maior.",
            "Era esse o acordo, e cumpriste-o.",
            "Os dias pequenos é que tornam os grandes possíveis.",
            "Agora faz o menos que puderes.",
            "Hoje não são precisos pontos extra.",
            "Não deixaste o fio partir-se, e é esse o objetivo de hoje.",
            "Acabou o expediente, oficialmente.",
            "Eu chamava-lhe um sucesso. Aliás, sou eu que decido."
        ],
        closers: ["Descansa bem.", "Muito bem.", "É isso.", "Aproveita o sossego.", "Pés para cima.", "Vês? Fácil."]
    )

    static let minimumDayOpen = PhrasePool(
        openers: ["Dia leve.", "Lista curta hoje.", "Dia mínimo.", "Hoje é um dia pequeno.", "Dia fácil.", "Hoje fica tudo pequenino."],
        bodies: [
            "Só {what}, e depois descansas.",
            "Apenas {what}, e é esse o plano todo.",
            "{What}, e acabou. A sério.",
            "O dia de hoje só pede {what}.",
            "Uma coisa na lista: {what}.",
            "{What} e mais nada. Confirmei duas vezes.",
            "{What} quando te der jeito, e depois descanso.",
            "{What} é a lista de tarefas inteira.",
            "Só {what}. O resto pode esperar por um dia maior.",
            "O grande projeto de hoje: {what}.",
            "{What}, e o dia é oficialmente um sucesso.",
            "Hoje só precisamos de {what}.",
            "Tudo o resto fica de fora. Só {what}.",
            "Basta {what} para o dia contar por inteiro.",
            "Primeiro {what}, depois o menos possível.",
            "Plano minúsculo: {what}, e depois sofá."
        ],
        closers: ["É isso.", "Sem pressa.", "Depois descansa.", "Fácil.", "Eu espero.", "Não é preciso mais."]
    )

    static let comeback = PhrasePool(
        openers: ["Olá, olha quem voltou.", "Ontem fugiu-nos.", "Aí estás tu.", "Fizemos um pequeno desvio.", "Um buraco na lista, mais nada.", "Dia novo."],
        bodies: [
            "Uma coisa pequena hoje e estamos de volta.",
            "Acontece a toda a gente, incluindo a mim.",
            "Não é preciso recuperar nada. Começa só a partir daqui.",
            "Vamos escolher a coisa mais pequena e chamar-lhe regresso.",
            "Guardei-te o lugar.",
            "Basta um passo pequeno para voltar a arrancar.",
            "Fico mesmo contente por estares aqui.",
            "Não se partiu nada, é só pegar outra vez.",
            "Hoje não tem de compensar nada.",
            "Não vamos contar o que falta. Vamos fazer o próximo.",
            "Basta marcar uma coisa para voltar ao ritmo.",
            "A lista não foi a lado nenhum, e não está zangada.",
            "Recomeçar é a arte toda, e estás a fazê-lo.",
            "Versão fácil hoje, e construímos a partir daí.",
            "Não é preciso discurso. Vamos só fazer uma coisinha.",
            "Está tudo aqui, e tu também."
        ],
        closers: ["Sem drama.", "Bom ver-te.", "Com calma.", "Vamos outra vez.", "Uma coisa, só isso.", "Ainda bem que voltaste."]
    )

    static let mustDoOpen = PhrasePool(
        openers: ["Uma coisa.", "Pequeno lembrete.", "Antes de mais nada.", "Um toquezinho.", "Com licença.", "Já que estás aqui."],
        bodies: [
            "Primeiro {what}, depois descansamos.",
            "{What} ainda está à espera. Só leva um minuto.",
            "{What}: ainda por fazer.",
            "Ainda há tempo para {what}.",
            "{What} tem sido muito paciente.",
            "A seguir na lista: {what}.",
            "E se tratássemos já de {what}?",
            "{What}, e depois ficas livre.",
            "Tens um minuto para {what}?",
            "Gostava muito de ver isto feito: {what}.",
            "{What} é o que ainda resta.",
            "Rapidinho: {what}.",
            "{What}, quando tiveres um segundo.",
            "Enquanto nos lembramos: {what}.",
            "{What} está a chamar por ti.",
            "Ainda tens um encontro marcado com {what}."
        ],
        closers: ["E fica tudo bem.", "Obrigado.", "É coisa pequena.", "Eu marco por ti, se tratares disso.", "É só isto.", "Sem complicações."]
    )

    static let routineLate = PhrasePool(
        openers: ["Pergunta rápida.", "Só por curiosidade.", "Um pouco tarde, não faz mal.", "Só a ver as horas.", "Um toque suave.", "Sem pressão."],
        bodies: [
            "Ainda está de pé?",
            "Queres fazer agora, ou deixar passar hoje?",
            "Ainda há tempo, se quiseres.",
            "Tarde também conta.",
            "Não se importa de ser um bocadinho mais tarde.",
            "Podemos fazer agora e ninguém vai saber.",
            "Começar mais tarde continua a ser começar.",
            "Ainda é esse o plano?",
            "Ainda dá para fazer, acho eu.",
            "Apetece-te agora?",
            "Continua ali à espera, se tiveres um momento.",
            "Se hoje não for o dia, é só dizeres.",
            "E se fosse agora?",
            "Os planos mudam. Este ainda vai acontecer?",
            "Dá o sinal e tratamos disso.",
            "Ainda te interessa, ou deixamos para lá?"
        ],
        closers: ["Qualquer das opções serve.", "Decides tu.", "Sem drama.", "Por mim, tudo bem.", "Só a confirmar.", "A escolha é tua."]
    )

    static let goodDay = PhrasePool(
        openers: ["Até agora, um bom dia.", "Está a correr bem.", "O dia está a portar-se bem.", "Nada mal.", "Gosto do dia de hoje.", "Hoje está a ser dos bons."],
        bodies: [
            "Mantém o embalo.",
            "Seja o que for que estás a fazer, mais disso.",
            "Isto está a correr-te bem.",
            "Não tenho nada a acrescentar, o que é um grande elogio.",
            "Estamos bem à frente do que os dias costumam estar.",
            "Da minha parte, nenhum reparo.",
            "Não quero agoirar, mas isto está a resultar.",
            "Sinceramente, dá gosto ver.",
            "Estás a fazer isto parecer bastante fácil.",
            "Se calhar vou ter de arranjar algo de que me queixar.",
            "Não mudes nada.",
            "Bom ritmo. Bom tudo.",
            "Estás naquela fase em que tudo corre bem.",
            "Mais uns quantos assim e começo a habituar-me.",
            "Essa pontuação está com ar bem satisfeito.",
            "Parece que o dia também gosta de ti."
        ],
        closers: ["Continua.", "Que bom.", "Bom trabalho.", "Estou a gostar disto.", "Venham mais.", "Muito bem."]
    )

    static let generic = PhrasePool(
        openers: ["Olá.", "Ainda por aqui.", "Sou só eu.", "Olá outra vez.", "Um olá rápido.", "Daqui fala o Pip."],
        bodies: [
            "Estás a ir bem.",
            "Nada urgente. Só gosto de vir ver como estás.",
            "Como vão as coisas por aí?",
            "Ando por aqui, se precisares de mim.",
            "Tu e eu estamos a safar-nos bem.",
            "Está tudo sob controlo, mais ou menos.",
            "Respira fundo. É de graça.",
            "Sem novidades, boas novidades, acho eu.",
            "Não tenho muito a relatar, mas queria dizer olá.",
            "Não ligues, só estou aqui a fazer companhia.",
            "Há alguma coisa pequena que pudesses acabar agora?",
            "Estive a regar o meu rebento. Enfim, estás a fazer um bom trabalho.",
            "É uma boa altura para te espreguiçares um pouco.",
            "Hoje é um bom dia para ser pequeno e cor de laranja, e um ótimo dia para ser tu.",
            "Isto está nas nossas mãos, mais coisa menos coisa.",
            "Tens ar de quem sabe o que está a fazer."
        ],
        closers: ["Continua.", "É só isto.", "Faz de conta que não vim.", "Vou ali ver uma folha.", "Até já.", "Adeusinho."]
    )

    static let focusing = PhrasePool(
        openers: ["Em foco.", "Concentração total.", "Hora de foco.", "Chiu.", "Em plena concentração, estou a ver."],
        bodies: [
            "Não faço barulho.",
            "Nem uma palavra da minha parte.",
            "Ando em bicos de pés.",
            "Eu fico a filtrar as chamadas.",
            "Nem vais dar por mim.",
            "Vou só ficar aqui a crescer.",
            "Faz de conta que sou uma planta.",
            "Baixei o volume."
        ],
        closers: ["Continua.", "Tudo como estava.", "Volto mais tarde.", "Esquece que estou aqui."]
    )
}
