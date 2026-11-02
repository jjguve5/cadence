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
            .replacingOccurrences(of: "{what}", with: what?.lowercased() ?? "that")
            .replacingOccurrences(of: "{What}", with: what ?? "That")
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
        "Hey, {name}.", "Right, {name}.", "Psst, {name}.", "Listen, {name}.", "Okay, {name}.", "So, {name}.",
        "Quick one, {name}.", "Hello, {name}.", "Look, {name}.", "Ah, {name}.", "Hi, {name}.", "Now then, {name}."
    ]

    static let morning = PhrasePool(
        openers: ["Morning.", "Good morning.", "Up and about, I see.", "Ah, you're here.", "Another day has been delivered.", "Hello, you."],
        bodies: [
            "Let's make today count.",
            "I've looked at today and it seems doable.",
            "Today is still completely unspoiled.",
            "Nothing has gone wrong yet, which is a strong start.",
            "The day is open. You get first pick.",
            "I've been up for ages. Well, for a minute.",
            "Let's pick one thing and do it properly.",
            "The list is there when you want it, no rush.",
            "You don't have to win the morning. Just turn up to it.",
            "Coffee first if that's how it works around here.",
            "Today has room in it. Let's use some.",
            "Let's start small and see what happens.",
            "I have a good feeling about today, and I'm usually only half wrong.",
            "A blank page, and you're holding the pen.",
            "Whatever yesterday was, it's filed away now.",
            "We're doing the day again. I hear it went fine last time.",
            "First things first: being awake. Done.",
            "You showed up, so the hard part is out of the way."
        ],
        closers: ["I'm right here.", "No hurry.", "Off we go.", "Lead the way.", "I'll follow you.", "Let's see what we can do."]
    )

    static let sleepShort = PhrasePool(
        openers: ["Short night.", "Not much sleep, I see.", "Well, that was a brief night.", "The night was on the small side.", "Morning, sleepy.", "So the night ran short."],
        bodies: [
            "Let's keep today gentle.",
            "We'll do the important bits and skip the heroics.",
            "Today can be a smaller day. Nobody's checking.",
            "Let's aim for good enough and call it a win.",
            "Pick the one thing that matters and leave the rest alone.",
            "No big plans needed. Just the next small thing.",
            "We'll go at walking pace today.",
            "An early night tonight would be a nice thing to look forward to.",
            "I'm a bit slow today too, so we match.",
            "Let's not ask too much of you before lunch.",
            "You can still have a perfectly decent day on this.",
            "Slow and steady is a whole plan today.",
            "Nothing here needs to be impressive.",
            "Let's lower the bar until it's easy to step over.",
            "These things happen. We'll work with what we've got.",
            "A soft day it is, then.",
            "Be nice to yourself today. I'll be nice to you too.",
            "We can take the scenic route through today."
        ],
        closers: ["I'll keep it simple.", "Easy does it.", "One thing at a time.", "We've got this, slowly.", "Tonight's another go.", "No pressure from me."]
    )

    static let sleepGood = PhrasePool(
        openers: ["A full night.", "Well slept.", "Look at you, rested.", "Now that was a night.", "Good sleep, that one.", "You slept. Properly."],
        bodies: [
            "Today's yours.",
            "You've got plenty in the tank today.",
            "I'd spend that on something you actually care about.",
            "Whatever you've been putting off, today is a fine day for it.",
            "Your bed did good work. Your turn now.",
            "That's the sort of start I like.",
            "You look ready, and I'm not just saying that.",
            "Let's not waste a morning like this one.",
            "Today can take a bit more than usual.",
            "Pick something a little ambitious. You can afford it.",
            "I'm impressed, and I've got a sprout on my head, so I've seen things.",
            "That's one thing done before you even got up.",
            "We should use this while it's fresh.",
            "All systems seem to be in a good mood.",
            "This is what lights out on time buys you.",
            "I'd be smug about that if I were you."
        ],
        closers: ["Enjoy it.", "Go on, then.", "Nicely done.", "Keep that up.", "Let's go.", "I'm taking notes."]
    )

    static let recoveryLow = PhrasePool(
        openers: ["Low battery day.", "Your numbers are a bit quiet today.", "Readiness is on the low side.", "A lower gear today, I think.", "Not your most charged day.", "The band says go easy."],
        bodies: [
            "Let's take it easy where we can.",
            "A walk would count as plenty today.",
            "This is a good day to do less and do it well.",
            "If you train, keep it light and call it smart.",
            "Nothing wrong with a slower day, they're part of the deal.",
            "We can leave the big stuff for tomorrow.",
            "Today's job is mostly not overdoing it.",
            "Maybe this isn't the day to set any records.",
            "You can still get things done, just with less drama.",
            "Pick the easy version of whatever's on the list.",
            "Let's save some for later in the week.",
            "A bit of rest would be time well spent.",
            "It's only one day's reading, not a verdict.",
            "Take today one stair at a time.",
            "Doing the small stuff still counts today.",
            "We'll coast a little. Coasting is allowed."
        ],
        closers: ["It's fine.", "Tomorrow's a new number.", "I'll go slow too.", "No heroics needed.", "You know best.", "Gently does it."]
    )

    static let recoveryHigh = PhrasePool(
        openers: ["Readiness is up.", "Green across the board.", "You're charged today.", "Good numbers this morning.", "The band is pleased.", "Today you've got some spare."],
        bodies: [
            "If you were waiting for a day to push, this is it.",
            "A harder session would fit nicely today.",
            "You've got room for something ambitious.",
            "Today can take more than usual, if you want it to.",
            "This is a good day to pick the heavy thing.",
            "Whatever you've been avoiding has run out of excuses.",
            "I'd use this before it wears off.",
            "Let's do something with all that.",
            "You could go for a long one today.",
            "The tough item on the list won't get a better day.",
            "Consider this a green light, not an order.",
            "You've earned a day like this.",
            "There's capacity today. Spend some of it.",
            "This is the day future you will be glad you used.",
            "I'd start with the hardest thing and work down.",
            "Nothing's stopping you today, as far as I can see."
        ],
        closers: ["Have fun with it.", "Go get it.", "I'll cheer.", "Up to you, of course.", "Enjoy that.", "Let's see it."]
    )

    static let trainingDone = PhrasePool(
        openers: ["Training done.", "Session in the bank.", "You trained.", "That's the workout done.", "Nice session.", "Look who moved today."],
        bodies: [
            "Nobody can take that one back.",
            "You can be pleased with yourself for a while.",
            "That was the hard part of the day, and it's behind you.",
            "Now for some food and a bit of sitting down.",
            "Everything else today is a bonus.",
            "I watched the whole thing and I'm very tired.",
            "Your next self owes you a thank you.",
            "That's how this works. One session at a time.",
            "A good thing to have done, however it felt.",
            "The couch has been informed that you've earned it.",
            "Good work. I'd clap, but my paws are very small.",
            "Not everybody did that today. You did.",
            "That's one more on the pile, and the pile is growing.",
            "You said you would, and then you did. Rare and excellent.",
            "Time to eat something and feel smug.",
            "That counts today, and it'll count next month too."
        ],
        closers: ["Well done.", "Proud of you.", "Rest up.", "Enjoy the feeling.", "See you next time.", "That's the stuff."]
    )

    static let trainedLowDay = PhrasePool(
        openers: ["You trained on a low day.", "A low day, and you still trained.", "Low numbers, and you still went.", "Not your best day on paper, and you trained anyway.", "You went even on a quiet day.", "Low readiness, session done."],
        bodies: [
            "Showing up counts.",
            "That takes something, and I noticed.",
            "Those are the sessions that build the habit.",
            "It doesn't have to be your best to be worth doing.",
            "Now you've done plenty, so feel free to do nothing.",
            "That's the kind of thing I'd put on a small trophy.",
            "Easy for the rest of today, I'd say.",
            "A gentle one on a gentle day is exactly right.",
            "The rest of today can be soft.",
            "Good days are easy. That one was the other sort.",
            "Consistency looks a lot like that.",
            "That one counts double in my book, and it's my book."
        ],
        closers: ["Good on you.", "I saw that.", "Rest now.", "Respect.", "Well played.", "Now put your feet up."]
    )

    static let trainingSkipped = PhrasePool(
        openers: ["No training today.", "So we're skipping the session.", "Rest day, then.", "The workout's off.", "Session skipped, noted.", "Today's training has been cancelled."],
        bodies: [
            "That's allowed. It'll still be there next time.",
            "One session doesn't change much at all.",
            "You know your day better than I do.",
            "Let's enjoy the extra time and go again next time.",
            "A walk would be lovely, if you feel like it. If not, also fine.",
            "We carry on. No drama.",
            "The weights won't take it personally.",
            "There's plenty of the week left.",
            "Sometimes that's the right call.",
            "I'm not keeping score on this one. Well, the app is, but kindly.",
            "Let's find the next slot and leave it at that.",
            "That's more time for the rest of your life.",
            "It's one day, and you've got a lot of those.",
            "Tomorrow's still got your name on it.",
            "Nothing lost that can't be picked up later.",
            "We'll call it a planned rest and move along."
        ],
        closers: ["All good.", "No big deal.", "Moving on.", "Next time, then.", "I'm easy.", "Carry on."]
    )

    static let waterBehind = PhrasePool(
        openers: ["Water check.", "A word about water.", "Your water is a bit behind.", "We're running a little dry.", "Psst, water.", "Glass status: mostly empty."],
        bodies: [
            "A big glass now gets you back on pace.",
            "Could you have a glass, as a favour to me?",
            "The tap is right there and it's very reasonably priced.",
            "One big glass and I'll stop mentioning it.",
            "Go on, have a good long drink.",
            "Your bottle is looking lonely.",
            "Let's catch up with a glass or two.",
            "I've got a sprout on my head, so I think about water a lot.",
            "This is my gentle tap on the shoulder about water.",
            "Take a few big sips and we'll call it progress.",
            "Fill a glass next time you pass the kitchen.",
            "It's the easiest thing on the list, and it's on the list.",
            "The water won't drink itself. I've watched it try.",
            "A refill would catch you up nicely.",
            "Maybe put a glass on the desk where you can see it.",
            "Just one glass. I'm not asking for a swimming pool.",
            "Have a drink, you've been busy.",
            "Next glass is on the house."
        ],
        closers: ["Cheers.", "Thank you.", "That's all from me.", "I'll be watching, kindly.", "Bottoms up.", "No rush, but soon."]
    )

    static let proteinBehind = PhrasePool(
        openers: ["Protein check.", "A note from the kitchen.", "About protein.", "Dinner thought.", "Food question.", "On the protein front."],
        bodies: [
            "A shake or a fridge portion covers most of it.",
            "Something with eggs or chicken would sort this out.",
            "Dinner could do most of the work here.",
            "A yogurt or a tin of tuna would make a nice dent.",
            "There's still time, and there's still food.",
            "Let's make the next thing you eat count for a bit more.",
            "It's closer than it looks. One proper portion does a lot.",
            "A big spoonful of something high in protein, maybe?",
            "Have a look in the fridge. It might surprise you.",
            "An easy one: a shake, and you're nearly there.",
            "A snack with some substance would help.",
            "Dessert could be a yogurt, if you want to be clever about it.",
            "No need to be perfect, just a bit closer.",
            "You don't have to finish it, just nudge it along.",
            "Cottage cheese exists, and I'm only mentioning it.",
            "This one is solved by eating, which is the good kind of problem."
        ],
        closers: ["Enjoy.", "Just a thought.", "Your call.", "Bon appetit.", "I'll stop there.", "Nearly there."]
    )

    static let fruitGoal = PhrasePool(
        openers: ["Fruit check.", "No fruit so far, by my count.", "A word from the fruit bowl.", "About fruit.", "Thought for today: fruit.", "The fruit bowl sent me."],
        bodies: [
            "An apple would do nicely.",
            "A banana takes ten seconds and no skill at all.",
            "Have an orange. It's practically already peeled. It isn't, but go on.",
            "One piece and today's fruit is sorted.",
            "Something sweet and from a tree, perhaps?",
            "A pear after lunch would be a civilised touch.",
            "Grab one on your way past, you won't even have to stop.",
            "Fruit counts as a snack and as a small victory.",
            "Whatever's in season and looks friendly.",
            "Grapes count too, and they come with no peeling.",
            "It's the easiest goal on the board, and the tastiest.",
            "Put one on the desk and let it tempt you.",
            "Dessert sorted, if you think about it.",
            "Let's get one in before the day runs off.",
            "That bowl isn't just decoration.",
            "A bit of fruit sounds nice about now, doesn't it?"
        ],
        closers: ["Easy one.", "Enjoy it.", "That's all I've got.", "Yum.", "No peeling required. Sometimes.", "Off you go."]
    )

    static let soupGoal = PhrasePool(
        openers: ["Soup check.", "A word about soup.", "Have we had soup today?", "Soup thought.", "Very serious soup matter.", "The soup question."],
        bodies: [
            "A bowl with lunch or dinner would do it.",
            "A proper bowl of sopa and that's the goal done.",
            "Vegetables in their friendliest form.",
            "Warm, easy and already practically a tradition.",
            "It only takes a bowl and a spoon, and you own both.",
            "Start dinner with a bowl and you're sorted.",
            "If there's some in the fridge, this is its moment.",
            "A pot of it would cover you for days.",
            "Caldo verde would count, and I'd be jealous.",
            "Soup is just a meal being kind to you.",
            "Anything with vegetables and a spoon will do.",
            "Your grandmother would approve of this reminder.",
            "A small bowl still counts. I checked.",
            "You could heat one up in the time it took to read this.",
            "Let's get one in before bedtime sneaks up.",
            "It's hard to be in a bad mood holding a bowl of soup."
        ],
        closers: ["Lovely.", "Spoon ready.", "Enjoy it.", "Save me a spoonful.", "That's my whole message.", "Warm regards."]
    )

    static let shower = PhrasePool(
        openers: ["Shower thought.", "About that shower.", "The shower is free, by the way.", "Bathroom's open.", "A small suggestion.", "Shower o'clock, more or less."],
        bodies: [
            "A few warm minutes and the day feels finished.",
            "It's a nice way to draw a line under today.",
            "You'll feel like a new person, or at least a cleaner one.",
            "Good place to have ideas, too.",
            "Five minutes and it's done for today.",
            "Hot water, no phone, excellent deal.",
            "Sing something. I won't tell.",
            "Now might be a nice time, before the evening gets away.",
            "You could fit one in before you get comfortable.",
            "It beats doing it half asleep.",
            "Whenever you're ready, the water is.",
            "Consider it a very short holiday.",
            "It's one of the easier wins on offer.",
            "Towel, water, done. Three steps.",
            "If it's too late tonight, tomorrow morning is fine.",
            "It takes less time than deciding whether to."
        ],
        closers: ["Enjoy.", "No rush.", "Just saying.", "You'll thank me.", "I'll wait here.", "Off you pop."]
    )

    static let brushing = PhrasePool(
        openers: ["Teeth.", "Brush time.", "A note on your teeth.", "Toothbrush calling.", "One small thing.", "Quick dental bulletin."],
        bodies: [
            "Two minutes and you never have to think about it again today.",
            "Your toothbrush has been standing there all day, waiting.",
            "You know how this one goes.",
            "Two minutes, plus some light dancing if you want.",
            "It's the shortest job on the list.",
            "Your teeth have asked me to mention it.",
            "Put on a song and you're done before it ends.",
            "Quick one, then back to whatever you were doing.",
            "Nobody's ever regretted this one.",
            "You could do it with your eyes closed, so maybe do.",
            "That's a tiny job with a minty finish.",
            "Grab the brush on your way past.",
            "Pip's dental advice: yes.",
            "You can scroll later. Well, you can't brush and scroll. Maybe you can.",
            "Bathroom, brush, done, freedom.",
            "It's small enough to do right now."
        ],
        closers: ["Minty.", "That's all.", "Done soon.", "Off you go.", "Your smile says thanks.", "Easy win."]
    )

    static let reading = PhrasePool(
        openers: ["Book time.", "Your book called.", "A thought about your book.", "Reading corner is open.", "It's been asking about you.", "On the bedside table."],
        bodies: [
            "Ten pages would do.",
            "A few pages count. They always count.",
            "It's probably better than whatever's on your phone.",
            "Find out what happens next. I'd like to know too.",
            "Just one chapter, and I do mean it, maybe.",
            "Screen down, book up.",
            "You left someone in the middle of a sentence.",
            "Twenty minutes, then you can say you read today.",
            "The story hasn't moved since you left it.",
            "A page is enough to get started.",
            "It's a very cheap way to go somewhere else.",
            "You'll fall asleep smarter, that's my whole pitch.",
            "It's sitting right where you left it, not judging at all.",
            "A cosy chair and a few pages sound good to me.",
            "Read until your eyes say stop.",
            "No need to finish it, just visit."
        ],
        closers: ["Enjoy.", "I'll be quiet.", "Happy reading.", "Tell me how it ends.", "Off you go.", "Good company, books."]
    )

    static let promisesDone = PhrasePool(
        openers: ["Everything done.", "That's the lot.", "The list is empty.", "All done for today.", "You did all of it.", "Nothing left on the board."],
        bodies: [
            "Proud of you.",
            "I'm doing a tiny dance about it.",
            "You can stop now. That's an actual option.",
            "The rest of today is purely decorative.",
            "That's what it looks like when you keep your word.",
            "I've run out of things to bother you about.",
            "You said you'd do these, and you did them. Excellent behaviour.",
            "Time to do something completely useless. You've earned it.",
            "Honestly, not bad at all.",
            "You've made my job very easy today.",
            "All of it, and on a regular day too.",
            "This is the good kind of nothing left to do.",
            "Today's version of you is on a roll.",
            "I'd give you a medal, but I need it for my wardrobe.",
            "Now go and enjoy being someone with nothing to do.",
            "You've left me speechless, nearly."
        ],
        closers: ["Well done.", "Go and relax.", "Lovely work.", "That's a good day.", "Enjoy your evening.", "Thank you for that."]
    )

    static let streak = PhrasePool(
        openers: ["Look at that.", "Well, well.", "Quite the run.", "Keep this up and I'll get emotional.", "I've been counting.", "Noticed."],
        bodies: [
            "That's how habits stick.",
            "That isn't luck any more. That's just you.",
            "You're making this look easy, and I know it isn't.",
            "A little more of this and you won't even have to think about it.",
            "Small things, done again and again. It adds up.",
            "This is the boring part that makes everything work.",
            "I'd like the record to show I never doubted you.",
            "You're turning into someone who does this.",
            "It's quietly becoming a thing you do.",
            "Most people talk about this. You keep doing it.",
            "Don't look down, just keep going.",
            "That number got there one ordinary day at a time.",
            "Very steady work. I like steady.",
            "It doesn't need to be perfect to keep going, and it's going.",
            "You've built something here, and it's only getting sturdier.",
            "If you miss one, we just carry on. But look at it."
        ],
        closers: ["Nice.", "Keep rolling.", "I'm impressed.", "Carry on.", "That's the way.", "Good stuff."]
    )

    static let eveningClose = PhrasePool(
        openers: ["Evening.", "Nearly there.", "The day's winding up.", "Almost time to call it.", "That was today.", "Evening, you."],
        bodies: [
            "Close the day when you're ready. It takes a minute.",
            "Tell me how it went. I've been wondering.",
            "One minute to put today away properly?",
            "Rate the day and pick tomorrow's three. Then you're free.",
            "Let's write down what happened and leave it there.",
            "Whatever today was, it's enough to close.",
            "Time to put a lid on today.",
            "It's nice to end a day on purpose.",
            "Let's tidy today up and leave tomorrow a note.",
            "A quick look back, and then no more thinking about it.",
            "Tomorrow's three are easier to pick tonight.",
            "Good days and odd days both get closed the same way.",
            "You've done the day. All that's left is saying so.",
            "No essay needed. A few taps will do it.",
            "I keep the score. You just tell me how it felt.",
            "Tell me one good thing, if there was one."
        ],
        closers: ["Then rest.", "I'm listening.", "No rush.", "Then it's couch time.", "Almost done.", "Good night soon."]
    )

    static let windDown = PhrasePool(
        openers: ["Wind-down time.", "Getting late.", "Time to start slowing down.", "Evening's nearly over.", "The day is shutting up shop.", "Sleepy hour."],
        bodies: [
            "Screens away, book out.",
            "Screens away, lights low.",
            "Tomorrow can wait until tomorrow.",
            "Lights down, feet up.",
            "Whatever's left can go on tomorrow's list.",
            "I'm yawning already, and my sprout is drooping.",
            "A book and a dim lamp sound right about now.",
            "Your phone will survive without you for a bit.",
            "This is the part where nothing else needs to happen.",
            "Let's start landing the plane.",
            "Teeth, pillow, the usual route.",
            "Time to stop being useful for the day.",
            "The internet will still be there in the morning. It's a shame, really.",
            "Getting comfy is the only task left.",
            "Let's turn things down a notch.",
            "You're off duty now."
        ],
        closers: ["Good night soon.", "Sleep's on its way.", "See you tomorrow.", "I'm heading off too.", "Sweet dreams, nearly.", "Off to bed with us."]
    )

    static let minimumDayDone = PhrasePool(
        openers: ["Light day.", "Essentials done.", "Minimum day, done.", "That's today's short list.", "Easy day, finished.", "The small list is empty."],
        bodies: [
            "That's a full day.",
            "That's all today needed to be.",
            "Nothing else is required. I checked.",
            "Today's rules say you've won.",
            "You did what today asked. Stop there if you like.",
            "A small day done properly is a good day.",
            "You can rest now, and it counts as following the plan.",
            "The rest is optional, and I mean that.",
            "Everything else can wait for a bigger day.",
            "That was the deal, and you kept it.",
            "Small days keep the big ones possible.",
            "Now do as little as you can get away with.",
            "No extra credit needed today.",
            "You kept the thread going, and that's the point of today.",
            "Off the clock, officially.",
            "I'd call that a success. In fact, I'm the one who does."
        ],
        closers: ["Rest up.", "Well done.", "That's it.", "Enjoy the quiet.", "Feet up.", "See? Easy."]
    )

    static let minimumDayOpen = PhrasePool(
        openers: ["Light day.", "Short list today.", "Minimum day.", "Today's a small one.", "Easy day.", "We're keeping today tiny."],
        bodies: [
            "Just {what} and rest.",
            "Only {what}, and that's the whole plan.",
            "{What}, then you're done. Really.",
            "All today asks for is {what}.",
            "One thing on the list: {what}.",
            "{What} and nothing else. I checked twice.",
            "Do {what} whenever suits you, then rest.",
            "{What} is the entire to-do list.",
            "Just {what}. The rest can wait for a bigger day.",
            "Today's big project: {what}.",
            "{What}, and the day is officially a success.",
            "We only need {what} from today.",
            "Everything else is off. Just {what}.",
            "If {what} happens, today counts in full.",
            "{What} first, then as little as possible.",
            "Tiny plan: {what}, then the couch."
        ],
        closers: ["That's it.", "No rush.", "Then rest.", "Easy.", "I'll wait.", "Nothing more."]
    )

    static let comeback = PhrasePool(
        openers: ["Hey, welcome back.", "Yesterday slipped.", "There you are.", "We took a small detour.", "A gap in the list, that's all.", "New day."],
        bodies: [
            "One small thing today and we're back.",
            "It happens to everybody, including me.",
            "No need to catch up. Just start from here.",
            "Let's pick the smallest thing and call it a return.",
            "I kept your place.",
            "It's one small step to get going again.",
            "I'm just glad you're here.",
            "Nothing's broken, you can just pick it up.",
            "Today doesn't need to make up for anything.",
            "Let's not count what's missing. Let's do the next one.",
            "One tick is all it takes to get rolling again.",
            "The list didn't go anywhere, and it isn't cross.",
            "Starting again is the whole skill, and you're doing it.",
            "Easy version today, and we'll build from there.",
            "No speech needed. Let's just do something tiny.",
            "Everything's still here, and so are you."
        ],
        closers: ["No fuss.", "Good to see you.", "Easy does it.", "We go again.", "One thing, that's all.", "I'm glad you came back."]
    )

    static let mustDoOpen = PhrasePool(
        openers: ["One thing.", "Small reminder.", "Before anything else.", "Tiny nudge.", "Excuse me.", "While I have you."],
        bodies: [
            "{What} first, then we rest.",
            "{What} is still waiting. It only takes a minute.",
            "{What}: still open.",
            "Still time for {what}.",
            "{What} has been very patient.",
            "Next on the list: {what}.",
            "Shall we get {what} out of the way?",
            "{What}, and then you're free.",
            "Got a minute for {what}?",
            "I'd like to see {what} ticked off.",
            "{What} is the one left standing.",
            "Quick one: {what}.",
            "{What}, whenever you get a second.",
            "Let's do {what} while we're thinking about it.",
            "{What} is asking for you by name.",
            "You and {what} still have an appointment."
        ],
        closers: ["Then we're good.", "Thank you.", "It's a small one.", "I'll tick it for you, if you do it.", "That's all.", "No fuss."]
    )

    static let routineLate = PhrasePool(
        openers: ["Small check.", "Just asking.", "A little late, no problem.", "Time check.", "Gentle nudge.", "No pressure."],
        bodies: [
            "Still on?",
            "Want to do it now, or let it go today?",
            "Still got time, if you want it.",
            "Late still counts.",
            "It doesn't mind being a bit late.",
            "We can do it now and nobody will know.",
            "A later start is still a start.",
            "Is it still the plan?",
            "Still doable, I think.",
            "Up for it now?",
            "It's still sitting there, if you've got a moment.",
            "If today's not the day, just tell me.",
            "Fancy doing it now?",
            "Plans move. Is this one still happening?",
            "Say the word and we'll get it done.",
            "Still interested, or shall we leave it?"
        ],
        closers: ["Either's fine.", "Up to you.", "No drama.", "I'm easy.", "Just checking.", "Your call."]
    )

    static let goodDay = PhrasePool(
        openers: ["Good day so far.", "Going well.", "Today's behaving.", "Not bad at all.", "I like today.", "Nice one, today."],
        bodies: [
            "Keep it rolling.",
            "Whatever you're doing, more of that.",
            "You've got a good thing going.",
            "I've nothing to add, which is high praise.",
            "We're well ahead of where days usually are.",
            "No notes from me.",
            "Let's not jinx it, but this is working.",
            "It's nice to watch, honestly.",
            "You're making this look quite easy.",
            "I may have to find something to complain about.",
            "Just carry on as you are.",
            "Good pace. Good everything.",
            "You're doing the thing where it all goes fine.",
            "A few more like this and I'll start to expect it.",
            "That score is looking quite pleased with itself.",
            "Today seems to like you back."
        ],
        closers: ["Carry on.", "Lovely.", "Nice work.", "I'm enjoying this.", "More of that.", "Good stuff."]
    )

    static let generic = PhrasePool(
        openers: ["Hi.", "Still here.", "Just me.", "Hello again.", "Quick hello.", "Pip here."],
        bodies: [
            "You're doing fine.",
            "Nothing urgent. I just like to check in.",
            "How's it going over there?",
            "I'm around if you need me.",
            "You and I are doing all right.",
            "Everything's under control, more or less.",
            "Take a breath. That's free.",
            "No news is good news, I think.",
            "I don't have much to report, but I wanted to say hi.",
            "Don't mind me, I'm only standing here.",
            "Is there anything small you could finish right now?",
            "I've been watering my sprout. Anyway, you're doing well.",
            "It's a decent moment to stretch a bit.",
            "It's a good day to be small and orange, and a fine one to be you.",
            "We've got this, in the loose sense of having it.",
            "You look like someone who has things in hand."
        ],
        closers: ["Carry on.", "That's all.", "As you were.", "I'm off to look at a leaf.", "See you in a bit.", "Bye for now."]
    )

    static let focusing = PhrasePool(
        openers: ["Focusing.", "Head down.", "Focus time.", "Shh.", "In the zone, I see."],
        bodies: [
            "I'll be quiet.",
            "Not a word from me.",
            "I'm on tiptoe.",
            "I'll hold your calls.",
            "You won't hear me.",
            "I'm just going to sit here and grow.",
            "Pretend I'm a plant.",
            "I'm keeping the noise down."
        ],
        closers: ["Carry on.", "As you were.", "Back later.", "Don't mind me."]
    )
}
