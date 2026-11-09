// Foods you put together: a toastie, a hot dog, a burger, a pizza, with what's in them, the sauces and the sides. Values
// are typical estimates for what's normally used of each. Pure, so it can be tested; the screen is FoodBuildView.
import Foundation

struct BuildOption: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var kcal: Double, protein: Double, carbs: Double, fat: Double

    init(_ name: String, _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double) {
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
    }

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

struct BuildSection: Identifiable, Hashable {
    var id: String { title }
    var title: String
    var single = false // exactly one, like the bread; otherwise any number
    var picked: Set<String> = [] // what comes with it unless you change it
    var scales = true // false: counted as they are, whatever the size (the sauces on a pizza)
    var options: [BuildOption]
}

struct BuildSize: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var factor: Double
}

struct BuildChoice: Equatable {
    var picked: [String: Set<String>]
    var size: String?
}

struct BuildFood: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var portion: String
    var sections: [BuildSection]
    var sizes: [BuildSize] = []
    var startSize: String? = nil

    var start: BuildChoice {
        var picked: [String: Set<String>] = [:]
        for s in sections { picked[s.title] = s.picked }
        return BuildChoice(picked: picked, size: startSize ?? sizes.first?.name)
    }

    func factor(_ c: BuildChoice) -> Double { sizes.first { $0.name == c.size }?.factor ?? 1 }

    func total(_ c: BuildChoice) -> Macros {
        let k = factor(c)
        var sum = Macros()
        for s in sections {
            for o in s.options where c.picked[s.title]?.contains(o.name) == true { sum = sum + o.macros * (s.scales ? k : 1) }
        }
        return sum
    }

    /// One bread at a time; anything else on and off
    func toggling(_ option: String, in section: BuildSection, _ c: BuildChoice) -> BuildChoice {
        var next = c
        if section.single {
            next.picked[section.title] = [option]
        } else {
            var set = c.picked[section.title] ?? []
            if set.contains(option) { set.remove(option) } else { set.insert(option) }
            next.picked[section.title] = set
        }
        return next
    }

    /// The name as logged: what went in it, and the bread or meat only when it isn't the usual one
    func label(_ c: BuildChoice) -> String {
        var parts: [String] = []
        for s in sections {
            let chosen = s.options.filter { c.picked[s.title]?.contains($0.name) == true }.map(\.name)
            if s.single && Set(chosen) == s.picked { continue }
            parts += chosen.map { $0.lowercased() }
        }
        return parts.isEmpty ? name : name + " · " + parts.joined(separator: ", ")
    }

    func portionText(_ c: BuildChoice) -> String { c.size ?? portion }

    func item(_ c: BuildChoice) -> FoodItem {
        let m = total(c).rounded
        var item = FoodItem(name: label(c), kcal: m.kcal, protein: m.protein, carbs: m.carbs, fat: m.fat,
                            group: FoodGoals.legacyGroup(name: name), portionText: portionText(c))
        item.quantityConfirmed = true // you said what's in it
        return item
    }
}

enum FoodBuilds {
    private static let cheese = BuildOption("Queijo", 70, 4.5, 0.3, 5.5)
    private static let ham = BuildOption("Fiambre", 45, 7, 1, 1.5)
    private static let bacon = BuildOption("Bacon", 110, 7, 0.3, 9)
    private static let egg = BuildOption("Ovo estrelado", 98, 6.8, 0.4, 7.5)
    private static let lettuce = BuildOption("Alface", 3, 0.2, 0.5, 0)
    private static let tomato = BuildOption("Tomate", 5, 0.2, 1, 0)
    private static let onion = BuildOption("Cebola", 8, 0.2, 2, 0)
    private static let pickles = BuildOption("Pickles", 4, 0.1, 0.8, 0)
    private static let butter = BuildOption("Manteiga", 72, 0.1, 0, 8)
    private static let honey = BuildOption("Mel", 61, 0.1, 16.5, 0)

    private static let mayo = BuildOption("Maionese", 100, 0.2, 0.2, 11)
    private static let ketchup = BuildOption("Ketchup", 16, 0.2, 3.8, 0)
    private static let mustard = BuildOption("Mostarda", 7, 0.4, 0.5, 0.4)
    private static let bbq = BuildOption("Molho barbecue", 25, 0.1, 6, 0.1)
    private static let garlic = BuildOption("Molho de alho", 90, 0.1, 0.5, 10)
    private static let burgerSauce = BuildOption("Molho de hambúrguer", 65, 0.2, 2, 6)
    private static let cocktail = BuildOption("Molho cocktail", 60, 0.1, 2, 5.5)
    private static let spicy = BuildOption("Piri-piri", 12, 0.1, 0.5, 1.1)
    private static let sauces = [mayo, ketchup, mustard, bbq, garlic, burgerSauce, cocktail, spicy]

    private static let spreads = [butter, honey, BuildOption("Compota", 50, 0.1, 12, 0), BuildOption("Creme de chocolate", 110, 1, 11, 6.5),
                                  BuildOption("Manteiga de amendoim", 95, 4, 3, 8), BuildOption("Queijo creme", 50, 1.5, 1, 4.5)]
    private static let sliced = BuildOption("Pão de forma", 150, 5, 28, 2)
    private static let roll = BuildOption("Pão", 135, 4.5, 25, 1.5)

    private static let fries = BuildOption("Batata frita", 340, 4, 42, 17)
    private static let sides = [fries, BuildOption("Batata-doce frita", 320, 3, 45, 14), BuildOption("Aros de cebola", 300, 4, 32, 17),
                                BuildOption("Nuggets", 280, 15, 18, 17), BuildOption("Salada de couve", 150, 1, 12, 11), BuildOption("Salada", 20, 1, 3.5, 0.2)]

    private static func burger(sides picked: Set<String>) -> BuildFood {
        BuildFood(name: "Hambúrguer", portion: "1", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão de hambúrguer"], options: [
                BuildOption("Pão de hambúrguer", 200, 7, 36, 3.5), BuildOption("Brioche", 260, 7, 38, 9), BuildOption("Sem pão", 0, 0, 0, 0)]),
            BuildSection(title: "Carne", single: true, picked: ["Vaca"], options: [
                BuildOption("Vaca", 300, 30, 0, 20), BuildOption("Vaca dupla", 600, 60, 0, 40), BuildOption("Frango grelhado", 180, 30, 0, 6),
                BuildOption("Frango panado", 350, 22, 22, 19), BuildOption("Vegetariano", 200, 15, 15, 9)]),
            BuildSection(title: "Ingredientes", picked: ["Queijo", "Alface", "Tomate"], options: [
                cheese, lettuce, tomato, onion, BuildOption("Cebola caramelizada", 45, 0.5, 7, 2), pickles, bacon, egg, BuildOption("Cogumelos", 15, 1.5, 1, 0.5)]),
            BuildSection(title: "Molhos", picked: ["Maionese", "Ketchup"], options: sauces),
            BuildSection(title: "Acompanhamentos", picked: picked, options: sides),
        ])
    }

    private static func pizza(size: String) -> BuildFood {
        BuildFood(name: "Pizza", portion: "1 média", sections: [
            BuildSection(title: "Massa", single: true, picked: ["Normal"], options: [
                BuildOption("Normal", 640, 20, 120, 8), BuildOption("Fina", 480, 15, 90, 6), BuildOption("Grossa", 800, 25, 150, 10), BuildOption("Borda recheada", 950, 36, 130, 30)]),
            BuildSection(title: "Base", picked: ["Molho de tomate", "Mozzarella"], options: [
                BuildOption("Molho de tomate", 60, 2, 10, 1.5), BuildOption("Mozzarella", 400, 26, 4, 30), BuildOption("Natas", 180, 1.5, 3, 18)]),
            BuildSection(title: "Ingredientes", options: [
                BuildOption("Fiambre", 100, 15, 2, 4), BuildOption("Pepperoni", 350, 15, 2, 30), BuildOption("Chouriço", 350, 17, 2, 30), BuildOption("Bacon", 300, 15, 0, 26),
                BuildOption("Frango", 170, 30, 0, 5), BuildOption("Atum", 150, 25, 0, 5), BuildOption("Carne picada", 300, 25, 0, 22), BuildOption("Cogumelos", 25, 3, 3, 0.5),
                BuildOption("Cebola", 30, 1, 7, 0), BuildOption("Pimento", 20, 1, 4, 0.2), BuildOption("Azeitonas", 80, 0.5, 2, 8), BuildOption("Ananás", 50, 0.5, 13, 0),
                BuildOption("Milho", 70, 2, 14, 1), BuildOption("Tomate fresco", 20, 1, 4, 0.2), BuildOption("Rúcula", 5, 0.5, 0.5, 0.1), BuildOption("Queijo extra", 200, 13, 2, 15)]),
            BuildSection(title: "Molhos", scales: false, options: [BuildOption("Azeite picante", 110, 0, 0, 12), garlic, bbq, mayo, ketchup]),
        ], sizes: [BuildSize(name: "1 fatia", factor: 0.25), BuildSize(name: "2 fatias", factor: 0.5), BuildSize(name: "3 fatias", factor: 0.75),
                   BuildSize(name: "Pizza média inteira", factor: 1), BuildSize(name: "Pizza familiar", factor: 1.6)], startSize: size)
    }

    /// By the catalogue's name: choosing one of these opens the screen to put it together
    static let all: [String: BuildFood] = [
        "Tosta mista": BuildFood(name: "Tosta mista", portion: "1 tosta", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão de forma"], options: [
                sliced, BuildOption("Pão de sementes", 170, 7, 26, 4), BuildOption("Pão caseiro", 200, 7, 40, 1.5)]),
            BuildSection(title: "Ingredientes", picked: ["Fiambre", "Queijo", "Manteiga"], options: [
                ham, BuildOption("Queijo", 140, 9, 0.5, 11), butter, tomato, egg, bacon, BuildOption("Frango desfiado", 100, 18, 0, 3)]),
            BuildSection(title: "Molhos", options: sauces),
        ]),
        "Cachorro": BuildFood(name: "Cachorro", portion: "1 cachorro-quente", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão de cachorro"], options: [
                BuildOption("Pão de cachorro", 150, 5, 28, 2.5), BuildOption("Baguete", 220, 8, 44, 1.5)]),
            BuildSection(title: "Salsicha", single: true, picked: ["1 salsicha"], options: [
                BuildOption("1 salsicha", 130, 6, 1, 11.5), BuildOption("2 salsichas", 260, 12, 2, 23), BuildOption("Salsicha de frango", 100, 7, 2, 7), BuildOption("Salsicha alemã", 260, 11, 2, 23)]),
            BuildSection(title: "Ingredientes", picked: ["Queijo ralado", "Batata palha"], options: [
                BuildOption("Queijo ralado", 70, 4, 0.3, 6), BuildOption("Batata palha", 80, 1, 8, 5), BuildOption("Cebola frita", 60, 0.7, 6, 4), onion, pickles,
                BuildOption("Chucrute", 10, 0.5, 2, 0), bacon, BuildOption("Milho", 25, 0.8, 5, 0.3)]),
            BuildSection(title: "Molhos", picked: ["Ketchup", "Mostarda", "Maionese"], options: sauces),
        ]),
        "Hambúrguer": burger(sides: []),
        "Hambúrguer com batatas fritas": burger(sides: ["Batata frita"]),
        "Pizza": pizza(size: "2 fatias"),
        "Pizza inteira": pizza(size: "Pizza média inteira"),
        "Pão ou sandes": BuildFood(name: "Pão", portion: "1", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão"], options: [
                roll, sliced, BuildOption("Pão integral", 130, 6, 23, 2), BuildOption("Broa", 145, 3.5, 29, 1.8), BuildOption("Bolo do caco", 260, 8, 50, 3), BuildOption("Croissant", 230, 5, 26, 12)]),
            BuildSection(title: "Para barrar", options: spreads),
            BuildSection(title: "Recheio", options: [
                ham, BuildOption("Queijo", 70, 4.5, 0.3, 5.5), BuildOption("Peito de peru", 35, 7, 0.5, 0.5), BuildOption("Presunto", 60, 8, 0, 3), BuildOption("Chouriço", 100, 5, 0.5, 8.5),
                BuildOption("Atum", 120, 18, 0, 5), BuildOption("Frango desfiado", 100, 18, 0, 3), egg, lettuce, tomato]),
            BuildSection(title: "Molhos", options: [mayo, mustard, ketchup]),
        ]),
        "Torradas com manteiga": BuildFood(name: "Torradas", portion: "2 fatias", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão de forma"], options: [sliced, BuildOption("Pão caseiro", 200, 7, 40, 1.5), BuildOption("Pão integral", 160, 8, 27, 2.5)]),
            BuildSection(title: "Para barrar", picked: ["Manteiga"], options: spreads),
        ]),
        "Bifana": BuildFood(name: "Bifana", portion: "1 sandes", sections: [
            BuildSection(title: "Carne", single: true, picked: ["1 bifana"], options: [BuildOption("1 bifana", 230, 30, 1, 12), BuildOption("Bifana dupla", 460, 60, 2, 24)]),
            BuildSection(title: "Pão", single: true, picked: ["Pão"], options: [roll, BuildOption("Bolo do caco", 260, 8, 50, 3)]),
            BuildSection(title: "Ingredientes", picked: ["Molho da bifana"], options: [BuildOption("Molho da bifana", 60, 0.5, 3, 5), cheese, egg, bacon, BuildOption("Cebola frita", 60, 0.7, 6, 4)]),
            BuildSection(title: "Molhos", picked: ["Mostarda"], options: [mustard, spicy, mayo, ketchup]),
            BuildSection(title: "Acompanhamentos", options: sides),
        ]),
        "Prego no pão": BuildFood(name: "Prego no pão", portion: "1 sandes", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Pão"], options: [roll, BuildOption("Bolo do caco", 260, 8, 50, 3)]),
            BuildSection(title: "Carne", single: true, picked: ["Bife de vaca"], options: [BuildOption("Bife de vaca", 250, 30, 0, 14), BuildOption("Bife de peru", 170, 32, 0, 4)]),
            BuildSection(title: "Ingredientes", picked: ["Manteiga"], options: [butter, cheese, ham, egg, lettuce, tomato, BuildOption("Cebola frita", 60, 0.7, 6, 4)]),
            BuildSection(title: "Molhos", picked: ["Mostarda"], options: [mustard, spicy, mayo, ketchup]),
            BuildSection(title: "Acompanhamentos", options: sides),
        ]),
        "Francesinha": BuildFood(name: "Francesinha", portion: "1, com molho", sections: [
            BuildSection(title: "Recheio", picked: ["Bife", "Linguiça", "Salsicha fresca", "Fiambre"], options: [
                BuildOption("Bife", 200, 25, 0, 11), BuildOption("Linguiça", 130, 7, 1, 11), BuildOption("Salsicha fresca", 130, 6, 1, 11.5), ham, BuildOption("Mortadela", 70, 4, 1, 6)]),
            BuildSection(title: "Por fora", picked: ["Pão de forma", "Queijo derretido", "Molho de francesinha"], options: [
                sliced, BuildOption("Queijo derretido", 280, 18, 1, 22), BuildOption("Molho de francesinha", 150, 2, 10, 10)]),
            BuildSection(title: "Extras", picked: ["Ovo estrelado"], options: [egg, fries]),
        ]),
        "Kebab": BuildFood(name: "Kebab", portion: "1 wrap", sections: [
            BuildSection(title: "Pão", single: true, picked: ["Wrap"], options: [BuildOption("Wrap", 200, 5, 33, 5), BuildOption("Pita", 170, 6, 33, 1), BuildOption("Prato, sem pão", 0, 0, 0, 0)]),
            BuildSection(title: "Carne", single: true, picked: ["Frango"], options: [BuildOption("Frango", 350, 33, 4, 22), BuildOption("Vaca", 420, 28, 4, 32), BuildOption("Falafel", 300, 12, 30, 15)]),
            BuildSection(title: "Ingredientes", picked: ["Alface", "Tomate", "Cebola"], options: [lettuce, tomato, onion, BuildOption("Couve roxa", 5, 0.3, 1, 0), pickles, BuildOption("Queijo feta", 75, 4, 1, 6)]),
            BuildSection(title: "Molhos", picked: ["Molho de alho"], options: [garlic, BuildOption("Molho de iogurte", 30, 1, 1.5, 2.5), spicy, ketchup, mayo]),
            BuildSection(title: "Acompanhamentos", options: sides),
        ]),
        "Omelete": BuildFood(name: "Omelete", portion: "2 ovos", sections: [
            BuildSection(title: "Ovos", single: true, picked: ["2 ovos"], options: [BuildOption("2 ovos", 190, 13, 1, 15), BuildOption("3 ovos", 280, 19, 1.5, 22)]),
            BuildSection(title: "Ingredientes", picked: ["Queijo"], options: [
                cheese, ham, bacon, BuildOption("Cogumelos", 15, 1.5, 1, 0.5), tomato, onion, BuildOption("Espinafres", 10, 1, 1, 0.2), BuildOption("Atum", 120, 18, 0, 5), BuildOption("Chouriço", 100, 5, 0.5, 8.5)]),
        ]),
    ]

    static func named(_ name: String) -> BuildFood? { all[name] }
}
