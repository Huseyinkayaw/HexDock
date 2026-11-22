// HexDock — Dock ikonlarının üzerine gelince pencere önizlemesi gösterir.
import Cocoa
import SwiftUI
import ScreenCaptureKit
import ApplicationServices
import ServiceManagement

// Özel ama yaygın kullanılan API: AX pencere elemanından CGWindowID alır.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

// MARK: - Sabitler

enum Layout {
    static let minThumbW: CGFloat = 130
    static let maxThumbW: CGFloat = 300
    static let thumbH: CGFloat = 125
    static let cardPad: CGFloat = 6
    static let cardSpacing: CGFloat = 10
    static let outerPad: CGFloat = 12
    static let headerH: CGFloat = 16
    static let headerGap: CGFloat = 8
    static let footerH: CGFloat = 18
    static let footerGap: CGFloat = 6
    static func thumbW(aspect: CGFloat) -> CGFloat {
        min(maxThumbW, max(minThumbW, (thumbH * aspect).rounded()))
    }
    static let titleH: CGFloat = 16
    static let titleGap: CGFloat = 5
    static var cardH: CGFloat { titleH + titleGap + thumbH + footerGap + footerH + cardPad * 2 }
    static var panelH: CGFloat { outerPad * 2 + cardH }
    static func panelW(items: [WinItem]) -> CGFloat {
        let cards = items.reduce(0) { $0 + thumbW(aspect: $1.aspect) + cardPad * 2 }
        return outerPad * 2 + cards + CGFloat(max(items.count - 1, 0)) * cardSpacing
    }
}

// MARK: - AX yardımcıları

func axValue(_ el: AXUIElement, _ name: String) -> CFTypeRef? {
    var v: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success else { return nil }
    return v
}

func axString(_ el: AXUIElement, _ name: String) -> String? { axValue(el, name) as? String }
func axBool(_ el: AXUIElement, _ name: String) -> Bool { (axValue(el, name) as? Bool) ?? false }

func axPoint(_ el: AXUIElement, _ name: String) -> CGPoint? {
    guard let v = axValue(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
}

func axSize(_ el: AXUIElement, _ name: String) -> CGSize? {
    guard let v = axValue(el, name), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
}

// MARK: - Ayarlar

/// Önizleme kartındaki orta düğme: "fill" (yerleştir), "full" (tam ekran) ya da "both" (ikisi birden).
var middleMode: String {
    let d = UserDefaults.standard
    if let m = d.string(forKey: "middleMode") { return m }
    return d.bool(forKey: "useFullScreen") ? "full" : "fill"   // eski ayardan geçiş
}

// MARK: - Model

struct WinItem: Identifiable {
    let id: CGWindowID
    let title: String
    let ax: AXUIElement
    var minimized: Bool
    let aspect: CGFloat          // pencerenin genişlik / yükseklik oranı
    var image: CGImage?
    var thumbW: CGFloat { Layout.thumbW(aspect: aspect) }
}

final class PreviewModel: ObservableObject {
    @Published var appName = ""
    @Published var appIcon: NSImage?
    @Published var windows: [WinItem] = []

    var onFocus: (WinItem) -> Void = { _ in }
    var onClose: (WinItem) -> Void = { _ in }
    var onMinimize: (WinItem) -> Void = { _ in }
    var onFill: (WinItem) -> Void = { _ in }
    var onFullScreen: (WinItem) -> Void = { _ in }
    var onNewWindow: (WinItem) -> Void = { _ in }
}

// MARK: - Görünümler

struct PreviewView: View {
    @ObservedObject var model: PreviewModel

    var body: some View {
        // Uygulama adı/simgesi gösterilmiyor: hangi uygulamanın üzerinde olunduğu Dock'tan zaten belli.
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Layout.cardSpacing) {
                    ForEach(model.windows) { w in
                        CardView(item: w, appName: model.appName, model: model)
                    }
                }
            }
            .frame(height: Layout.cardH)
        }
        .padding(Layout.outerPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CardView: View {
    let item: WinItem
    let appName: String
    let model: PreviewModel
    private let hoverState = State(initialValue: false)
    private var hover: Bool { hoverState.wrappedValue }

    var body: some View {
        VStack(spacing: 0) {
            // Üstte uygulama simgesi + pencere adı
            HStack(spacing: 5) {
                if let icon = model.appIcon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(item.title.isEmpty ? appName : item.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: item.thumbW, height: Layout.titleH, alignment: .leading)
            .padding(.bottom, Layout.titleGap)

            thumbnail
                .frame(width: item.thumbW, height: Layout.thumbH)
                .contentShape(Rectangle())
                .onTapGesture { model.onFocus(item) }

            // Altta kontrol düğmeleri
            WindowControls(closeQuits: UserDefaults.standard.bool(forKey: "closeQuitsApp"),
                           onNew: { model.onNewWindow(item) },
                           onMinimize: { model.onMinimize(item) },
                           onFill: { model.onFill(item) },
                           onFullScreen: { model.onFullScreen(item) },
                           onClose: { model.onClose(item) })
                .frame(width: item.thumbW, height: Layout.footerH, alignment: .center)
                .padding(.top, Layout.footerGap)
        }
        .padding(Layout.cardPad)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(hover ? 0.10 : 0))
        )
        .onHover { hoverState.wrappedValue = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
    }

    @ViewBuilder var thumbnail: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.05))
            if let img = item.image {
                Image(decorative: img, scale: 1)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: item.thumbW, height: Layout.thumbH)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .opacity(item.minimized ? 0.45 : 1)
            } else if !item.minimized {
                ProgressView().controlSize(.small)
            }
            if item.minimized {
                Text("Küçültüldü")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(.black.opacity(0.45)))
                    .foregroundStyle(.white)
            }
        }
    }
}

struct CtrlButton: View {
    let symbol: String
    let help: String
    var destructive = false
    let action: () -> Void
    private let hoverState = State(initialValue: false)
    private var hover: Bool { hoverState.wrappedValue }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .frame(width: 18, height: 18)
                .foregroundStyle(hover ? Color.white : Color.secondary)
                .background(
                    Circle().fill(hover ? (destructive ? Color.red : Color.accentColor)
                                        : Color.primary.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hoverState.wrappedValue = $0 }
    }
}

final class ClickThroughHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Kontrolcü

@MainActor
final class Controller {
    let model = PreviewModel()
    let panel: NSPanel
    let systemWide = AXUIElementCreateSystemWide()

    var currentPID: pid_t?
    var suppressedPID: pid_t?
    var lastInside = Date.distantPast
    var token = 0
    var timer: Timer?

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: Layout.panelH),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.cornerCurve = .continuous
        blur.layer?.masksToBounds = true
        blur.layer?.borderWidth = 0.5
        blur.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let host = ClickThroughHostingView(rootView: PreviewView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            host.topAnchor.constraint(equalTo: blur.topAnchor),
            host.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        panel.contentView = blur

        model.onFocus = { [weak self] in self?.focus($0) }
        model.onClose = { [weak self] in self?.close($0) }
        model.onMinimize = { [weak self] in self?.toggleMinimize($0) }
        model.onFill = { [weak self] in self?.fill($0, fullScreen: false) }
        model.onFullScreen = { [weak self] in self?.fill($0, fullScreen: true) }
        model.onNewWindow = { [weak self] _ in
            guard let self, let pid = self.currentPID else { return }
            self.suppressedPID = pid
            self.hide()
            WindowActions.newWindow(pid: pid)
        }
    }

    func start() {
        setTickInterval(Self.slowTick)

        // Dock'a tıklanınca önizlemeyi kapat.
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                if !self.panel.frame.contains(NSEvent.mouseLocation) {
                    self.suppressedPID = self.currentPID
                    self.hide()
                }
            }
        }
    }

    // MARK: Hover takibi

    // Dock'un PID'i önbellekte tutulur (her karede tüm uygulamaları taramamak için).
    var cachedDockPID: pid_t?
    var dockPID: pid_t? {
        if let p = cachedDockPID, kill(p, 0) == 0 { return p }
        cachedDockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        return cachedDockPID
    }
    /// Dock'un ekrandaki alanı; saniyede bir güncellenir. Fare buradan uzaksa AX sorgusu yapılmaz.
    var dockRect: CGRect?

    func dockItemUnderMouse() -> (NSRunningApplication, CGRect)? {
        guard let dockPID, let primary = NSScreen.screens.first else { return nil }
        let loc = NSEvent.mouseLocation
        var found: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(systemWide, Float(loc.x), Float(primary.frame.height - loc.y), &found)
        guard err == .success, let el = found else { noteHover("no element (AX error \(err.rawValue))"); return nil }
        var pid: pid_t = 0
        AXUIElementGetPid(el, &pid)
        guard pid == dockPID else { noteHover("not dock (pid \(pid))"); return nil }
        let subrole = axString(el, kAXSubroleAttribute) ?? "-"
        let url = axValue(el, kAXURLAttribute) as? URL
        noteHover("dock item role=\(axString(el, kAXRoleAttribute) ?? "-") subrole=\(subrole) url=\(url?.path ?? "-")")
        guard subrole == "AXApplicationDockItem", let url,
              let pos = axPoint(el, kAXPositionAttribute),
              let size = axSize(el, kAXSizeAttribute) else { return nil }
        let path = url.standardizedFileURL.path
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleURL?.standardizedFileURL.path == path
        }) else { return nil }
        // AX koordinatı (sol üst) → Cocoa koordinatı (sol alt)
        let rect = CGRect(x: pos.x, y: primary.frame.height - pos.y - size.height, width: size.width, height: size.height)
        return (app, rect)
    }

    var lastHoverDesc = ""
    func noteHover(_ d: String) {
        guard debugLogging, d != lastHoverDesc else { return }
        lastHoverDesc = d; dlog("hover: " + d)
    }

    var lastTick: CFTimeInterval = 0
    // Uyarlanır hız: fare Dock'a yakınken saniyede 20 kontrol (hızlı tepki), uzaktayken 4 (pil dostu).
    static let fastTick: TimeInterval = 0.05
    static let slowTick: TimeInterval = 0.25
    var tickInterval: TimeInterval = 0

    func setTickInterval(_ i: TimeInterval) {
        guard i != tickInterval else { return }
        tickInterval = i
        timer?.invalidate()
        let t = Timer(timeInterval: i, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = i * 0.2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    /// İzin durumu önbellekte (her fare hareketinde sistemden sormamak için); saniyede bir yenilenir.
    var axTrusted = AXIsProcessTrusted()
    var lastAttempt = Date.distantPast

    func tick() {
        lastTick = CACurrentMediaTime()
        let mouse = NSEvent.mouseLocation
        if panel.isVisible && panel.frame.insetBy(dx: -4, dy: -4).contains(mouse) {
            lastInside = Date()
            return
        }
        // İzin yoksa her karede başarısız AX sorgusu yapma (boşuna işlemci harcar).
        if dockRect == nil && !axTrusted { return }
        let nearDock = dockRect.map { $0.insetBy(dx: -20, dy: -40).contains(mouse) } ?? true
        // Dock'a yaklaşırken (biraz daha geniş alan) hızlı moda geç.
        let approaching = dockRect.map { $0.insetBy(dx: -60, dy: -160).contains(mouse) } ?? true
        setTickInterval(approaching || currentPID != nil || panel.isVisible ? Self.fastTick : Self.slowTick)
        if currentPID == nil && !nearDock { return }   // boşta: hiçbir şey yapma
        if nearDock, let (app, rect) = dockItemUnderMouse(), app.processIdentifier != getpid() {
            let pid = app.processIdentifier
            if pid == suppressedPID { return }
            suppressedPID = nil
            lastInside = Date()
            if pid != currentPID {
                show(app: app, itemRect: rect)
            } else if !panel.isVisible && Date().timeIntervalSince(lastAttempt) > 0.5 {
                show(app: app, itemRect: rect)   // ilk denemede pencere bulunamadıysa tekrar dene
            }
            return
        }
        suppressedPID = nil
        if currentPID != nil && Date().timeIntervalSince(lastInside) > 0.35 { hide() }
    }

    // MARK: Göster / gizle

    func windows(of app: NSRunningApplication) -> [WinItem] {
        let pid = app.processIdentifier
        let appEl = AXUIElementCreateApplication(pid)
        return WindowFinder.windows(pid: pid).map { w in
            WinItem(id: w.id, title: w.title, ax: w.ax ?? appEl, minimized: w.minimized,
                    aspect: w.size.width / max(w.size.height, 1))
        }
    }

    func show(app: NSRunningApplication, itemRect: CGRect) {
        currentPID = app.processIdentifier
        lastAttempt = Date()
        token += 1
        let items = windows(of: app)
        if debugLogging { dlog("show \(app.localizedName ?? "?") windows=\(items.count)") }
        guard !items.isEmpty else { panel.orderOut(nil); return }

        model.appName = app.localizedName ?? ""
        model.appIcon = app.icon
        model.windows = items
        layout(itemRect: itemRect)
        panel.orderFrontRegardless()
        panel.invalidateShadow()
        captureThumbnails(ids: items.map(\.id), token: token)
    }

    func hide() {
        panel.orderOut(nil)
        currentPID = nil
        token += 1
        model.windows = []          // önizleme görüntülerini bellekten bırak
    }

    var lastItemRect = CGRect.zero

    func layout(itemRect: CGRect) {
        lastItemRect = itemRect
        let center = CGPoint(x: itemRect.midX, y: itemRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main ?? NSScreen.screens[0]
        let sf = screen.frame
        let w = min(Layout.panelW(items: model.windows), sf.width - 16)
        let h = Layout.panelH
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        var o: CGPoint
        switch orientation {
        case "left":  o = CGPoint(x: itemRect.maxX + 6, y: itemRect.midY - h / 2)
        case "right": o = CGPoint(x: itemRect.minX - w - 6, y: itemRect.midY - h / 2)
        default:
            // Dock camının görünen üst kenarının hemen üstü: macOS'un kendi isim etiketini örter.
            //   Ayar: defaults write local.hexdock pvGap -float 3
            let d = UserDefaults.standard
            let gap = CGFloat(d.object(forKey: "pvGap") as? Double ?? 10)   // varsayılan: Ferah
            let base = dockRect.map { $0.maxY + CGFloat(d.double(forKey: "npOffsetY")) } ?? (itemRect.maxY + 3)
            o = CGPoint(x: itemRect.midX - w / 2, y: base + gap)
        }
        o.x = max(sf.minX + 8, min(o.x, sf.maxX - w - 8))
        o.y = max(sf.minY + 8, min(o.y, sf.maxY - h - 8))
        panel.setFrame(NSRect(origin: o, size: CGSize(width: w, height: h)), display: true)
    }

    func captureThumbnails(ids: [CGWindowID], token: Int) {
        guard CGPreflightScreenCaptureAccess() else { return }
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            for id in ids {
                guard token == self.token else { return }
                guard let win = content.windows.first(where: { $0.windowID == id }), win.isOnScreen else { continue }
                let filter = SCContentFilter(desktopIndependentWindow: win)
                let cfg = SCStreamConfiguration()
                let scale = min(1, 480 / max(win.frame.width, 1))
                cfg.width = max(1, Int(win.frame.width * scale))
                cfg.height = max(1, Int(win.frame.height * scale))
                cfg.showsCursor = false
                guard let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) else { continue }
                guard token == self.token, let i = self.model.windows.firstIndex(where: { $0.id == id }) else { continue }
                self.model.windows[i].image = img
            }
        }
    }

    // MARK: Pencere işlemleri

    func focus(_ item: WinItem) {
        guard let pid = currentPID, let app = NSRunningApplication(processIdentifier: pid) else { return }
        if item.minimized {
            AXUIElementSetAttributeValue(item.ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(item.ax, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(item.ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        suppressedPID = pid
        hide()
    }

    func close(_ item: WinItem) {
        guard let pid = currentPID else { return }
        if WindowActions.close(item.ax, id: item.id, pid: pid, allowQuit: true) {
            suppressedPID = pid
            hide()
            return
        }
        model.windows.removeAll { $0.id == item.id }
        if model.windows.isEmpty { hide() } else { layout(itemRect: lastItemRect) }
    }

    /// Yerleştir: pencereyi, bulunduğu ekranın görünen alanına (menü çubuğu ve Dock hariç) tam oturtur.
    /// Ayarlarda "tam ekran" seçiliyse bunun yerine macOS'un gerçek tam ekran modunu açar/kapatır.
    func fill(_ item: WinItem, fullScreen: Bool) {
        let win = item.ax
        if item.minimized {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        if fullScreen {
            let isFull = axBool(win, "AXFullScreen")
            AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, isFull ? kCFBooleanFalse : kCFBooleanTrue)
        } else if let primary = NSScreen.screens.first {
            // Pencerenin ortası hangi ekrandaysa o ekranın görünen alanı.
            let pos = axPoint(win, kAXPositionAttribute) ?? .zero
            let size = axSize(win, kAXSizeAttribute) ?? .zero
            let center = CGPoint(x: pos.x + size.width / 2, y: primary.frame.height - (pos.y + size.height / 2))
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? primary
            let vf = screen.visibleFrame
            // Cocoa (sol alt) → AX (sol üst) koordinatı
            var newPos = CGPoint(x: vf.minX, y: primary.frame.height - vf.maxY)
            var newSize = vf.size
            if let p = AXValueCreate(.cgPoint, &newPos), let s = AXValueCreate(.cgSize, &newSize) {
                // Önce konum, sonra boyut, sonra yine konum: bazı uygulamalar ekran kenarında boyutu kısıtlıyor.
                AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
                AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s)
                AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
            }
        }
        focus(item)   // pencereyi öne getirir ve paneli kapatır
    }

    func toggleMinimize(_ item: WinItem) {
        let newValue = !item.minimized
        AXUIElementSetAttributeValue(item.ax, kAXMinimizedAttribute as CFString,
                                     newValue ? kCFBooleanTrue : kCFBooleanFalse)
        if let i = model.windows.firstIndex(where: { $0.id == item.id }) {
            model.windows[i].minimized = newValue
        }
    }

}

// MARK: - Menü çubuğu simgesi

/// Kodla çizilen küçük simge: Dock çubuğunun üstünde açılmış bir önizleme penceresi.
/// Şablon görsel olduğu için açık/koyu menü çubuğuna kendiliğinden uyar; dosya gerektirmez.
func menuBarIcon() -> NSImage {
    let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
        NSColor.black.set()
        // İnce çerçeveli önizleme penceresi
        let win = NSBezierPath(roundedRect: NSRect(x: 3.5, y: 6.5, width: 11, height: 8), xRadius: 2, yRadius: 2)
        win.lineWidth = 1.1
        win.stroke()
        // Altında ince Dock çizgisi
        NSBezierPath(roundedRect: NSRect(x: 3, y: 2.5, width: 12, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
        return true
    }
    img.isTemplate = true
    img.accessibilityDescription = "HexDock"
    return img
}

// MARK: - Uygulama

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let controller = Controller()
    let nowPlaying = NowPlayingController()
    let switcher = SwitcherController()
    var switcherItem: NSMenuItem!
    var shortcutItems: [NSMenuItem] = []
    var customShortcutItem: NSMenuItem!
    var statusItem: NSStatusItem!
    var axItem: NSMenuItem!
    var screenItem: NSMenuItem!
    var quitItem: NSMenuItem!
    var spotifyItem: NSMenuItem!
    var loginItem: NSMenuItem!
    var fullItem: NSMenuItem!
    var modeItems: [NSMenuItem] = []
    var gapItems: [NSMenuItem] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Donmuş bir uygulamayı sorgularken en fazla 0,5 sn bekle (varsayılan 6 sn).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = menuBarIcon()

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: "Genel"))
        loginItem = item("Girişte başlat", #selector(toggleLogin))
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "İzinler"))
        axItem = item("Erişilebilirlik", #selector(openAX))
        screenItem = item("Ekran kaydı", #selector(openScreen))
        menu.addItem(axItem)
        menu.addItem(screenItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Pencere önizlemesi"))
        let modeMenu = NSMenu()
        for (title, mode) in [("Ekrana yerleştir", "fill"), ("Tam ekran", "full"), ("İkisi birden", "both")] {
            let i = item(title, #selector(setMode(_:)))
            i.representedObject = mode
            modeMenu.addItem(i)
            modeItems.append(i)
        }
        fullItem = NSMenuItem(title: "Büyütme düğmesi", action: nil, keyEquivalent: "")
        fullItem.submenu = modeMenu
        let gapMenu = NSMenu()
        for (title, value) in [("Ferah", 10.0), ("Yakın", 3.0)] {
            let i = item(title, #selector(setGap(_:)))
            i.representedObject = value
            gapMenu.addItem(i)
            gapItems.append(i)
        }
        let gapItem = NSMenuItem(title: "Dock'a mesafe", action: nil, keyEquivalent: "")
        gapItem.submenu = gapMenu
        menu.addItem(gapItem)
        quitItem = item("Önizlemede × uygulamadan çıksın", #selector(toggleQuit))
        menu.addItem(fullItem)
        menu.addItem(quitItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Pencere değiştirici"))
        switcherItem = item("Açık", #selector(toggleSwitcher))
        menu.addItem(switcherItem)
        let scMenu = NSMenu()
        for sc in SwitcherShortcut.allCases {
            let i = item(sc.title, #selector(setShortcut(_:)))
            i.representedObject = sc.rawValue
            scMenu.addItem(i)
            shortcutItems.append(i)
        }
        scMenu.addItem(.separator())
        customShortcutItem = item("Özel", #selector(noop))
        customShortcutItem.isEnabled = false
        scMenu.addItem(customShortcutItem)
        scMenu.addItem(item("Özel kısayol ayarla…", #selector(recordShortcut)))
        let scItem = NSMenuItem(title: "Kısayol", action: nil, keyEquivalent: "")
        scItem.submenu = scMenu
        menu.addItem(scItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem.sectionHeader(title: "Müzik"))
        spotifyItem = item("Müzik kutusunu göster", #selector(toggleSpotify))
        menu.addItem(spotifyItem)

        menu.addItem(.separator())
        menu.addItem(item("HexDock'tan çık", #selector(quit), key: "q"))
        menu.delegate = self
        statusItem.menu = menu

        controller.start()
        nowPlaying.start()
        switcher.start()
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let dock = currentDockFrame()
                self.controller.dockRect = dock
                self.controller.axTrusted = AXIsProcessTrusted()
                self.nowPlaying.update(dock: dock)
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        dlog("launch ax=\(AXIsProcessTrusted()) screen=\(CGPreflightScreenCaptureAccess())")
    }

    func item(_ title: String, _ sel: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = self
        return i
    }

    // Menü her açıldığında izin durumunu göster (✓ verildi / ✗ verilmedi).
    func menuWillOpen(_ menu: NSMenu) {
        quitItem.state = UserDefaults.standard.bool(forKey: "closeQuitsApp") ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        spotifyItem.state = UserDefaults.standard.bool(forKey: "spotifyDisabled") ? .off : .on
        switcherItem.state = switcherEnabled ? .on : .off
        let spec = ShortcutSpec.current
        let sc = SwitcherShortcut.current.rawValue
        for i in shortcutItems { i.state = !spec.isCustom && (i.representedObject as? String) == sc ? .on : .off }
        customShortcutItem.isHidden = !spec.isCustom
        customShortcutItem.title = "Özel: \(spec.label)"
        customShortcutItem.state = spec.isCustom ? .on : .off
        let gap = UserDefaults.standard.object(forKey: "pvGap") as? Double ?? 10
        for i in gapItems { i.state = (i.representedObject as? Double) == gap ? .on : .off }
        let mode = middleMode
        for i in modeItems { i.state = (i.representedObject as? String) == mode ? .on : .off }
        // İzinler: verildiyse tik; verilmediyse tıklayınca ayarları açar.
        axItem.state = AXIsProcessTrusted() ? .on : .off
        axItem.title = AXIsProcessTrusted() ? "Erişilebilirlik" : "Erişilebilirlik — izin ver…"
        screenItem.state = CGPreflightScreenCaptureAccess() ? .on : .off
        screenItem.title = CGPreflightScreenCaptureAccess() ? "Ekran kaydı" : "Ekran kaydı — izin ver…"
    }

    @objc func toggleSwitcher() {
        UserDefaults.standard.set(!switcherEnabled, forKey: "switcherEnabled")
        switcher.refreshTapState()
    }

    @objc func setShortcut(_ sender: NSMenuItem) {
        let d = UserDefaults.standard
        d.set(sender.representedObject as? String ?? "option", forKey: "switcherShortcut")
        // Hazır bir seçenek seçilince özel kısayol kalkar.
        for k in ["switcherKeyCode", "switcherMods", "switcherLabel"] { d.removeObject(forKey: k) }
        switcher.refreshTapState()
    }

    @objc func recordShortcut() { ShortcutRecorder.open {} }
    @objc func noop() {}

    @objc func setGap(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? Double ?? 10, forKey: "pvGap")
    }

    @objc func setMode(_ sender: NSMenuItem) {
        UserDefaults.standard.set(sender.representedObject as? String ?? "fill", forKey: "middleMode")
    }

    @objc func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            dlog("login item error: \(error)")
            // Olmazsa Giriş Öğeleri ayarlarını aç, kullanıcı elle eklesin.
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    @objc func toggleSpotify() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "spotifyDisabled"), forKey: "spotifyDisabled")
        nowPlaying.update(dock: controller.dockRect)   // hemen uygula
    }

    @objc func toggleQuit() {
        let d = UserDefaults.standard
        d.set(!d.bool(forKey: "closeQuitsApp"), forKey: "closeQuitsApp")
    }

    @objc func openAX() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)   // uygulamayı listeye ekler
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func openScreen() {
        _ = CGRequestScreenCaptureAccess()        // uygulamayı listeye ekler
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }
    @objc func quit() { NSApp.terminate(nil) }
}

MainActor.assumeIsolated {
    if CommandLine.arguments.contains("--selftest") {
        SelfTest.run()
        exit(0)
    }
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
