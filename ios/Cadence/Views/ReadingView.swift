// Reading: books with pace and a finish date, quotes, and reading mode (press play: warm dark screen kept on,
// a timer that survives locking, Do Not Disturb through a Shortcut you set up once). Projects live here too.
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
                            Text(b.title).font(.system(size: 17, weight: .bold))
                            if !b.author.isEmpty { Text(b.author).font(.system(size: 13)).foregroundStyle(Color.soft) }
                            Bar(progress: Double(b.page) / Double(max(1, b.pages)), area: .read)
                            let pace = store.readingPace(b)
                            Text("p. \(b.page) of \(b.pages)" + (pace.finish.map { " · done by \(Day.date($0).formatted(.dateTime.day().month()))" } ?? "")).font(.system(size: 12)).foregroundStyle(Color.soft)
                        }
                    }
                    PrimaryButton(title: "▶  Read now", area: .read) { reading = true }
                }
            }
            Card {
                HStack { Eyebrow(text: "Books", icon: "books.vertical.fill"); Spacer(); Button { editing = Book(title: "") } label: { Label("Add", systemImage: "plus").font(.system(size: 13, weight: .semibold)) }.tint(.read) }
                ForEach(store.all(Book.self).sorted { ($0.finished ?? "9") > ($1.finished ?? "9") }) { b in
                    Button { editing = b } label: {
                        HStack {
                            BookCover(book: b).frame(width: 26, height: 38)
                            VStack(alignment: .leading) { Text(b.title).font(.system(size: 14, weight: .semibold)); Text(b.finished.map { "finished \(Day.date($0).formatted(.dateTime.day().month().year()))" } ?? "p. \(b.page) / \(b.pages)").font(.system(size: 11.5)).foregroundStyle(Color.soft) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
                let year = String(Day.today.prefix(4))
                Text("\(store.all(Book.self).filter { $0.finished?.hasPrefix(year) ?? false }.count) finished in \(year)").font(.system(size: 12)).foregroundStyle(Color.faint)
            }
            let quotes = store.all(ReadingSession.self).filter { $0.quote != nil }.sorted { $0.start > $1.start }.prefix(5)
            if !quotes.isEmpty {
                Card {
                    Eyebrow(text: "Quotes", icon: "quote.opening")
                    ForEach(Array(quotes)) { q in Text("“\(q.quote!)”").font(.system(size: 14, design: .serif)).italic() }
                }
            }
            if let rs = store.readingAndSleep() {
                Card(tint: .sleep) {
                    Eyebrow(text: "Reading and sleep", icon: "moon.stars", color: .sleep)
                    Text("After evenings with 15+ minutes of reading you slept \(duration(rs.with)), against \(duration(rs.without)) without (\(rs.nights) nights). Pattern, not proof.").font(.system(size: 13))
                }
            }
            NavigationLink { ProjectsView() } label: { Text("Projects and deadlines").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.mint) }
        }
        .navigationTitle("Reading")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { BookEditor(book: $0) }
        .fullScreenCover(isPresented: $reading) { ReadingMode() }
    }
}

struct BookCover: View {
    var book: Book
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [Color(hue: book.hue, saturation: 0.55, brightness: 0.45), Color(hue: book.hue, saturation: 0.6, brightness: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Text(book.title).font(.system(size: 8, design: .serif)).foregroundStyle(Color(hex: 0xF1D9A8)).padding(4).minimumScaleFactor(0.5), alignment: .center)
    }
}

struct BookEditor: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var book: Book
    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $book.title)
                TextField("Author", text: $book.author)
                Stepper("\(book.pages) pages", value: $book.pages, in: 20...2000, step: 10)
                Stepper("On page \(book.page)", value: $book.page, in: 0...book.pages, step: 1)
                Toggle("Finished", isOn: Binding(get: { book.finished != nil }, set: { book.finished = $0 ? Day.today : nil; if $0 { book.page = book.pages } }))
                if store.record(Book.self, book.id) != nil { Button("Delete", role: .destructive) { store.remove(book); dismiss() } }
            }
            .cadenceList()
            .navigationTitle(book.title.isEmpty ? "New book" : book.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if book.hue == 0.58 { book.hue = Double.random(in: 0...1) }; store.save(book); dismiss() }.disabled(book.title.isEmpty) }
            }
        }
    }
}

struct ReadingMode: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
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

    private var elapsed: Double { (paused ?? now).timeIntervalSince(Date(timeIntervalSince1970: session.start / 1000)) - pausedTotal }

    var body: some View {
        let book = store.currentBook
        ZStack {
            RadialGradient(colors: [Color(hex: 0x2B2113), Color(hex: 0x07090E)], center: .top, startRadius: 0, endRadius: 600).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Button("Do Not Disturb") { openURL(URL(string: "shortcuts://run-shortcut?name=Cadence%20Reading")!) }.font(.system(size: 13)).foregroundStyle(Color(hex: 0xF6EAD2, opacity: 0.6))
                    Spacer()
                    Button("End") { finishing = true; page = book?.page ?? 0 }.foregroundStyle(Color(hex: 0xF6EAD2, opacity: 0.6))
                }
                Spacer()
                if let book { BookCover(book: book).frame(width: 110, height: 160).shadow(color: .black.opacity(0.7), radius: 20, y: 14) }
                ZStack {
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 6)
                    Circle().trim(from: 0, to: min(1, elapsed / Double(goal * 60))).stroke(LinearGradient(colors: [.read, .read2], startPoint: .top, endPoint: .bottom), style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                    VStack {
                        Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)).font(.system(size: 44, weight: .medium, design: .monospaced)).foregroundStyle(Color(hex: 0xF6EAD2))
                        Text("of \(goal) min" + (book.map { " · p. \($0.page)" } ?? "")).font(.system(size: 13)).foregroundStyle(Color(hex: 0xF6EAD2, opacity: 0.5))
                    }
                }
                .frame(width: 220, height: 220)
                Text("Screen dimmed and kept on. Notifications wait.").font(.system(size: 12)).foregroundStyle(Color(hex: 0xF6EAD2, opacity: 0.4))
                Spacer()
                HStack {
                    SoftButton(title: paused == nil ? "Pause" : "Resume") {
                        if let p = paused { pausedTotal += Date().timeIntervalSince(p); paused = nil } else { paused = Date() }
                    }
                    SoftButton(title: "Note") { finishing = true; page = book?.page ?? 0 }
                }
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .onReceive(timer) { now = $0 }
        .onAppear {
            session = ReadingSession(bookId: book?.id, fromPage: book?.page ?? 0)
            UIApplication.shared.isIdleTimerDisabled = true
            UIScreen.main.brightness = max(0.15, UIScreen.main.brightness * 0.6)
        }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $finishing) {
            NavigationStack {
                Form {
                    if let book { Stepper("Now on page \(page)", value: $page, in: 0...book.pages) }
                    TextField("A line about this session", text: $note, axis: .vertical)
                    TextField("A quote worth keeping", text: $quote, axis: .vertical)
                }
                .cadenceList()
                .navigationTitle("\(Int(elapsed / 60)) minutes read")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            var s = session
                            s.minutes = Int(elapsed / 60)
                            s.toPage = page
                            s.note = note.isEmpty ? nil : note
                            s.quote = quote.isEmpty ? nil : quote
                            store.save(s)
                            if var b = book { b.page = page; if page >= b.pages { b.finished = Day.today }; store.save(b) }
                            if store.readingMinutes() >= 20, let p = store.due().first(where: { $0.title.lowercased().hasPrefix("read") && store.status($0) == nil }) { store.log(p, .done) }
                            finishing = false
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .cancellationAction) { Button("Keep reading") { finishing = false } }
                }
            }
        }
    }
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
                            Text(p.title).font(.system(size: 17, weight: .bold))
                            Spacer()
                            Chip(text: "due \(Day.date(p.deadline).formatted(.dateTime.day().month()))", color: late ? .warn : .good)
                        }
                        Bar(progress: p.done / max(1, p.target), area: .mint)
                        Text("\(kg(p.done)) of \(kg(p.target)) \(p.unit) · need \(String(format: "%.1f", pace.needed))/day, doing \(String(format: "%.1f", pace.perDay))/day").font(.system(size: 12.5)).foregroundStyle(Color.soft)
                        if let f = pace.finish { Text(late ? "At this pace: \(Day.date(f).formatted(.dateTime.day().month())), after the deadline. Add deep-work blocks." : "On track: done by \(Day.date(f).formatted(.dateTime.day().month())).").font(.system(size: 12.5)).foregroundStyle(late ? Color.warn : Color.good) }
                        ForEach(p.milestones.filter { !$0.done }.prefix(3)) { m in
                            HStack { Image(systemName: "flag").foregroundStyle(Color.soft); Text(m.title).font(.system(size: 13)); Spacer(); Text(Day.date(m.due).formatted(.dateTime.day().month())).font(.system(size: 12)).foregroundStyle(Color.soft) }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            PrimaryButton(title: "New project") { editing = Project(title: "", deadline: Day.add(60, to: Day.today)) }
        }
        .navigationTitle("Projects")
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
                    TextField("Title (e.g. Thesis)", text: $project.title)
                    DatePicker("Deadline", selection: Binding(get: { Day.date(project.deadline) }, set: { project.deadline = Day.key($0) }), displayedComponents: .date)
                    Picker("Measured in", selection: $project.unit) { Text("Pages").tag("pages"); Text("Words").tag("words"); Text("Hours").tag("hours") }
                    TextField("Target", value: $project.target, format: .number).keyboardType(.decimalPad)
                    TextField("Already done", value: $project.startAmount, format: .number).keyboardType(.decimalPad)
                }
                Section("Log progress") {
                    HStack { TextField("\(project.unit.capitalized) today", text: $log).keyboardType(.decimalPad); Button("Add") { if let v = Double(log.replacingOccurrences(of: ",", with: ".")) { project.logs.append(ProgressLog(date: Day.today, amount: v)); log = "" } } }
                    ForEach(Array(project.logs.suffix(5).reversed().enumerated()), id: \.offset) { _, l in HStack { Text(Day.date(l.date).formatted(.dateTime.day().month())); Spacer(); Text("+\(kg(l.amount))") } }
                }
                Section("Milestones") {
                    ForEach($project.milestones) { $m in
                        HStack {
                            Button { m.done.toggle() } label: { Image(systemName: m.done ? "checkmark.circle.fill" : "circle") }.buttonStyle(.plain)
                            TextField("Milestone", text: $m.title)
                            DatePicker("", selection: Binding(get: { Day.date(m.due) }, set: { m.due = Day.key($0) }), displayedComponents: .date).labelsHidden()
                        }
                    }
                    HStack { TextField("New milestone", text: $milestone); Button("Add") { project.milestones.append(Milestone(title: milestone, due: project.deadline)); milestone = "" }.disabled(milestone.isEmpty) }
                }
                if store.record(Project.self, project.id) != nil {
                    Button("Archive", role: .destructive) { project.archived = true; store.save(project); dismiss() }
                }
            }
            .cadenceList()
            .navigationTitle(project.title.isEmpty ? "New project" : project.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.save(project); dismiss() }.disabled(project.title.isEmpty) }
            }
        }
    }
}
