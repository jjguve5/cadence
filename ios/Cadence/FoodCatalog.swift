// Common foods and meals with typical portions, for logging without knowing the numbers, plus a name search in
// Open Food Facts for packaged products. Values are typical estimates per normal portion.
import Foundation

struct CommonFood: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var portion: String // what a normal portion is
    var kcal: Double
    var protein: Double
    var group: String
    var words = "" // other names to search by
}

let commonFoods: [CommonFood] = [
    // Breakfast and snacks
    CommonFood(name: "Banana", portion: "1 medium", kcal: 105, protein: 1.3, group: "Fruit", words: "banana"),
    CommonFood(name: "Apple", portion: "1 medium", kcal: 95, protein: 0.5, group: "Fruit", words: "maçã maca"),
    CommonFood(name: "Orange", portion: "1 medium", kcal: 62, protein: 1.2, group: "Fruit", words: "laranja"),
    CommonFood(name: "Pear", portion: "1 medium", kcal: 100, protein: 0.6, group: "Fruit", words: "pera"),
    CommonFood(name: "Grapes", portion: "1 cup", kcal: 104, protein: 1.1, group: "Fruit", words: "uvas"),
    CommonFood(name: "Egg, boiled or fried", portion: "1 egg", kcal: 80, protein: 6.5, group: "Breakfast", words: "ovo ovos"),
    CommonFood(name: "Scrambled eggs", portion: "2 eggs", kcal: 200, protein: 13, group: "Breakfast", words: "ovos mexidos"),
    CommonFood(name: "Omelette", portion: "2 eggs, cheese", kcal: 290, protein: 19, group: "Breakfast", words: "omelete"),
    CommonFood(name: "Toast with butter", portion: "2 slices", kcal: 230, protein: 6, group: "Breakfast", words: "torrada manteiga"),
    CommonFood(name: "Pão with cheese", portion: "1 roll", kcal: 280, protein: 12, group: "Breakfast", words: "pao com queijo bread cheese"),
    CommonFood(name: "Pão with ham and cheese", portion: "1 roll", kcal: 330, protein: 17, group: "Breakfast", words: "pao misto sandes mista fiambre"),
    CommonFood(name: "Tosta mista", portion: "1 toastie", kcal: 380, protein: 19, group: "Breakfast", words: "toastie ham cheese"),
    CommonFood(name: "Croissant", portion: "1", kcal: 230, protein: 5, group: "Breakfast", words: "croissant"),
    CommonFood(name: "Pastel de nata", portion: "1", kcal: 220, protein: 3.5, group: "Breakfast", words: "nata custard tart"),
    CommonFood(name: "Oatmeal with milk", portion: "1 bowl", kcal: 300, protein: 12, group: "Breakfast", words: "papas aveia porridge oats"),
    CommonFood(name: "Granola with yogurt", portion: "1 bowl", kcal: 350, protein: 13, group: "Breakfast", words: "granola iogurte"),
    CommonFood(name: "Greek yogurt", portion: "1 pot 170 g", kcal: 160, protein: 15, group: "Dairy", words: "iogurte grego"),
    CommonFood(name: "Skyr", portion: "1 pot 150 g", kcal: 95, protein: 16, group: "Dairy", words: "skyr iogurte"),
    CommonFood(name: "Protein yogurt", portion: "1 pot 200 g", kcal: 130, protein: 20, group: "Dairy", words: "iogurte proteico high protein"),
    CommonFood(name: "Milk", portion: "1 glass 250 ml", kcal: 120, protein: 8, group: "Dairy", words: "leite"),
    CommonFood(name: "Cheese slice", portion: "1 slice", kcal: 70, protein: 4.5, group: "Dairy", words: "queijo fatia"),
    CommonFood(name: "Protein shake", portion: "1 scoop in water", kcal: 120, protein: 24, group: "Snacks", words: "whey batido"),
    CommonFood(name: "Protein shake with milk", portion: "1 scoop, 300 ml milk", kcal: 260, protein: 34, group: "Snacks", words: "whey batido leite"),
    CommonFood(name: "Protein bar", portion: "1 bar", kcal: 200, protein: 20, group: "Snacks", words: "barra proteica"),
    CommonFood(name: "Nuts", portion: "a handful 30 g", kcal: 180, protein: 6, group: "Snacks", words: "frutos secos amendoas almonds nozes"),
    CommonFood(name: "Peanut butter", portion: "1 tbsp", kcal: 95, protein: 4, group: "Snacks", words: "manteiga amendoim"),
    CommonFood(name: "Chocolate bar", portion: "1 bar 45 g", kcal: 240, protein: 3, group: "Snacks", words: "chocolate"),
    CommonFood(name: "Bolacha Maria", portion: "4 biscuits", kcal: 120, protein: 2, group: "Snacks", words: "biscuits bolachas"),
    CommonFood(name: "Crisps", portion: "1 small bag", kcal: 160, protein: 2, group: "Snacks", words: "batatas fritas chips"),
    CommonFood(name: "Rice cakes", portion: "2 cakes", kcal: 70, protein: 1.5, group: "Snacks", words: "bolachas arroz"),
    // Meals
    CommonFood(name: "Chicken breast with rice", portion: "1 plate", kcal: 600, protein: 45, group: "Meals", words: "frango arroz"),
    CommonFood(name: "Chicken with potatoes and salad", portion: "1 plate", kcal: 550, protein: 42, group: "Meals", words: "frango batata salada"),
    CommonFood(name: "Frango assado", portion: "a quarter, with fries", kcal: 750, protein: 45, group: "Meals", words: "piri piri roast chicken churrasco"),
    CommonFood(name: "Salmon with vegetables", portion: "1 plate", kcal: 520, protein: 38, group: "Meals", words: "salmao legumes"),
    CommonFood(name: "Grilled fish with potatoes", portion: "1 plate", kcal: 480, protein: 38, group: "Meals", words: "peixe grelhado batata dourada robalo"),
    CommonFood(name: "Bacalhau à Brás", portion: "1 plate", kcal: 650, protein: 30, group: "Meals", words: "bacalhau cod"),
    CommonFood(name: "Bacalhau com natas", portion: "1 plate", kcal: 700, protein: 30, group: "Meals", words: "bacalhau cod cream"),
    CommonFood(name: "Arroz de pato", portion: "1 plate", kcal: 750, protein: 35, group: "Meals", words: "duck rice"),
    CommonFood(name: "Feijoada", portion: "1 plate", kcal: 750, protein: 35, group: "Meals", words: "bean stew"),
    CommonFood(name: "Cozido à portuguesa", portion: "1 plate", kcal: 900, protein: 50, group: "Meals", words: "cozido stew"),
    CommonFood(name: "Bitoque", portion: "steak, egg, fries, rice", kcal: 950, protein: 50, group: "Meals", words: "bife steak"),
    CommonFood(name: "Steak with rice and salad", portion: "1 plate", kcal: 700, protein: 45, group: "Meals", words: "bife arroz"),
    CommonFood(name: "Spaghetti bolognese", portion: "1 plate", kcal: 650, protein: 30, group: "Meals", words: "esparguete bolonhesa pasta"),
    CommonFood(name: "Pasta with tuna", portion: "1 plate", kcal: 550, protein: 32, group: "Meals", words: "massa atum"),
    CommonFood(name: "Lasagna", portion: "1 portion", kcal: 600, protein: 30, group: "Meals", words: "lasanha"),
    CommonFood(name: "Soup", portion: "1 bowl", kcal: 120, protein: 4, group: "Meals", words: "sopa caldo verde legumes"),
    CommonFood(name: "Mixed salad with tuna", portion: "1 bowl", kcal: 350, protein: 25, group: "Meals", words: "salada atum"),
    CommonFood(name: "Chicken salad", portion: "1 bowl", kcal: 400, protein: 35, group: "Meals", words: "salada frango caesar"),
    CommonFood(name: "Omelette with salad", portion: "1 plate", kcal: 380, protein: 22, group: "Meals", words: "omelete salada"),
    CommonFood(name: "Burrito bowl", portion: "1 bowl", kcal: 700, protein: 40, group: "Meals", words: "bowl"),
    CommonFood(name: "Poke bowl", portion: "1 bowl", kcal: 600, protein: 30, group: "Meals", words: "poke salmao"),
    CommonFood(name: "Sushi", portion: "8 pieces", kcal: 350, protein: 15, group: "Meals", words: "sushi"),
    // Eating out
    CommonFood(name: "Francesinha", portion: "1, with sauce", kcal: 1200, protein: 60, group: "Eating out", words: "francesinha"),
    CommonFood(name: "Bifana", portion: "1 sandwich", kcal: 450, protein: 25, group: "Eating out", words: "bifana pork sandwich"),
    CommonFood(name: "Prego no pão", portion: "1 sandwich", kcal: 500, protein: 30, group: "Eating out", words: "prego steak sandwich"),
    CommonFood(name: "Cachorro", portion: "1 hot dog", kcal: 550, protein: 18, group: "Eating out", words: "hot dog cachorro quente"),
    CommonFood(name: "Burger and fries", portion: "1 menu", kcal: 1000, protein: 35, group: "Eating out", words: "hamburguer batatas mcdonalds"),
    CommonFood(name: "Burger", portion: "1", kcal: 550, protein: 28, group: "Eating out", words: "hamburguer"),
    CommonFood(name: "Fries", portion: "1 medium", kcal: 340, protein: 4, group: "Eating out", words: "batatas fritas"),
    CommonFood(name: "Pizza", portion: "2 slices", kcal: 550, protein: 24, group: "Eating out", words: "pizza"),
    CommonFood(name: "Pizza, whole", portion: "1 medium", kcal: 1100, protein: 48, group: "Eating out", words: "pizza inteira"),
    CommonFood(name: "Kebab", portion: "1 wrap", kcal: 700, protein: 35, group: "Eating out", words: "kebab durum"),
    CommonFood(name: "Chicken nuggets", portion: "9 pieces", kcal: 420, protein: 23, group: "Eating out", words: "nuggets"),
    CommonFood(name: "Rissóis", portion: "2", kcal: 300, protein: 8, group: "Eating out", words: "rissois croquetes salgados"),
    CommonFood(name: "Ice cream", portion: "2 scoops", kcal: 270, protein: 5, group: "Eating out", words: "gelado"),
    // Drinks
    CommonFood(name: "Beer", portion: "1 imperial 200 ml", kcal: 85, protein: 0.6, group: "Drinks", words: "cerveja fino imperial"),
    CommonFood(name: "Beer, large", portion: "1 caneca 500 ml", kcal: 210, protein: 1.5, group: "Drinks", words: "cerveja caneca"),
    CommonFood(name: "Wine", portion: "1 glass", kcal: 125, protein: 0, group: "Drinks", words: "vinho"),
    CommonFood(name: "Orange juice", portion: "1 glass", kcal: 110, protein: 2, group: "Drinks", words: "sumo laranja"),
    CommonFood(name: "Smoothie", portion: "1 cup", kcal: 200, protein: 4, group: "Drinks", words: "batido fruta"),
]

/// Portions you can pick for anything: a smaller or bigger plate than usual
let portionSizes: [(name: String, factor: Double)] = [("Small", 0.7), ("Normal", 1), ("Large", 1.4), ("Double", 2)]

struct OFFResult: Identifiable, Hashable {
    var id: String
    var name: String
    var brand: String?
    var kcal100: Double
    var protein100: Double
    var serving: Double?
}

enum FoodSearch {
    static func local(_ q: String) -> [CommonFood] {
        let words = q.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }
        return commonFoods.filter { f in
            let hay = (f.name + " " + f.words + " " + f.group).lowercased().folding(options: .diacriticInsensitive, locale: nil)
            return words.allSatisfy { hay.contains($0) }
        }
    }

    /// Packaged products by name from Open Food Facts, Portuguese first
    static func products(_ q: String) async -> [OFFResult] {
        if TestMode.active { return [] }
        guard q.count >= 3, let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://world.openfoodfacts.org/cgi/search.pl?search_terms=\(enc)&search_simple=1&action=process&json=1&page_size=15&sort_by=unique_scans_n&fields=code,product_name,brands,nutriments,serving_quantity") else { return [] }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("Cadence/0.9 (personal app)", forHTTPHeaderField: "User-Agent")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["products"] as? [[String: Any]] else { return [] }
        return list.compactMap { p in
            guard let name = p["product_name"] as? String, !name.isEmpty else { return nil }
            let n = p["nutriments"] as? [String: Any] ?? [:]
            func num(_ k: String) -> Double? { (n[k] as? Double) ?? (n[k] as? NSNumber)?.doubleValue ?? Double(n[k] as? String ?? "") }
            guard let kcal = num("energy-kcal_100g") else { return nil }
            let serving = (p["serving_quantity"] as? Double) ?? Double(p["serving_quantity"] as? String ?? "")
            return OFFResult(id: p["code"] as? String ?? name, name: name, brand: (p["brands"] as? String)?.components(separatedBy: ",").first, kcal100: kcal, protein100: num("proteins_100g") ?? 0, serving: serving)
        }
    }
}
