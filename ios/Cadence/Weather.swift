// Weather where you are, from Open-Meteo (free, no key): the umbrella call across the hours you're out, how many
// layers, UV and sunscreen, air quality and pollen, and the outdoor-light estimate.
import CoreLocation
import Foundation

struct HourWeather: Codable, Equatable {
    var minute: Int // of today; > 1440 = tomorrow
    var temp: Double
    var feels: Double
    var rain: Double // probability %
    var wind: Double
    var uv: Double
    var code: Int
}

struct WeatherDay: Codable, Equatable {
    var date: String
    var place: String
    var hours: [HourWeather]
    var sunrise: Int
    var sunset: Int
    var high: Double
    var low: Double
    var pm25: Double?
    var pollen: Double?
    var fetched: Double
}

@MainActor
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()
    @Published private(set) var today: WeatherDay?
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?
    private let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("weather.json")
    // Braga, until the phone says where you are
    private let fallback = CLLocation(latitude: 41.5518, longitude: -8.4229)

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let d = try? Data(contentsOf: file), let w = try? JSONDecoder().decode(WeatherDay.self, from: d), w.date == Day.today { today = w }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in waiting?.resume(returning: locations.last); waiting = nil }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in waiting?.resume(returning: nil); waiting = nil }
    }

    /// Where the phone is now, asking for permission if it hasn't been asked
    func currentLocation() async -> CLLocation { await location() }

    private func location() async -> CLLocation {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        guard manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return manager.location ?? fallback }
        if let l = manager.location, Date().timeIntervalSince(l.timestamp) < 3600 { return l }
        let l: CLLocation? = await withCheckedContinuation { c in waiting = c; manager.requestLocation() }
        return l ?? fallback
    }

    func refresh(force: Bool = false) async {
        if TestMode.active { return }
        if !force, let t = today, nowMs() - t.fetched < 45 * 60 * 1000, t.date == Day.today { return }
        let loc = await location()
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&hourly=temperature_2m,apparent_temperature,precipitation_probability,wind_speed_10m,uv_index,weather_code&daily=sunrise,sunset,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2")!
        guard let (data, _) = try? await URLSession.shared.data(from: url), let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let h = j["hourly"] as? [String: Any], let times = h["time"] as? [String], let d = j["daily"] as? [String: Any] else { return }
        func nums(_ k: String) -> [Double] { (h[k] as? [Any] ?? []).map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) } }
        let temp = nums("temperature_2m"), feels = nums("apparent_temperature"), rain = nums("precipitation_probability"), wind = nums("wind_speed_10m"), uv = nums("uv_index"), code = nums("weather_code")
        var hours: [HourWeather] = []
        for (i, t) in times.enumerated() where i < temp.count {
            let day = String(t.prefix(10)), hh = Int(t.dropFirst(11).prefix(2)) ?? 0
            let offset = Day.between(Day.today, day)
            guard offset >= 0, offset <= 1 else { continue }
            hours.append(HourWeather(minute: offset * 1440 + hh * 60, temp: temp[i], feels: feels[i], rain: rain[safe: i] ?? 0, wind: wind[safe: i] ?? 0, uv: uv[safe: i] ?? 0, code: Int(code[safe: i] ?? 0)))
        }
        func clockMinute(_ s: String?) -> Int { guard let s, s.count >= 16 else { return 0 }; return (Int(s.dropFirst(11).prefix(2)) ?? 0) * 60 + (Int(s.dropFirst(14).prefix(2)) ?? 0) }
        let sunrise = clockMinute((d["sunrise"] as? [String])?.first), sunset = clockMinute((d["sunset"] as? [String])?.first)
        let highs = (d["temperature_2m_max"] as? [Any])?.compactMap { $0 as? Double } ?? [], lows = (d["temperature_2m_min"] as? [Any])?.compactMap { $0 as? Double } ?? []
        var place = "Onde estás"
        if let p = try? await CLGeocoder().reverseGeocodeLocation(loc).first { place = p.locality ?? place }
        var w = WeatherDay(date: Day.today, place: place, hours: hours, sunrise: sunrise, sunset: sunset, high: highs.first ?? 0, low: lows.first ?? 0, fetched: nowMs())
        // Air quality and pollen (European model)
        let aq = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(lat)&longitude=\(lon)&hourly=pm2_5,grass_pollen,birch_pollen,olive_pollen&timezone=auto&forecast_days=1")!
        if let (adata, _) = try? await URLSession.shared.data(from: aq), let a = try? JSONSerialization.jsonObject(with: adata) as? [String: Any], let ah = a["hourly"] as? [String: Any] {
            func maxOf(_ k: String) -> Double? { (ah[k] as? [Any])?.compactMap { $0 as? Double }.max() }
            w.pm25 = maxOf("pm2_5")
            w.pollen = [maxOf("grass_pollen"), maxOf("birch_pollen"), maxOf("olive_pollen")].compactMap { $0 }.max()
        }
        today = w
        if let out = try? JSONEncoder().encode(w) { try? out.write(to: file, options: .atomic) }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

struct WeatherCall {
    var umbrella: Bool
    var rainWindow: String?
    var layers: Int // 1 = T-shirt ... 4 = coat and layers
    var feels: Double
    var uvPeak: Double
    var uvHours: String?
    var airNote: String?
    var summary: String
}

@MainActor
extension Store {
    /// The hours you're out: from leaving (or waking) to wind-down, minus nothing fancy
    func outHours() -> ClosedRange<Int> {
        let leave = commutes().map(\.leave).min() ?? profile.wakeMinute + 60
        return leave...max(leave + 60, sleepPlan().windDown - 60)
    }

    func weatherCall() -> WeatherCall? {
        guard let w = WeatherStore.shared.today else { return nil }
        let range = outHours()
        let out = w.hours.filter { range.contains($0.minute) }
        guard !out.isEmpty else { return nil }
        let wet = out.filter { $0.rain >= 50 }
        let umbrella = !wet.isEmpty
        let window = wet.isEmpty ? nil : "\(clock(wet.first!.minute))–\(clock(wet.last!.minute + 60))"
        let feels = out.map(\.feels).min() ?? 15
        let layers = feels >= 22 ? 1 : feels >= 16 ? 2 : feels >= 9 ? 3 : 4
        let uvPeak = out.map(\.uv).max() ?? 0
        let uvHigh = out.filter { $0.uv >= 3 }
        let uvHours = uvHigh.isEmpty ? nil : "\(clock(uvHigh.first!.minute))–\(clock(uvHigh.last!.minute + 60))"
        var air: String?
        if let pm = w.pm25, pm > 25 { air = "A qualidade do ar está má hoje (PM2.5 \(Int(pm))): treina num espaço fechado." }
        else if let p = w.pollen, p > 50 { air = "Muito pólen hoje: é melhor correr num espaço fechado ou cedo." }
        let words = ["", "Tempo de t-shirt", "Uma camada leve", "Camisola e casaco", "Casaco quente e várias camadas"][layers]
        return WeatherCall(umbrella: umbrella, rainWindow: window, layers: layers, feels: feels, uvPeak: uvPeak, uvHours: uvHours, airNote: air,
                           summary: (umbrella ? "Leva o guarda-chuva (\(window!)). " : "Não precisas de guarda-chuva. ") + "\(words): sensação de \(Int(feels.rounded()))° na hora mais fria.")
    }

    /// Daylight you probably got: steps between sunrise and sunset count as time outside, plus "I was outside" taps
    func outdoorMinutes(on day: String = Day.today) -> Int {
        records("outside").filter { $0.key.hasPrefix(day) }.count * 15
    }
}
