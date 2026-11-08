// Reading: books with pace and a finish date, quotes, and reading mode (press play: warm dark screen kept on,
// a timer that survives locking, Do Not Disturb through a Shortcut you set up once). Projects live here too.
// Phase 2.9 (design v17 N_Leitura, decision 78): a reading started from the night carries the minutes planned, with a
// light vibration when they're up (which you can turn off); «Ao terminar» corrects the duration and, optionally, where
// you stopped, by page or percentage. The reading planned (ReadingPlan) and the reading done (ReadingSession) are
// different records.
import SwiftUI

struct BooksView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Book?
    @State private var reading = false

    var body: some View {
        Screen(glow: .read) {
            if let b = store.currentBook {
                Card(tint: .read) {
                    HStack(spacing: 14) {
                        BookCover(book: b).frame(width: 70, height: 100)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(b.title).font(.geist(17, .bold))
                            if !b.author.isEmpty { Text(b.author).font(.geist(13)).foregroundStyle(Color.soft) }
                            Bar(progress: Double(b.page) / Double(max(1, b.pages)), area: .read)
                            let pace = store.readingPace(b)
                            Text("p. \(b.page) de \(b.pages)" + (pace.finish.map { " · acabas a \(Day.date($0).formatted(.dateTime.day().month()))" } ?? "")).font(.geist(12)).foregroundStyle(Color.soft)
                        }
                    }
                    PrimaryButton(title: "▶  Ler agora", area: .read) { reading = true }
                }
            }
            Card {
                HStack { Eyebrow(text: "Livros", icon: "books.vertical.fill"); Spacer(); Button { editing = Book(title: "") } label: { Label("Adicionar", systemImage: "plus").font(.geist(13, .semibold)) }.tint(.read) }
                ForEach(store.all(Book.self).sorted { ($0.finished ?? "9") > ($1.finished ?? "9") }) { b in
                    Button { editing = b } label: {
                        HStack {
                            BookCover(book: b).frame(width: 26, height: 38)
                            VStack(alignment: .leading) { Text(b.title).font(.geist(14, .semibold)); Text(b.finished.map { "terminado a \(Day.date($0).formatted(.dateTime.day().month().year()))" } ?? "p. \(b.page) / \(b.pages)").font(.geist(11.5)).foregroundStyle(Color.soft) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                let year = String(Day.today.prefix(4))
                let finishedThisYear = store.all(Book.self).filter { $0.finished?.hasPrefix(year) ?? false }.count
                Text("\(finishedThisYear) \(finishedThisYear == 1 ? "terminado" : "terminados") em \(year)").font(.geist(12)).foregroundStyle(Color.faint)
            }
            let quotes = store.all(ReadingSession.self).filter { $0.quote != nil }.sorted { $0.start > $1.start }.prefix(5)
            if !quotes.isEmpty {
                Card {
                    Eyebrow(text: "Citações", icon: "quote.opening")
                    ForEach(Array(quotes)) { q in Text("“\(q.quote!)”").font(.serif(14)).italic() }
                }
            }
            if let rs = store.readingAndSleep() {
                Card(tint: .sleep) {
                    Eyebrow(text: "Leitura e sono", icon: "moon.stars", color: .sleep)
                    Text("Depois de serões com 15 ou mais minutos de leitura dormiste \(duration(rs.with)), contra \(duration(rs.without)) nos outros (\(rs.nights) noites). É um padrão, não uma prova.").font(.geist(13))
                }
            }
            NavigationLink { ProjectsView() } label: { Text("Projetos e prazos").font(.geist(14, .semibold)).foregroundStyle(Color.mint) }
        }
        .navigationTitle("Leitura")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { BookEditor(book: $0) }
        .fullScreenCover(isPresented: $reading) { ReadingMode() }
    }
}

struct BookCover: View {
    var book: Book
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: g.size.width * 0.06, bottomLeadingRadius: g.size.width * 0.06, bottomTrailingRadius: g.size.width * 0.12, topTrailingRadius: g.size.width * 0.12)
                    .fill(LinearGradient(colors: [Color(hue: book.hue, saturation: 0.55, brightness: 0.38), Color(hue: book.hue, saturation: 0.6, brightness: 0.16)], startPoint: .topLeading, endPoint: .bottomTrailing))
                Rectangle().fill(.white.opacity(0.08)).frame(width: max(2, g.size.width * 0.05))
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    Text(book.title).font(.serif(max(7, g.size.width * 0.15))).foregroundStyle(Color(hex: 0xF1D9A8)).lineLimit(4).minimumScaleFactor(0.6)
                    if !book.author.isEmpty { Text(book.author).font(.geist(max(5, g.size.width * 0.07))).foregroundStyle(Color(hex: 0xF1D9A8, opacity: 0.6)).lineLimit(1) }
                    Spacer()
                }
                .padding(.horizontal, g.size.width * 0.12)
            }
            .shadow(color: .black.opacity(0.6), radius: g.size.width * 0.12, y: g.size.width * 0.1)
        }
    }
}

struct BookEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var book: Book
    var body: some View {
        NavigationStack {
            Form {
                TextField("Título", text: $book.title)
                TextField("Autor", text: $book.author)
                Stepper("\(book.pages) páginas", value: $book.pages, in: 20...2000, step: 10)
                Stepper("Na página \(book.page)", value: $book.page, in: 0...book.pages, step: 1)
                Toggle("Terminado", isOn: Binding(get: { book.finished != nil }, set: { book.finished = $0 ? Day.today : nil; if $0 { book.page = book.pages } }))
                if store.record(Book.self, book.id) != nil { Button("Apagar", role: .destructive) { store.remove(book); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(book.title.isEmpty ? "Novo livro" : book.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { if book.hue == 0.58 { book.hue = Double.random(in: 0...1) }; store.save(book); dismiss() }.disabled(book.title.isEmpty) }
            }
        }
    }
}

struct ReadingMode: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    /// The minutes planned, when the reading was started from the night; nil otherwise (the ring keeps its 30 min)
    var planned: Int?
    @AppStorage("reading.nudge") private var nudge = true // the light vibration at the planned end
    @State private var nudged = false
    @State private var minutes = 0 // «Duração», corrected before saving
    @State private var byPercent = false
    @State private var percent = 0
    @State private var startPercent = 0
    @State private var session = ReadingSession()
    @State private var now = Date()
    @State private var paused: Date?
    @State private var pausedTotal = 0.0
    @State private var finishing = false
    @State private var page = 0
    @State private var note = ""
    @State private var quote = ""
    @State private var goal = 30
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let cream = Color(hex: 0xF6EAD2)

    init(planned: Int? = nil) {
        self.planned = planned
        _goal = State(initialValue: planned ?? 30)
    }

    private var elapsed: Double { (paused ?? now).timeIntervalSince(Date(timeIntervalSince1970: session.start / 1000)) - pausedTotal }

    var body: some View {
        let book = store.currentBook
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2B2113), Color(hex: 0x07090E)], center: UnitPoint(x: 0.5, y: 0.1), startRadius: 0, endRadius: 520).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { openURL(URL(string: "shortcuts://run-shortcut?name=Cadence%20Reading")!) } label: {
                        Text("NÃO INCOMODAR · ATIVADO").font(.geist(11, .semibold)).tracking(1.1).foregroundStyle(cream.opacity(0.5))
                    }
                    Spacer()
                    Button("Terminar") { finish(book) }.font(.geist(14)).foregroundStyle(cream.opacity(0.55))
                }
                .padding(.top, 6)
                Spacer(minLength: 30)
                if let book { BookCover(book: book).frame(width: 128, height: 186) }
                Spacer(minLength: 34)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 5)
                    Circle().trim(from: 0, to: min(1, max(0.002, elapsed / Double(goal * 60))))
                        .stroke(LinearGradient(colors: [Color(hex: 0xF6D48F), Color(hex: 0xC98B3A)], startPoint: .topLeading, endPoint: .bottomTrailing), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 6) {
                        Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)).font(.mono(46, .medium)).foregroundStyle(cream)
                        Text("de \(goal) min" + (book.map { " · p. \($0.page)" } ?? "")).font(.geist(14)).foregroundStyle(cream.opacity(0.5))
                    }
                }
                .frame(width: 236, height: 236)
                Spacer(minLength: 30)
                if let planned {
                    let startMinute = Day.minuteOfDay(Date(timeIntervalSince1970: session.start / 1000))
                    Button { nudge.toggle() } label: {
                        Text("Planeado \(planned) min · " + (nudge ? "aviso discreto às \(clock(startMinute + planned))" : "sem aviso")).font(.geist(13)).foregroundStyle(cream.opacity(0.6))
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(nudge ? "Desliga a vibração no fim do tempo planeado" : "Liga uma vibração leve no fim do tempo planeado")
                    .accessibilityIdentifier("reading.nudge")
                }
                Text("Ecrã escurecido e sempre ligado. As notificações esperam.").font(.geist(13)).foregroundStyle(cream.opacity(0.42))
                    .padding(.bottom, 14)
                HStack(spacing: 10) {
                    readingButton(paused == nil ? "Pausa" : "Retomar") {
                        if let p = paused { pausedTotal += Date().timeIntervalSince(p); paused = nil } else { paused = Date() }
                    }
                    readingButton("Nota") { finish(book) }
                    Button { finish(book) } label: {
                        Text("Concluído").font(.geist(15, .semibold)).foregroundStyle(Color(hex: 0x2B1A05)).frame(maxWidth: .infinity).padding(.vertical, 15)
                            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(LinearGradient(colors: [Color(hex: 0xF6D48F), Color(hex: 0xC98B3A)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                            .shadow(color: Color(hex: 0xC98B3A, opacity: 0.4), radius: 12, y: 5)
                    }
                    .buttonStyle(Pressable())
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 10)
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) {
            now = $0
            // A light vibration once the planned minutes are up, if you keep it on; never while paused
            if let planned, nudge, !nudged, paused == nil, elapsed >= Double(planned * 60) {
                nudged = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
        .onAppear {
            session = ReadingSession(bookId: book?.id, fromPage: book?.page ?? 0)
            UIApplication.shared.isIdleTimerDisabled = true
            UIScreen.main.brightness = max(0.15, UIScreen.main.brightness * 0.6)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $finishing) {
            NavigationStack {
                Form {
                    Section {
                        Stepper(value: $minutes, in: 0...600) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Duração · \(minutes) min")
                                Text("corrige se pousaste o livro antes").font(.geist(12)).foregroundStyle(Color.soft)
                            }
                        }
                        .accessibilityIdentifier("reading.minutes")
                    } header: {
                        Text(startedText(book))
                    }
                    if let book {
                        Section("Onde ficaste · opcional") {
                            Picker("Em", selection: $byPercent) {
                                Text("Página").tag(false)
                                Text("Percentagem").tag(true)
                            }
                            .pickerStyle(.segmented)
                            if byPercent {
                                Stepper("\(percent)%", value: $percent, in: 0...100)
                            } else {
                                Stepper("Página \(page)", value: $page, in: 0...book.pages)
                            }
                        }
                    }
                    Section {
                        TextField("Uma linha sobre esta sessão", text: $note, axis: .vertical)
                        TextField("Uma citação a guardar", text: $quote, axis: .vertical)
                    } footer: {
                        Text(planned.map { "Planeada: \($0) min · feita: o que guardares." } ?? "")
                    }
                }
                .cadenceList()
                .navigationTitle("Leitura")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Guardar leitura") {
                            var s = session
                            s.minutes = minutes
                            // By percentage only when you changed it: an untouched percentage never moves the page
                            if byPercent, percent != startPercent, let b = book { page = min(b.pages, Int((Double(percent) / 100 * Double(b.pages)).rounded())) }
                            s.toPage = page
                            s.note = note.isEmpty ? nil : note
                            s.quote = quote.isEmpty ? nil : quote
                            store.save(s)
                            if var b = book { b.page = page; if page >= b.pages { b.finished = Day.today }; store.save(b) }
                            if store.readingMinutes() >= 20, let p = store.due().first(where: { $0.title.lowercased().hasPrefix("read") && store.status($0) == nil }) { store.log(p, .done) }
                            finishing = false
                            dismiss()
                        }
                        .accessibilityIdentifier("reading.save")
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Continuar a ler") { finishing = false } }
                }
            }
        }
    }

    /// «Ao terminar»: the duration as timed, to correct; where you were in the book
    private func finish(_ book: Book?) {
        minutes = Int(elapsed / 60)
        page = book?.page ?? 0
        if let book, book.pages > 0 { percent = min(100, Int((Double(book.page) / Double(book.pages) * 100).rounded())) } else { percent = 0 }
        startPercent = percent
        finishing = true
    }

    /// "Harry Potter · começaste às 22:02"
    private func startedText(_ book: Book?) -> String {
        let start = clock(Day.minuteOfDay(Date(timeIntervalSince1970: session.start / 1000)))
        return (book.map { $0.title + " · " } ?? "") + "começaste às " + start
    }

    private func readingButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.geist(15, .semibold)).foregroundStyle(cream).frame(maxWidth: .infinity).padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.09)).overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1)))
        }
        .buttonStyle(Pressable())
    }
}

/// What a project's unit shows; the English unit is what's saved
fileprivate func projectUnitLabel(_ unit: String) -> String {
    ["pages": "páginas", "words": "palavras", "hours": "horas"][unit] ?? unit
}

struct ProjectsView: View {
    @EnvironmentObject var store: Store
    @State private var editing: Project?

    var body: some View {
        Screen(glow: .mint) {
            ForEach(store.all(Project.self).filter { !$0.archived }.sorted { $0.deadline < $1.deadline }) { p in
                let pace = store.pace(p)
                let late = pace.finish.map { $0 > p.deadline } ?? (p.done < p.target)
                Button { editing = p } label: {
                    Card(tint: late ? .warn : .mint) {
                        HStack {
                            Text(p.title).font(.geist(17, .bold))
                            Spacer()
                            Chip(text: "até \(Day.date(p.deadline).formatted(.dateTime.day().month()))", color: late ? .warn : .good)
                        }
                        Bar(progress: p.done / max(1, p.target), area: .mint)
                        Text("\(kg(p.done)) de \(kg(p.target)) \(projectUnitLabel(p.unit)) · precisas de \(String(format: "%.1f", pace.needed))/dia, fazes \(String(format: "%.1f", pace.perDay))/dia").font(.geist(12.5)).foregroundStyle(Color.soft)
                        if let f = pace.finish { Text(late ? "A este ritmo: \(Day.date(f).formatted(.dateTime.day().month())), depois do prazo. Junta blocos de trabalho focado." : "No bom caminho: acabas a \(Day.date(f).formatted(.dateTime.day().month())).").font(.geist(12.5)).foregroundStyle(late ? Color.warn : Color.good) }
                        ForEach(p.milestones.filter { !$0.done }.prefix(3)) { m in
                            HStack { Image(systemName: "flag").foregroundStyle(Color.soft); Text(m.title).font(.geist(13)); Spacer(); Text(Day.date(m.due).formatted(.dateTime.day().month())).font(.geist(12)).foregroundStyle(Color.soft) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            PrimaryButton(title: "Novo projeto") { editing = Project(title: "", deadline: Day.add(60, to: Day.today)) }
        }
        .navigationTitle("Projetos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ProjectEditor(project: $0) }
    }
}

struct ProjectEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var project: Project
    @State private var log = ""
    @State private var milestone = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Título (p. ex. Tese)", text: $project.title)
                    DatePicker("Prazo", selection: Binding(get: { Day.date(project.deadline) }, set: { project.deadline = Day.key($0) }), displayedComponents: .date)
                    Picker("Medido em", selection: $project.unit) { Text("Páginas").tag("pages"); Text("Palavras").tag("words"); Text("Horas").tag("hours") }
                    TextField("Meta", value: $project.target, format: .number).keyboardType(.decimalPad)
                    TextField("Já feito", value: $project.startAmount, format: .number).keyboardType(.decimalPad)
                }
                Section("Registar progresso") {
                    HStack { TextField("\(projectUnitLabel(project.unit).capitalized) hoje", text: $log).keyboardType(.decimalPad); Button("Adicionar") { if let v = Double(log.replacingOccurrences(of: ",", with: ".")) { project.logs.append(ProgressLog(date: Day.today, amount: v)); log = "" } } }
                    ForEach(Array(project.logs.suffix(5).reversed().enumerated()), id: \.offset) { _, l in HStack { Text(Day.date(l.date).formatted(.dateTime.day().month())); Spacer(); Text("+\(kg(l.amount))") } }
                }
                Section("Marcos") {
                    ForEach($project.milestones) { $m in
                        HStack {
                            Button { m.done.toggle() } label: { Image(systemName: m.done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                            TextField("Marco", text: $m.title)
                            DatePicker("", selection: Binding(get: { Day.date(m.due) }, set: { m.due = Day.key($0) }), displayedComponents: .date).labelsHidden()
                        }
                    }
                    HStack { TextField("Novo marco", text: $milestone); Button("Adicionar") { project.milestones.append(Milestone(title: milestone, due: project.deadline)); milestone = "" }.disabled(milestone.isEmpty) }
                }
                if store.record(Project.self, project.id) != nil {
                    Button("Arquivar", role: .destructive) { project.archived = true; store.save(project); dismiss() }
                }
            }
            .cadenceList()
            .navigationTitle(project.title.isEmpty ? "Novo projeto" : project.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar") { store.save(project); dismiss() }.disabled(project.title.isEmpty) }
            }
        }
    }
}
