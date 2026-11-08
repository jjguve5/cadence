// You: Pip and your level, the days you closed, promises, settings and credits. Life holds the areas still coming.
import AuthenticationServices
import CoreImage.CIFilterBuiltins
import SwiftUI

struct YouView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        NavigationStack {
            Screen(glow: .mind) {
                Title(eyebrow: "Nível \(store.level.level) · \(store.totalPoints.formatted()) pontos", title: "Perfil")
                    .padding(.top, 8)
                NavigationLink { PipPage() } label: {
                    Card(tint: .fuel) {
                        HStack(spacing: 14) {
                            PipHead(mood: store.pipMood(), size: 64)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Pip · \(store.pipMood().label)").font(.geist(17, .bold))
                                Text(store.pipLine()).font(.geist(13)).foregroundStyle(Color.soft).lineLimit(3)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Card {
                    Eyebrow(text: "Últimas 4 semanas", icon: "square.grid.3x3.fill")
                    DaysGrid()
                }
                NavigationLink { YouGrowthView() } label: {
                    Card(tint: .mind) {
                        HStack { Eyebrow(text: "Crescimento", icon: "chart.line.uptrend.xyaxis", color: .mind); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Color.faint) }
                        Text("Diário, humor, objetivos, experiências, revisão semanal, idade Cadence, medalhas · esta semana: \(store.challenge().text.lowercased())").font(.geist(13)).foregroundStyle(Color.soft)
                    }
                }
                .accessibilityIdentifier("you.growth")
                .buttonStyle(.plain)
                VStack(spacing: 0) {
                    link("Hábitos", "bell", PromisesView())
                    link("Aprendizagem", "graduationcap", LearningView())
                    link("Definições", "gearshape", SettingsView())
                    link("Créditos", "heart", CreditsView())
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
            ForEach(["S", "T", "Q", "Q", "S", "S", "D"].indices, id: \.self) { i in
                Text(["S", "T", "Q", "Q", "S", "S", "D"][i]).font(.geist(10)).foregroundStyle(Color.faint)
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
                NavigationLink { SmartSetup() } label: { Label("Configuração inteligente: metas a partir do teu corpo e objetivo", systemImage: "wand.and.stars") }
                HStack { Text("Objetivo"); Spacer(); GoalMenu() }
            }
            Section("Sobre ti") {
                TextField("Nome", text: Binding(get: { store.profile.name }, set: { v in store.update { $0.name = v } }))
                DatePicker("Hora de acordar", selection: minuteBinding(\.wakeMinute), displayedComponents: .hourAndMinute)
                Stepper("Sono necessário \(duration(store.profile.sleepNeed))", value: Binding(get: { store.profile.sleepNeed }, set: { v in store.update { $0.sleepNeed = v } }), in: 360...600, step: 15)
                Stepper("Desacelerar \(store.profile.windDownLead) min antes de deitar", value: Binding(get: { store.profile.windDownLead }, set: { v in store.update { $0.windDownLead = v } }), in: 15...90, step: 15)
                Stepper("Meta de passos \(store.profile.stepGoal.formatted())", value: Binding(get: { store.profile.stepGoal }, set: { v in store.update { $0.stepGoal = v } }), in: 2000...20000, step: 500)
            }
            Section {
                DatePicker("Silêncio a partir das", selection: minuteBinding(\.quietStart), displayedComponents: .hourAndMinute)
                DatePicker("Silêncio até às", selection: minuteBinding(\.quietEnd), displayedComponents: .hourAndMinute)
                Stepper("Até \(store.profile.notificationBudget) por dia", value: Binding(get: { store.profile.notificationBudget }, set: { v in store.update { $0.notificationBudget = v } }), in: 3...30)
            } header: { Text("Notificações") } footer: { Text("Essenciais, medicamentos e avisos da hora de saída passam sempre; o resto é ordenado por importância e espera.") }
            Section {
                Picker("Dados de sono e coração", selection: Binding(get: { store.profile.healthSource }, set: { v in store.update { $0.healthSource = v }; Task { await store.refreshHealth(force: true) } })) {
                    Text("Fitbit").tag("fitbit")
                    Text("Só Apple Health").tag("apple")
                }
                if let p = store.appleHealthProblem { Text(p).font(.footnote).foregroundStyle(Color.warn) }
                Button("Ler o Apple Health agora") { Task { await store.refreshAppleHealth(everything: !store.profile.usesBand) } }
            } header: { Text("Dados de saúde") } footer: { Text(store.profile.usesBand ? "Sono, VFC e passos vêm da Air; o peso e a água também vêm do Apple Health. O peso que escreves ganha sempre." : "Tudo vem do Apple Health: sono, VFC, FC em repouso, passos, peso e água. Um Apple Watch dá os melhores dados.") }
            if store.profile.usesBand {
            Section {
                Button("Ligar o Google Health") { Task { await connectGoogle() } }
                if let googleMessage { Text(googleMessage).font(.footnote).foregroundStyle(Color.soft) }
                if let d = store.device {
                    LabeledContent("Pulseira", value: d.name ?? "–")
                    LabeledContent("Bateria", value: d.battery.map { "\($0)%" } ?? "–")
                }
                LabeledContent("Dias com dados", value: "\(store.health.count)")
                if !store.healthErrors.isEmpty {
                    ForEach(store.healthErrors.sorted(by: { $0.key < $1.key }), id: \.key) { k, v in Text("\(k): \(v)").font(.caption2).foregroundStyle(Color.warn) }
                }
            } header: { Text("Fitbit Air") } footer: { Text("Enquanto a app da Google está em testes, o início de sessão dura 7 dias: volta a ligar quando Hoje pedir.") }
            }
            PeopleSection()
            Section {
                ForEach([("fuel", "Comida e água"), ("training", "Treino"), ("care", "Higiene e medicamentos"), ("money", "Dinheiro"), ("wardrobe", "Roupeiro e lavandaria"), ("kitchen", "Cozinha e compras"), ("home", "Casa e documentos"), ("people", "Pessoas"), ("travel", "Viagens"), ("learning", "Aprendizagem")], id: \.0) { key, name in
                    Toggle(name, isOn: Binding(get: { store.profile.on(key) }, set: { on in store.update { p in p.areasOff.removeAll { $0 == key }; if !on { p.areasOff.append(key) } } }))
                }
            } header: { Text("Áreas") } footer: { Text("Começa com pouco e liga as áreas quando as quiseres. A pontuação só conta o que está ligado.") }
            Section {
                LabeledContent("Widgets", value: store.widgetsAvailable ? "a funcionar" : "indisponível com esta assinatura")
            } footer: { Text(store.widgetsAvailable ? "Toca sem largar no ecrã principal e adiciona o Cadence." : "Números em tempo real nos widgets precisam de um App Group, que a assinatura gratuita não dá. Em vez disso, o widget é um conjunto de atalhos: água, escovagem, registo rápido.") }
            Section {
                Button(store.homeCoordinate == nil ? "Estou em casa: lembrar este sítio" : "Estou em casa: atualizar este sítio") { Task { await store.setHomeHere() } }.accessibilityIdentifier("home.set")
            } header: { Text("Casa") } footer: { Text("Usado só neste iPhone, para te lembrar de desfazer o saco do ginásio quando chegas depois de um treino. Sem isto, o lembrete chega 45 minutos depois de acabares.") }
            Section {
                LabeledContent("Estado", value: store.lastSaved.map { "verificado às " + $0.formatted(date: .omitted, time: .shortened) } ?? "sem gravações nesta sessão")
                LabeledContent("Registos", value: "\(store.personalRecordCount)")
                LabeledContent("Cópias locais", value: store.localCopies.first.map { "\(store.localCopies.count) · última \($0.date.formatted(date: .abbreviated, time: .omitted))" } ?? "nenhuma ainda")
                LabeledContent("Por enviar ao servidor", value: "\(store.pendingSendableCount)") // the same count as «Precisa de ação» in Hoje (decision D24)
                Text("As respostas aos hábitos ficam só neste iPhone: não vão para o servidor.").font(.footnote).foregroundStyle(Color.soft) // decision D8
                if let hold = store.syncHold {
                    Text(hold).font(.footnote).foregroundStyle(Color.warn)
                }
                if !store.syncRefused.isEmpty {
                    LabeledContent("Recusados pelo servidor", value: "\(store.syncRefused.count)")
                }
                if store.lastRecoveryArchive != nil {
                    Button("Desfazer a última recuperação", role: .destructive) { try? store.undoRecovery() }
                }
            } header: { Text("Armazenamento local") } footer: {
                Text(store.storageNote ?? "Os teus dados ficam guardados neste iPhone. Cada gravação é verificada antes de substituir a anterior, e há uma cópia local por dia.")
            }
            Section("Os teus dados") {
                ShareLink(item: store.exportJSON(), preview: SharePreview("Cadence export.json")) { Label("Exportar tudo (JSON)", systemImage: "square.and.arrow.up") }
            }
            Section("Servidor") {
                LabeledContent("Endereço", value: store.connection.server)
                Button("Sincronizar agora") { Task { await store.refreshAll(force: true); await store.refreshHealth(force: true) } }
                if let e = store.syncError { Text(e).font(.footnote).foregroundStyle(Color.warn) }
                Button("Esquecer este servidor", role: .destructive) { store.connection = Connection() }
            }
        }
        .cadenceList()
        .navigationTitle("Definições")
    }

    private func connectGoogle() async {
        guard let url = store.googleURL() else { return }
        do {
            let back = try await webAuth.authenticate(using: url, callbackURLScheme: "cadence")
            if back.absoluteString.contains("ok=1") { googleMessage = "Ligado."; store.googleConnected() } else { googleMessage = "Não ficou ligado. Tenta de novo." }
        } catch {
            googleMessage = "Cancelado."
        }
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("Pip") { Text("Uma personagem original do Cadence, animada no After Effects e reproduzida com Lottie.") }
            Section("Dados de exercícios") { Text("Dados de exercícios da RepDB (repdb.co)") }
            Section("Mapa do corpo") { Text("Baseado no GymMane, de InlitX (GPL-3.0)") }
            Section("Ciência") {
                Text("Prontidão face à tua própria referência de 14 dias; regularidade do sono segundo Windred et al., Sleep 2024; sinais de doença segundo Natarajan et al., npj Digital Medicine 2020.")
            }
        }
        .cadenceList()
        .navigationTitle("Créditos")
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
                Text("Lê o código QR de configuração com a app Câmara, ou cola o endereço e o token do teu servidor.").multilineTextAlignment(.center).foregroundStyle(Color.soft)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            Card {
                TextField("Endereço do servidor", text: $server).textInputAutocapitalization(.never).keyboardType(.URL).autocorrectionDisabled()
                Divider()
                SecureField("Token", text: $token)
            }
            PrimaryButton(title: "Ligar") {
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
                        TextField("Nome da pessoa", text: $name)
                        Button("Convidar") { Task { await add() } }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    if let added {
                        VStack(alignment: .center, spacing: 8) {
                            if let qr = Self.qr(added.setup) { Image(uiImage: qr).interpolation(.none).resizable().frame(width: 200, height: 200) }
                            Text("\(added.name) lê isto com a câmara do iPhone depois de instalar o Cadence. Só aparece uma vez.").font(.footnote).multilineTextAlignment(.center)
                            ShareLink(item: added.setup) { Label("Enviar a ligação de configuração", systemImage: "square.and.arrow.up") }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color.warn) }
                } header: { Text("Pessoas") } footer: { Text("Cada pessoa tem o seu token e os seus dados no teu servidor; ninguém vê os dos outros.") }
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
              let a = try? JSONDecoder().decode(Added.self, from: data) else { error = "Não foi possível adicionar: verifica a ligação."; return }
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
