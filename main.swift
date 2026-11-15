import AppKit
import CoreLocation

struct Forecast: Decodable {
    struct Hourly: Decodable {
        let time: [String]
        let temperature_2m: [Double?]
        let precipitation_probability: [Int?]
        let weather_code: [Int?]
        let is_day: [Int?]
    }
    struct Current: Decodable { let time: String }
    let hourly: Hourly
    let current: Current
}

final class App: NSObject, NSApplicationDelegate, CLLocationManagerDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let loc = CLLocationManager()
    var coord: CLLocationCoordinate2D?
    var timer: Timer?
    let unit = Locale.current.measurementSystem == .us ? "&temperature_unit=fahrenheit" : ""

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        show("…")
        loc.delegate = self
        loc.desiredAccuracy = kCLLocationAccuracyKilometer
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 300
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refresh), name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc func refresh() {
        switch loc.authorizationStatus {
        case .notDetermined: loc.requestWhenInUseAuthorization()
        case .denied, .restricted:
            if let c = coord { fetch(c) } else { show("⚠︎", ["Location access denied"]) }
        default: loc.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) { refresh() }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        coord = c
        fetch(c)
    }

    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {
        if let c = coord { fetch(c) } else { show("⚠︎", ["Location unavailable"]) }
    }

    func fetch(_ c: CLLocationCoordinate2D) {
        let s = "https://api.open-meteo.com/v1/forecast?latitude=\(c.latitude)&longitude=\(c.longitude)"
            + "&hourly=temperature_2m,precipitation_probability,weather_code,is_day&current=temperature_2m&past_days=1&forecast_days=2&timezone=auto" + unit
        var req = URLRequest(url: URL(string: s)!)
        req.timeoutInterval = 15
        URLSession.shared.dataTask(with: req) { data, resp, err in
            var f: Forecast?
            do { f = try JSONDecoder().decode(Forecast.self, from: data ?? Data()) }
            catch { NSLog("TempDiff: status=%d err=%@ decode=%@", (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          String(describing: err), String(describing: error)) }
            DispatchQueue.main.async { self.update(f) }
        }.resume()
    }

    func update(_ f: Forecast?) {
        let t = f?.hourly.temperature_2m ?? []
        let hour = f.map { String($0.current.time.prefix(13)) + ":00" }
        guard let f, let i = f.hourly.time.firstIndex(of: hour!),
              i >= 24, i + 24 < t.count, let y = t[i - 24], let n = t[i], let m = t[i + 24]
        else {
            NSLog("TempDiff: no usable data (hour=%@, count=%d)", hour ?? "-", t.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.refresh() }
            if item.button?.title.contains("°") != true { show("⚠︎", ["Weather unavailable, retrying…"]) }
            return
        }
        let (yr, nr, mr) = (Int(y.rounded()), Int(n.rounded()), Int(m.rounded()))
        let h = f.hourly
        func sky(_ j: Int) -> String {
            let (icon, text) = describe(h.weather_code[j] ?? -1, night: h.is_day[j] == 0)
            let rain = h.precipitation_probability[j].map { "  ·  \($0)% rain" } ?? ""
            return "  \(icon) \(text)\(rain)"
        }
        let time = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        let d = nr - yr
        show(d == 0 ? "= same as yesterday" : "\(diff(d)) \(d > 0 ? "warmer" : "colder") than yesterday",
             ["Yesterday  \(yr)°" + sky(i - 24),
              "Now  \(nr)°  (\(diff(nr - yr)) vs yesterday)" + sky(i),
              "Tomorrow  \(mr)°  (\(diff(mr - nr)) vs now)" + sky(i + 24),
              "Updated \(time)"])
    }

    let agent = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/LaunchAgents/io.github.boyanangelov.tempdiff.plist")
    var startsAtLogin: Bool { FileManager.default.fileExists(atPath: agent.path) }

    @objc func toggleLogin(_ sender: NSMenuItem) {
        do {
            if startsAtLogin { try FileManager.default.removeItem(at: agent) }
            else {
                let plist: [String: Any] = ["Label": "io.github.boyanangelov.tempdiff",
                                            "ProgramArguments": [Bundle.main.executablePath!],
                                            "RunAtLoad": true, "ProcessType": "Interactive"]
                try FileManager.default.createDirectory(at: agent.deletingLastPathComponent(), withIntermediateDirectories: true)
                try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: agent)
            }
        } catch { NSLog("TempDiff: login item error %@", String(describing: error)) }
        sender.state = startsAtLogin ? .on : .off
    }

    func describe(_ c: Int, night: Bool) -> (String, String) {
        switch c {
        case 0: return night ? ("🌙", "Clear") : ("☀️", "Sunny")
        case 1: return night ? ("🌙", "Mostly clear") : ("🌤", "Mostly sunny")
        case 2: return ("⛅️", "Partly cloudy")
        case 3: return ("☁️", "Overcast")
        case 45, 48: return ("🌫", "Fog")
        case 51...57: return ("🌦", "Drizzle")
        case 61...67: return ("🌧", "Rain")
        case 71...77: return ("🌨", "Snow")
        case 80...82: return ("🌦", "Showers")
        case 85, 86: return ("🌨", "Snow showers")
        case 95...99: return ("⛈", "Thunderstorm")
        default: return ("", "")
        }
    }

    func diff(_ d: Int) -> String { d > 0 ? "↑\(d)°" : d < 0 ? "↓\(-d)°" : "=0°" }

    func show(_ title: String, _ info: [String] = []) {
        item.button?.title = title
        let menu = NSMenu()
        for r in info { menu.addItem(withTitle: r, action: nil, keyEquivalent: "").isEnabled = false }
        if !info.isEmpty { menu.addItem(.separator()) }
        let login = menu.addItem(withTitle: "Start at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = startsAtLogin ? .on : .off
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
