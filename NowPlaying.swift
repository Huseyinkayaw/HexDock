// Spotify "şimdi çalıyor" kutusu — ekranın en sağında, Dock ile aynı hizada ve aynı camla.
import Cocoa
import SwiftUI
import ApplicationServices

// MARK: - Kayıt (yalnızca yerel, varsayılan olarak çok az yazar)

let logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HexDock.log")
/// Ayrıntılı kayıt kapalıdır. Açmak için: defaults write local.hexdock debugLog -bool true
var debugLogging: Bool { UserDefaults.standard.bool(forKey: "debugLog") }

func dlog(_ s: String) {
    // Dosya 256 KB'ı geçerse sıfırla — diskte büyümesin.
    if let size = (try? FileManager.default.attributesOfItem(atPath: logURL.path))?[.size] as? Int, size > 256_000 {
        try? FileManager.default.removeItem(at: logURL)
    }
    let line = "\(Date()) \(s)\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? line.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - Dock konumu

/// Dock'un görünen alanı (Cocoa koordinatlarında). Dock altta değilse ya da gizliyse nil.
@MainActor func currentDockFrame() -> CGRect? {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
          let primary = NSScreen.screens.first,
          let children = axValue(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement],
          let list = children.first(where: { axString($0, kAXRoleAttribute) == kAXListRole as String }),
          let p = axPoint(list, kAXPositionAttribute), let s = axSize(list, kAXSizeAttribute) else { return nil }
    return CGRect(x: p.x, y: primary.frame.height - p.y - s.height, width: s.width, height: s.height)
}

// MARK: - Model ve görünüm

final class NowPlayingModel: ObservableObject {
    @Published var title = ""
    @Published var artist = ""
    @Published var playing = false
    @Published var art: NSImage?
    @Published var height: CGFloat = 60
    @Published var playerName = "Spotify"
    var artURL = ""
}

struct NowPlayingView: View {
    @ObservedObject var model: NowPlayingModel
    let send: (String) -> Void
    let openApp: () -> Void

    var body: some View {
        // Kapak, Dock ikonlarıyla aynı oranda: yüksekliğin ~%70'i.
        let artSize = (model.height * 0.70).rounded()
        let inset = ((model.height - artSize) / 2).rounded()
        HStack(spacing: 10) {
            Group {
                if let art = model.art {
                    Image(nsImage: art).resizable().interpolation(.high).aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.primary.opacity(0.06))
                }
            }
            .frame(width: artSize, height: artSize)
            .clipShape(RoundedRectangle(cornerRadius: artSize * 0.22, style: .continuous))
            .onTapGesture(perform: openApp)

            VStack(alignment: .leading, spacing: 1) {
                Text(model.title.isEmpty ? model.playerName : model.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if !model.artist.isEmpty {
                    Text(model.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: openApp)

            HStack(spacing: 0) {
                MediaButton(symbol: "backward.fill") { send("previous track") }
                MediaButton(symbol: model.playing ? "pause.fill" : "play.fill") { send("playpause") }
                MediaButton(symbol: "forward.fill") { send("next track") }
            }
        }
        .padding(.leading, inset)
        .padding(.trailing, inset - 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MediaButton: View {
    let symbol: String
    let action: () -> Void
    private let hoverState = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(hoverState.wrappedValue ? Color.primary : Color.primary.opacity(0.75))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
    }
}

// MARK: - Kontrolcü

@MainActor
final class NowPlayingController {
    static let spotifyID = "com.spotify.client"
    static let pad: CGFloat = 16
    let model = NowPlayingModel()
    let panel: NSPanel
    let glass: NSView
    /// Kapak görselleri için diske önbellek yazmayan oturum.
    let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral   // çerez, önbellek, disk yok
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.timeoutIntervalForRequest = 10
        return URLSession(configuration: c)
    }()

    // Canlı ayarlanabilir değerler (yeniden derlemeden):  defaults write local.hexdock <anahtar> <değer>
    var d: UserDefaults { .standard }
    var widgetWidth: CGFloat { CGFloat(d.object(forKey: "npWidth") as? Double ?? 250) }
    var cornerRadius: CGFloat? { (d.object(forKey: "npRadius") as? Double).map { CGFloat($0) } }
    var offsetY: CGFloat { CGFloat(d.double(forKey: "npOffsetY")) }
    var extraHeight: CGFloat { CGFloat(d.double(forKey: "npExtraHeight")) }

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 250, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false   // Dock'un kendi gölgesi yok; cam efekti yeterli.
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        var sendRef: (String) -> Void = { _ in }
        var openRef: () -> Void = {}
        let host = ClickThroughHostingView(rootView: NowPlayingView(model: model,
                                                                  send: { sendRef($0) }, openApp: { openRef() }))

        // macOS'un kendi "Liquid Glass" malzemesi — Dock ile aynı.
        let g = NSGlassEffectView()
        g.style = .regular
        g.contentView = host
        glass = g
        // Cam, pencere kenarına yapışık olursa yuvarlak köşelerdeki kenar ışığı/gölgesi kesilip
        // siyah lekeler gibi görünüyor. Bu yüzden camı şeffaf bir kabın içine, kenarlardan boşluk bırakarak koyuyoruz.
        let container = NSView()
        g.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(g)
        let p = Self.pad
        NSLayoutConstraint.activate([
            g.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: p),
            g.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -p),
            g.topAnchor.constraint(equalTo: container.topAnchor, constant: p),
            g.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -p),
        ])
        panel.contentView = container

        sendRef = { [weak self] cmd in self?.command(cmd) }
        openRef = { [weak self] in self?.openPlayer() }
    }

    // MARK: Oynatıcılar — Spotify ve Apple Music

    enum Player: String, CaseIterable {
        case spotify = "com.spotify.client"
        case music = "com.apple.Music"
        /// Çalma durumu değişince yayınlanan bildirim (izin gerektirmez).
        var notification: String {
            self == .spotify ? "com.spotify.client.PlaybackStateChanged" : "com.apple.Music.playerInfo"
        }
        var name: String { self == .spotify ? "Spotify" : "Music" }
        var app: NSRunningApplication? { NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).first }
    }

    /// Kutunun şu an gösterdiği oynatıcı: en son çalmaya başlayan.
    var active: Player = .spotify

    /// Etkin oynatıcı kapandıysa, açık olanlardan çalanı (yoksa herhangi birini) seç.
    func pickActive() {
        if active.app != nil { return }
        let running = Player.allCases.filter { $0.app != nil }
        guard let first = running.first else { return }
        active = running.first(where: { runScript("return player state as string", on: $0) == "playing" }) ?? first
        model.artURL = ""
        refreshFromScript()
    }

    func start() {
        for player in Player.allCases {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(player.notification), object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo ?? [:]
                let state = info["Player State"] as? String
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                MainActor.assumeIsolated {
                    guard let self else { return }
                    // Bir oynatıcı çalmaya başlarsa kutu ona geçer.
                    if state == "Playing" && self.active != player {
                        self.active = player
                        self.model.artURL = ""
                    }
                    guard player == self.active else { return }
                    self.model.title = state == "Stopped" ? "" : title
                    self.model.artist = state == "Stopped" ? "" : artist
                    self.model.playing = state == "Playing"
                    self.model.playerName = player.name
                    self.refreshArtwork()
                }
            }
        }
    }

    // MARK: AppleScript (Otomasyon izni ister: "HexDock, Spotify'ı / Müzik'i denetlemek istiyor")

    func runDescriptor(_ body: String, on player: Player) -> NSAppleEventDescriptor? {
        guard player.app != nil else { return nil }   // oynatıcı kapalıysa onu açmasın
        var err: NSDictionary?
        let result = NSAppleScript(source: "tell application id \"\(player.rawValue)\"\n\(body)\nend tell")?
            .executeAndReturnError(&err)
        if let err, debugLogging { dlog("applescript error (\(player.name)): \(err)") }
        return result
    }

    @discardableResult
    func runScript(_ body: String, on player: Player? = nil) -> String? {
        runDescriptor(body, on: player ?? active)?.stringValue
    }

    func command(_ cmd: String) {
        runScript(cmd)
        if cmd == "playpause" { model.playing.toggle() }   // anında tepki; bildirim gelince doğrulanır
    }

    func refreshFromScript() {
        model.playerName = active.name
        guard let out = runScript("""
            if player state is stopped then return ""
            return (name of current track) & "\\n" & (artist of current track) & "\\n" & (player state as string)
            """) else { return }
        let parts = out.components(separatedBy: "\n")
        model.title = parts.first ?? ""
        model.artist = parts.count > 1 ? parts[1] : ""
        model.playing = parts.count > 2 && parts[2] == "playing"
        refreshArtwork()
    }

    /// Görseli küçültüp bellekte sadece küçük kopyayı tutar.
    nonisolated static func thumbnail(_ data: Data?) -> NSImage? {
        guard let data, let src = NSImage(data: data) else { return nil }
        let side: CGFloat = 96
        let out = NSImage(size: NSSize(width: side, height: side))
        out.lockFocus()
        src.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        out.unlockFocus()
        return out
    }

    func refreshArtwork() {
        switch active {
        case .spotify:
            guard !model.title.isEmpty,
                  let url = runScript("if player state is stopped then return \"\"\nreturn artwork url of current track"),
                  !url.isEmpty, url != model.artURL else { return }
            model.artURL = url
            // Yalnızca https ve yalnızca Spotify'ın kendi görsel sunucuları; başka hiçbir adrese istek atılmaz.
            guard let u = URL(string: url), u.scheme?.lowercased() == "https",
                  let host = u.host?.lowercased(),
                  host == "i.scdn.co" || host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com")
            else { model.art = nil; return }
            // Spotify kapakları Spotify'ın görsel sunucusundan indirilir; diske kaydedilmez.
            session.dataTask(with: u) { data, _, _ in
                let img = Self.thumbnail(data)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { if self.model.artURL == url { self.model.art = img } }
                }
            }.resume()
        case .music:
            // Apple Music kapağı doğrudan uygulamadan alınır — internet yok.
            let key = "music:\(model.title)|\(model.artist)"
            guard key != model.artURL else { return }
            model.artURL = key
            let desc = runDescriptor("""
                if player state is stopped then return ""
                if (count of artworks of current track) is 0 then return ""
                return data of artwork 1 of current track
                """, on: .music)
            let data = desc.flatMap { $0.descriptorType == typeUnicodeText ? nil : $0.data }
            model.art = Self.thumbnail(data)
        }
    }

    func openPlayer() { active.app?.activate() }

    // MARK: Konum — ekranın en sağı, Dock ile aynı yükseklik ve alt boşluk

    func update(dock: CGRect?) {
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        pickActive()
        guard !d.bool(forKey: "spotifyDisabled"), active.app != nil, orientation == "bottom", let dock,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(dock) }),
              dock.minY >= screen.frame.minY - 1 else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let sf = screen.frame
        let h = dock.height + extraHeight
        // Dock'un ekranın altına olan GÖRÜNEN boşluğu (AX alanı camdan biraz yukarıda başlıyor, offsetY bunu düzeltiyor).
        // Sağ boşluk bununla aynı olsun; istenirse elle: defaults write local.hexdock npRightMargin -float 6
        let bottomGap = (d.object(forKey: "npRightMargin") as? Double).map { CGFloat($0) }
            ?? max(0, dock.minY + offsetY - sf.minY)
        let y = dock.minY + offsetY - extraHeight / 2
        // Konum: varsayılan olarak Dock'un hemen sağı. "right" ise ekranın en sağı.
        //   defaults write local.hexdock npAnchor right   |   defaults write local.hexdock npGap 8
        let gap = CGFloat(d.object(forKey: "npGap") as? Double ?? 8)
        let x = d.string(forKey: "npAnchor") == "right"
            ? sf.maxX - widgetWidth - bottomGap
            : dock.maxX + gap
        // Ekrana sığmıyorsa gösterme.
        guard x + widgetWidth <= sf.maxX - 4, x >= dock.maxX + 4 else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let frame = NSRect(x: x, y: y, width: widgetWidth, height: h).integral
        if model.height != frame.height { model.height = frame.height }
        // Dock'un köşe yarıçapı: yüksekliğe orantılı (ayar ile değiştirilebilir).
        if let g = glass as? NSGlassEffectView {
            g.cornerRadius = cornerRadius ?? (frame.height * 0.30).rounded()
            // Cam türü: "regular" (Dock gibi) ya da "clear" (daha şeffaf) — defaults write local.hexdock npGlass clear
            let style: NSGlassEffectView.Style = d.string(forKey: "npGlass") == "clear" ? .clear : .regular
            if g.style != style { g.style = style }
            // İsteğe bağlı hafif renk tonu (0 = yok): defaults write local.hexdock npTint -float 0.1
            let tint = d.double(forKey: "npTint")
            g.tintColor = tint > 0 ? NSColor.black.withAlphaComponent(tint) : nil
        }
        let outer = frame.insetBy(dx: -Self.pad, dy: -Self.pad)
        if panel.frame != outer { panel.setFrame(outer, display: true) }
        if !panel.isVisible {
            panel.orderFrontRegardless()
            refreshFromScript()
        }
    }
}
