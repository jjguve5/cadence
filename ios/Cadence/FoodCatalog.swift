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

    /// The group as shown; `group` stays the English key (the Picker's tag and the search words)
    static func groupLabel(_ group: String) -> String {
        let labels: [String: String] = ["Eating out": "Comer fora", "Meals": "Refeições", "Soups and salads": "Sopas e saladas", "Breakfast": "Pequeno-almoço",
                                        "Snacks": "Lanches", "Fruit": "Fruta", "Dairy": "Laticínios", "Desserts": "Sobremesas", "Drinks": "Bebidas"]
        return labels[group] ?? group
    }

    /// What this food counts for in the day's goals, from the catalogue (phase 2.7: the group comes from the food):
    /// every fruit in the catalogue is fruit; the rest by the catalogue's own name ("Sopa de legumes" is a soup, "Salada
    /// mista" a portion of vegetables). FoodGoals.noGroup when it counts for none.
    var goals: String {
        if group == "Fruit" { return FoodGoals.fruit }
        return FoodGoals.legacyGroup(name: name)
    }
}

/// What a portion's text says about the units it allows (phase 2.7 decision). Nothing is guessed: grams only when the
/// text gives the weight (or it is a spoon: tablespoon 15 g, teaspoon 5 g), units only when it counts things.
enum FoodPortion {
    /// Words that measure rather than count: "1 prato" is a plate of food, not one unit of it
    private static let measures: Set<String> = ["prato", "malga", "taca", "chavena", "copo", "caneca", "imperial", "dose", "porcao", "pote", "medida",
                                               "punhado", "colher", "colheres", "pacote", "acompanhamento", "menu", "pires", "quarto", "ml", "l", "g", "kg"]

    private static func folded(_ text: String) -> String { text.lowercased().folding(options: .diacriticInsensitive, locale: nil) }

    /// The number the text starts with ("2 ovos" → 2), if it starts with one
    private static func leadingNumber(_ t: String) -> Double? {
        let digits = t.prefix { $0.isNumber }
        return digits.isEmpty ? nil : Double(String(digits))
    }

    /// The weight of the portion: "1 pote de 170 g" → 170, "um punhado, 30 g" → 30, "1 colher de sopa" → 15
    static func grams(_ text: String) -> Double? {
        let t = folded(text)
        if let r = t.range(of: #"\d+([.,]\d+)?\s?g\b"#, options: .regularExpression) {
            let number = t[r].filter { $0.isNumber || $0 == "." || $0 == "," }.replacingOccurrences(of: ",", with: ".")
            if let g = Double(number), g > 0 { return g }
        }
        let n = leadingNumber(t) ?? 1
        if t.contains("colher de sopa") || t.contains("colheres de sopa") { return n * FoodUnit.tablespoonGrams }
        if t.contains("colher de cha") || t.contains("colheres de cha") { return n * FoodUnit.teaspoonGrams }
        return nil
    }

    /// How many countable things the portion is: "2 ovos" → 2, "1 média" → 1, "8 peças" → 8, "1, com molho" → 1;
    /// nil for plates, bowls, glasses and anything else that measures
    static func count(_ text: String) -> Double? {
        let t = folded(text)
        guard let n = leadingNumber(t), n > 0 else { return nil }
        let words = t.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if words.count > 1, measures.contains(words[1]) { return nil }
        return n
    }
}

let commonFoods: [CommonFood] = [
    // Breakfast and snacks
    CommonFood(name: "Banana", portion: "1 média", kcal: 105, protein: 1.3, group: "Fruit", words: "banana"),
    CommonFood(name: "Maçã", portion: "1 média", kcal: 95, protein: 0.5, group: "Fruit", words: "apple maçã maca"),
    CommonFood(name: "Laranja", portion: "1 média", kcal: 62, protein: 1.2, group: "Fruit", words: "orange laranja"),
    CommonFood(name: "Pera", portion: "1 média", kcal: 100, protein: 0.6, group: "Fruit", words: "pear pera"),
    CommonFood(name: "Uvas", portion: "1 chávena", kcal: 104, protein: 1.1, group: "Fruit", words: "grapes uvas"),
    CommonFood(name: "Ovo", portion: "1, cozido ou estrelado", kcal: 80, protein: 6.5, group: "Breakfast", words: "egg, boiled or fried ovo ovos"),
    CommonFood(name: "Ovos mexidos", portion: "2 ovos", kcal: 200, protein: 13, group: "Breakfast", words: "scrambled eggs ovos mexidos"),
    CommonFood(name: "Omelete", portion: "2 ovos, queijo", kcal: 290, protein: 19, group: "Breakfast", words: "omelette omelete"),
    CommonFood(name: "Torradas com manteiga", portion: "2 fatias", kcal: 230, protein: 6, group: "Breakfast", words: "toast with butter torrada manteiga"),
    CommonFood(name: "Pão com queijo", portion: "1 pão", kcal: 280, protein: 12, group: "Breakfast", words: "pão with cheese pao com queijo bread cheese"),
    CommonFood(name: "Pão com fiambre e queijo", portion: "1 pão", kcal: 330, protein: 17, group: "Breakfast", words: "pão with ham and cheese pao misto sandes mista fiambre"),
    CommonFood(name: "Tosta mista", portion: "1 tosta", kcal: 380, protein: 19, group: "Breakfast", words: "toastie ham cheese"),
    CommonFood(name: "Pão com mel", portion: "1 pão", kcal: 196, protein: 4.6, group: "Breakfast", words: "pao bread honey"),
    CommonFood(name: "Pão com manteiga e mel", portion: "1 pão", kcal: 268, protein: 4.7, group: "Breakfast", words: "pao bread butter honey"),
    CommonFood(name: "Torradas com mel", portion: "2 fatias", kcal: 211, protein: 5.1, group: "Breakfast", words: "toast honey torrada"),
    CommonFood(name: "Pão ou sandes", portion: "escolhe o pão e o que leva", kcal: 135, protein: 4.5, group: "Breakfast", words: "pao sandes sandwich bread recheio barrar mel compota"),
    CommonFood(name: "Croissant", portion: "1", kcal: 230, protein: 5, group: "Breakfast", words: "croissant"),
    CommonFood(name: "Pastel de nata", portion: "1", kcal: 220, protein: 3.5, group: "Breakfast", words: "nata custard tart"),
    CommonFood(name: "Papas de aveia", portion: "1 taça, com leite", kcal: 300, protein: 12, group: "Breakfast", words: "oatmeal with milk papas aveia porridge oats"),
    CommonFood(name: "Granola com iogurte", portion: "1 taça", kcal: 350, protein: 13, group: "Breakfast", words: "granola with yogurt granola iogurte"),
    CommonFood(name: "Iogurte grego", portion: "1 pote de 170 g", kcal: 160, protein: 15, group: "Dairy", words: "greek yogurt iogurte grego"),
    CommonFood(name: "Skyr", portion: "1 pote de 150 g", kcal: 95, protein: 16, group: "Dairy", words: "skyr iogurte"),
    CommonFood(name: "Iogurte proteico", portion: "1 pote de 200 g", kcal: 130, protein: 20, group: "Dairy", words: "protein yogurt iogurte proteico high protein"),
    CommonFood(name: "Leite", portion: "1 copo de 250 ml", kcal: 120, protein: 8, group: "Dairy", words: "milk leite"),
    CommonFood(name: "Fatia de queijo", portion: "1 fatia", kcal: 70, protein: 4.5, group: "Dairy", words: "cheese slice queijo fatia"),
    CommonFood(name: "Batido de proteína", portion: "1 medida em água", kcal: 120, protein: 24, group: "Snacks", words: "protein shake whey batido"),
    CommonFood(name: "Batido de proteína com leite", portion: "1 medida, 300 ml de leite", kcal: 260, protein: 34, group: "Snacks", words: "protein shake with milk whey batido leite"),
    CommonFood(name: "Barra de proteína", portion: "1 barra", kcal: 200, protein: 20, group: "Snacks", words: "protein bar barra proteica"),
    CommonFood(name: "Frutos secos", portion: "um punhado, 30 g", kcal: 180, protein: 6, group: "Snacks", words: "nuts frutos secos amendoas almonds nozes"),
    CommonFood(name: "Manteiga de amendoim", portion: "1 colher de sopa", kcal: 95, protein: 4, group: "Snacks", words: "peanut butter manteiga amendoim"),
    CommonFood(name: "Tablete de chocolate", portion: "1 tablete de 45 g", kcal: 240, protein: 3, group: "Snacks", words: "chocolate bar chocolate"),
    CommonFood(name: "Bolacha Maria", portion: "4 bolachas", kcal: 120, protein: 2, group: "Snacks", words: "biscuits bolachas"),
    CommonFood(name: "Batatas fritas de pacote", portion: "1 pacote pequeno", kcal: 160, protein: 2, group: "Snacks", words: "crisps batatas fritas chips"),
    CommonFood(name: "Bolachas de arroz", portion: "2 bolachas", kcal: 70, protein: 1.5, group: "Snacks", words: "rice cakes bolachas arroz"),
    // Meals
    CommonFood(name: "Frango com arroz", portion: "1 prato, peito de frango", kcal: 600, protein: 45, group: "Meals", words: "chicken breast with rice frango arroz"),
    CommonFood(name: "Frango com batata e salada", portion: "1 prato", kcal: 550, protein: 42, group: "Meals", words: "chicken with potatoes and salad frango batata salada"),
    CommonFood(name: "Frango assado", portion: "um quarto, com batatas fritas", kcal: 750, protein: 45, group: "Meals", words: "piri piri roast chicken churrasco"),
    CommonFood(name: "Salmão com legumes", portion: "1 prato", kcal: 520, protein: 38, group: "Meals", words: "salmon with vegetables salmao legumes"),
    CommonFood(name: "Peixe grelhado com batata", portion: "1 prato", kcal: 480, protein: 38, group: "Meals", words: "grilled fish with potatoes peixe grelhado batata dourada robalo"),
    CommonFood(name: "Bacalhau à Brás", portion: "1 prato", kcal: 650, protein: 30, group: "Meals", words: "bacalhau cod"),
    CommonFood(name: "Bacalhau com natas", portion: "1 prato", kcal: 700, protein: 30, group: "Meals", words: "bacalhau cod cream"),
    CommonFood(name: "Arroz de pato", portion: "1 prato", kcal: 750, protein: 35, group: "Meals", words: "duck rice"),
    CommonFood(name: "Feijoada", portion: "1 prato", kcal: 750, protein: 35, group: "Meals", words: "bean stew"),
    CommonFood(name: "Cozido à portuguesa", portion: "1 prato", kcal: 900, protein: 50, group: "Meals", words: "cozido stew"),
    CommonFood(name: "Bitoque", portion: "bife, ovo, batatas fritas, arroz", kcal: 950, protein: 50, group: "Meals", words: "bife steak"),
    CommonFood(name: "Bife com arroz e salada", portion: "1 prato", kcal: 700, protein: 45, group: "Meals", words: "steak with rice and salad bife arroz"),
    CommonFood(name: "Esparguete à bolonhesa", portion: "1 prato", kcal: 650, protein: 30, group: "Meals", words: "spaghetti bolognese esparguete bolonhesa pasta"),
    CommonFood(name: "Massa com atum", portion: "1 prato", kcal: 550, protein: 32, group: "Meals", words: "pasta with tuna massa atum"),
    CommonFood(name: "Lasanha", portion: "1 porção", kcal: 600, protein: 30, group: "Meals", words: "lasagna lasanha"),
    CommonFood(name: "Sopa", portion: "1 prato", kcal: 120, protein: 4, group: "Meals", words: "soup sopa caldo verde legumes"),
    CommonFood(name: "Salada variada com atum", portion: "1 taça", kcal: 350, protein: 25, group: "Meals", words: "mixed salad with tuna salada atum"),
    CommonFood(name: "Salada de frango", portion: "1 taça", kcal: 400, protein: 35, group: "Meals", words: "chicken salad salada frango caesar"),
    CommonFood(name: "Omelete com salada", portion: "1 prato", kcal: 380, protein: 22, group: "Meals", words: "omelette with salad omelete salada"),
    CommonFood(name: "Burrito bowl", portion: "1 taça", kcal: 700, protein: 40, group: "Meals", words: "bowl"),
    CommonFood(name: "Poke bowl", portion: "1 taça", kcal: 600, protein: 30, group: "Meals", words: "poke salmao"),
    CommonFood(name: "Sushi", portion: "8 peças", kcal: 350, protein: 15, group: "Meals", words: "sushi"),
    // Eating out
    CommonFood(name: "Francesinha", portion: "1, com molho", kcal: 1200, protein: 60, group: "Eating out", words: "francesinha"),
    CommonFood(name: "Bifana", portion: "1 sandes", kcal: 450, protein: 25, group: "Eating out", words: "bifana pork sandwich"),
    CommonFood(name: "Prego no pão", portion: "1 sandes", kcal: 500, protein: 30, group: "Eating out", words: "prego steak sandwich"),
    CommonFood(name: "Cachorro", portion: "1 cachorro-quente", kcal: 550, protein: 18, group: "Eating out", words: "hot dog cachorro quente"),
    CommonFood(name: "Hambúrguer com batatas fritas", portion: "1 menu", kcal: 1000, protein: 35, group: "Eating out", words: "burger and fries hamburguer batatas mcdonalds"),
    CommonFood(name: "Hambúrguer", portion: "1", kcal: 550, protein: 28, group: "Eating out", words: "burger hamburguer"),
    CommonFood(name: "Batatas fritas", portion: "1 dose média", kcal: 340, protein: 4, group: "Eating out", words: "fries batatas fritas"),
    CommonFood(name: "Pizza", portion: "2 fatias", kcal: 550, protein: 24, group: "Eating out", words: "pizza"),
    CommonFood(name: "Pizza inteira", portion: "1 média", kcal: 1100, protein: 48, group: "Eating out", words: "pizza, whole pizza inteira"),
    CommonFood(name: "Kebab", portion: "1 wrap", kcal: 700, protein: 35, group: "Eating out", words: "kebab durum"),
    CommonFood(name: "Nuggets de frango", portion: "9 peças", kcal: 420, protein: 23, group: "Eating out", words: "chicken nuggets nuggets"),
    CommonFood(name: "Rissóis", portion: "2", kcal: 300, protein: 8, group: "Eating out", words: "rissois croquetes salgados"),
    CommonFood(name: "Gelado", portion: "2 bolas", kcal: 270, protein: 5, group: "Eating out", words: "ice cream gelado"),
    // Drinks
    CommonFood(name: "Cerveja", portion: "1 imperial de 200 ml", kcal: 85, protein: 0.6, group: "Drinks", words: "beer cerveja fino imperial"),
    CommonFood(name: "Cerveja grande", portion: "1 caneca de 500 ml", kcal: 210, protein: 1.5, group: "Drinks", words: "beer, large cerveja caneca"),
    CommonFood(name: "Vinho", portion: "1 copo", kcal: 125, protein: 0, group: "Drinks", words: "wine vinho"),
    CommonFood(name: "Sumo de laranja", portion: "1 copo", kcal: 110, protein: 2, group: "Drinks", words: "orange juice sumo laranja"),
    CommonFood(name: "Smoothie", portion: "1 copo", kcal: 200, protein: 4, group: "Drinks", words: "batido fruta"),
    // Soups and salads
    CommonFood(name: "Sopa de legumes", portion: "1 malga", kcal: 90, protein: 3, group: "Soups and salads", words: "vegetable soup"),
    CommonFood(name: "Caldo verde", portion: "1 malga", kcal: 110, protein: 4, group: "Soups and salads", words: "sopa couve chourico kale soup"),
    CommonFood(name: "Creme de legumes", portion: "1 malga", kcal: 120, protein: 3, group: "Soups and salads", words: "sopa creme cream vegetable soup"),
    CommonFood(name: "Canja de galinha", portion: "1 malga", kcal: 100, protein: 7, group: "Soups and salads", words: "sopa chicken soup"),
    CommonFood(name: "Sopa de feijão", portion: "1 prato", kcal: 170, protein: 8, group: "Soups and salads", words: "feijao bean soup"),
    CommonFood(name: "Salada mista", portion: "1 acompanhamento, com azeite", kcal: 70, protein: 1.2, group: "Soups and salads", words: "mixed side salad alface tomate"),
    CommonFood(name: "Salada de tomate", portion: "1 acompanhamento", kcal: 50, protein: 1.2, group: "Soups and salads", words: "tomato salad cebola"),
    CommonFood(name: "Salada de grão com atum", portion: "1 taça", kcal: 380, protein: 25, group: "Soups and salads", words: "grao chickpea tuna salad"),
    // More fruit
    CommonFood(name: "Tangerina", portion: "2 pequenas", kcal: 70, protein: 1, group: "Fruit", words: "tangerine tangerina clementina"),
    CommonFood(name: "Kiwi", portion: "1", kcal: 45, protein: 0.8, group: "Fruit", words: "kiwi"),
    CommonFood(name: "Morangos", portion: "1 chávena", kcal: 50, protein: 1, group: "Fruit", words: "strawberries morangos"),
    CommonFood(name: "Pêssego", portion: "1 médio", kcal: 60, protein: 1.4, group: "Fruit", words: "peach pessego"),
    CommonFood(name: "Melão", portion: "1 fatia", kcal: 55, protein: 1.2, group: "Fruit", words: "melon melao meloa"),
    CommonFood(name: "Melancia", portion: "1 fatia", kcal: 85, protein: 1.7, group: "Fruit", words: "watermelon melancia"),
    CommonFood(name: "Ananás", portion: "1 rodela", kcal: 60, protein: 0.6, group: "Fruit", words: "pineapple ananas"),
    CommonFood(name: "Salada de fruta", portion: "1 taça", kcal: 90, protein: 1, group: "Fruit", words: "fruit salad"),
    CommonFood(name: "Manga", portion: "1/2 manga", kcal: 100, protein: 1.4, group: "Fruit", words: "mango"),
    CommonFood(name: "Papaia", portion: "1 fatia", kcal: 60, protein: 0.7, group: "Fruit", words: "papaya mamao"),
    CommonFood(name: "Abacaxi", portion: "1 rodela", kcal: 60, protein: 0.6, group: "Fruit", words: "pineapple ananas"),
    CommonFood(name: "Cerejas", portion: "10 cerejas", kcal: 50, protein: 0.9, group: "Fruit", words: "cherries cereja"),
    CommonFood(name: "Ameixa", portion: "2 ameixas", kcal: 60, protein: 0.9, group: "Fruit", words: "plum ameixas"),
    CommonFood(name: "Figos", portion: "2 figos", kcal: 75, protein: 0.8, group: "Fruit", words: "figs figo"),
    CommonFood(name: "Framboesas", portion: "1 chávena", kcal: 65, protein: 1.5, group: "Fruit", words: "raspberries framboesa"),
    CommonFood(name: "Mirtilos", portion: "1 chávena", kcal: 85, protein: 1.1, group: "Fruit", words: "blueberries mirtilo"),
    CommonFood(name: "Amoras", portion: "1 chávena", kcal: 62, protein: 2, group: "Fruit", words: "blackberries amora"),
    CommonFood(name: "Romã", portion: "1/2 romã", kcal: 115, protein: 2.3, group: "Fruit", words: "pomegranate roma"),
    CommonFood(name: "Dióspiro", portion: "1 médio", kcal: 120, protein: 1, group: "Fruit", words: "persimmon diospiro"),
    CommonFood(name: "Nêsperas", portion: "4 nêsperas", kcal: 50, protein: 0.5, group: "Fruit", words: "loquat nespera"),
    CommonFood(name: "Maracujá", portion: "2 maracujás", kcal: 35, protein: 0.8, group: "Fruit", words: "passion fruit maracuja"),
    CommonFood(name: "Toranja", portion: "1/2 toranja", kcal: 52, protein: 1, group: "Fruit", words: "grapefruit"),
    CommonFood(name: "Nectarina", portion: "1 média", kcal: 62, protein: 1.5, group: "Fruit", words: "nectarine"),
    CommonFood(name: "Alperces", portion: "3 alperces", kcal: 50, protein: 1.5, group: "Fruit", words: "apricot damasco alperce"),
    CommonFood(name: "Clementina", portion: "2 clementinas", kcal: 70, protein: 1.2, group: "Fruit", words: "clementine"),
    CommonFood(name: "Meloa", portion: "1 fatia", kcal: 50, protein: 1.2, group: "Fruit", words: "cantaloupe melon"),
    CommonFood(name: "Goiaba", portion: "1 média", kcal: 60, protein: 2.3, group: "Fruit", words: "guava"),
    CommonFood(name: "Lichias", portion: "6 lichias", kcal: 40, protein: 0.5, group: "Fruit", words: "lychee lichia"),
    CommonFood(name: "Anona", portion: "1/2 anona", kcal: 115, protein: 2.4, group: "Fruit", words: "custard apple cherimoya"),
    CommonFood(name: "Limão", portion: "1 limão", kcal: 20, protein: 0.6, group: "Fruit", words: "lemon limao"),
    CommonFood(name: "Lima", portion: "1 lima", kcal: 20, protein: 0.5, group: "Fruit", words: "lime"),
    CommonFood(name: "Abacate", portion: "1/2 abacate", kcal: 160, protein: 2, group: "Fruit", words: "avocado"),
    CommonFood(name: "Coco fresco", portion: "1 pedaço, 40 g", kcal: 140, protein: 1.3, group: "Fruit", words: "coconut"),
    CommonFood(name: "Marmelo", portion: "1 médio", kcal: 52, protein: 0.4, group: "Fruit", words: "quince"),
    CommonFood(name: "Physalis", portion: "1 chávena", kcal: 74, protein: 2.7, group: "Fruit", words: "physalis fisalis"),
    CommonFood(name: "Tâmaras", portion: "3 tâmaras", kcal: 70, protein: 0.6, group: "Fruit", words: "dates tamara"),
    CommonFood(name: "Passas", portion: "1 colher de sopa", kcal: 45, protein: 0.5, group: "Fruit", words: "raisins uvas passas"),
    CommonFood(name: "Maçã assada", portion: "1 média", kcal: 110, protein: 0.5, group: "Fruit", words: "baked apple maca"),
    CommonFood(name: "Banana pequena", portion: "1 pequena", kcal: 75, protein: 1, group: "Fruit", words: "banana"),
    CommonFood(name: "Uvas sem grainha", portion: "1 cacho pequeno", kcal: 90, protein: 1, group: "Fruit", words: "grapes uvas"),
    CommonFood(name: "Pera rocha", portion: "1 média", kcal: 85, protein: 0.5, group: "Fruit", words: "pear pera"),
    CommonFood(name: "Fruta em calda", portion: "1 taça", kcal: 120, protein: 0.6, group: "Fruit", words: "tinned fruit pessego ananas calda"),
    CommonFood(name: "Puré de fruta", portion: "1 saqueta, 100 g", kcal: 60, protein: 0.4, group: "Fruit", words: "fruit puree pouch saqueta"),
    // More Portuguese plates
    CommonFood(name: "Bacalhau à Braga", portion: "1 prato", kcal: 780, protein: 38, group: "Meals", words: "bacalhau cod fried batata cebolada"),
    CommonFood(name: "Bacalhau à lagareiro", portion: "1 prato", kcal: 700, protein: 40, group: "Meals", words: "bacalhau cod azeite batata murro"),
    CommonFood(name: "Bacalhau à Gomes de Sá", portion: "1 prato", kcal: 620, protein: 32, group: "Meals", words: "bacalhau cod batata ovo"),
    CommonFood(name: "Sardinhas assadas", portion: "4, com batatas", kcal: 620, protein: 38, group: "Meals", words: "grilled sardines batata"),
    CommonFood(name: "Polvo à lagareiro", portion: "1 prato", kcal: 620, protein: 38, group: "Meals", words: "octopus azeite batata"),
    CommonFood(name: "Arroz de marisco", portion: "1 prato", kcal: 550, protein: 32, group: "Meals", words: "seafood rice"),
    CommonFood(name: "Arroz de cabidela", portion: "1 prato", kcal: 650, protein: 35, group: "Meals", words: "frango galinha chicken blood rice"),
    CommonFood(name: "Caldeirada de peixe", portion: "1 prato", kcal: 500, protein: 35, group: "Meals", words: "fish stew batata"),
    CommonFood(name: "Rojões à minhota", portion: "1 prato", kcal: 850, protein: 40, group: "Meals", words: "rojoes pork porco batata"),
    CommonFood(name: "Papas de sarrabulho", portion: "1 malga", kcal: 450, protein: 22, group: "Meals", words: "minho braga"),
    CommonFood(name: "Carne de porco à alentejana", portion: "1 prato", kcal: 800, protein: 40, group: "Meals", words: "pork clams ameijoas batata"),
    CommonFood(name: "Tripas à moda do Porto", portion: "1 prato", kcal: 650, protein: 35, group: "Meals", words: "tripe feijao"),
    CommonFood(name: "Cabrito assado", portion: "1 prato, com batatas", kcal: 750, protein: 45, group: "Meals", words: "roast kid goat batata"),
    CommonFood(name: "Alheira com ovo e batata frita", portion: "1 prato", kcal: 850, protein: 28, group: "Meals", words: "alheira egg fries"),
    // Desserts
    CommonFood(name: "Arroz doce", portion: "1 taça", kcal: 240, protein: 5, group: "Desserts", words: "rice pudding sobremesa"),
    CommonFood(name: "Pudim Abade de Priscos", portion: "1 fatia", kcal: 300, protein: 5, group: "Desserts", words: "braga sobremesa flan"),
    CommonFood(name: "Pudim flan", portion: "1 fatia", kcal: 170, protein: 4.5, group: "Desserts", words: "sobremesa caramel custard"),
    CommonFood(name: "Leite creme", portion: "1 taça", kcal: 220, protein: 5, group: "Desserts", words: "sobremesa creme queimado"),
    CommonFood(name: "Mousse de chocolate", portion: "1 taça", kcal: 230, protein: 5, group: "Desserts", words: "sobremesa"),
    CommonFood(name: "Bolo de bolacha", portion: "1 fatia", kcal: 350, protein: 4, group: "Desserts", words: "sobremesa biscuit cake"),
]

/// Portions you can pick for anything: a smaller or bigger plate than usual
let portionSizes: [(name: String, factor: Double)] = [("Small", 0.7), ("Normal", 1), ("Large", 1.4), ("Double", 2)]

/// A portion size as shown; the English name stays (ids and accessibility identifiers are built from it)
func portionSizeLabel(_ name: String) -> String {
    let labels: [String: String] = ["Small": "Pequena", "Normal": "Normal", "Large": "Grande", "Double": "Dupla"]
    return labels[name] ?? name
}

struct OFFResult: Identifiable, Hashable {
    var id: String
    var name: String
    var brand: String?
    var kcal100: Double
    var protein100: Double? // nil when Open Food Facts doesn't have it: «Sem dados», never 0
    var serving: Double?

    /// The list's line, per 100 g
    var perHundred: String {
        protein100.map { "\(Int(kcal100)) kcal · \(Int($0)) g /100 g" } ?? "\(Int(kcal100)) kcal /100 g · proteína: sem dados"
    }
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
        return list.compactMap { FoodSearch.result($0) }
    }

    /// One product of a search. A product with no kcal isn't listed; protein it doesn't have stays nil, never 0
    static func result(_ p: [String: Any]) -> OFFResult? {
        guard let name = p["product_name"] as? String, !name.isEmpty else { return nil }
        let n = p["nutriments"] as? [String: Any] ?? [:]
        func num(_ k: String) -> Double? { (n[k] as? Double) ?? (n[k] as? NSNumber)?.doubleValue ?? Double(n[k] as? String ?? "") }
        guard let kcal = num("energy-kcal_100g") else { return nil }
        let serving = (p["serving_quantity"] as? Double) ?? Double(p["serving_quantity"] as? String ?? "")
        return OFFResult(id: p["code"] as? String ?? name, name: name, brand: (p["brands"] as? String)?.components(separatedBy: ",").first, kcal100: kcal, protein100: num("proteins_100g"), serving: serving)
    }
}
