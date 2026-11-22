// Windows tarzı pencere değiştirici: kısayolu basılı tutup Tab'a basınca tüm açık pencereler görünür.
// Tab / Shift+Tab / ok tuşları ile seç, tuşu bırakınca seçilen pencere öne gelir. Esc vazgeçer.
import Cocoa
import SwiftUI
import ScreenCaptureKit
import ApplicationServices

// MARK: - Ayarlar

enum SwitcherShortcut: String, CaseIterable {
    case option, command, control
    var title: String {
        switch self {
        case .option: return "⌥ Option + Tab"
        case .command: return "⌘ Command + Tab (macOS'unkinin yerine)"
        case .control: return "⌃ Control + Tab"
        }
    }
    var flag: CGEventFlags {
        switch self {
        case .option: return .maskAlternate
        case .command: return .maskCommand
        case .control: return .maskControl
        }
    }
    static var current: SwitcherShortcut {
        SwitcherShortcut(rawValue: UserDefaults.standard.string(forKey: "switcherShortcut") ?? "") ?? .option
    }
}

/// Etkin kısayol: hazır seçeneklerden biri ya da kullanıcının kaydettiği özel kısayol.
struct ShortcutSpec {
    var keyCode: Int64
    var mods: CGEventFlags      // ⌘ ⌥ ⌃ ⇧ kombinasyonu
    var label: String
    var isCustom: Bool

    static let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    static var current: ShortcutSpec {
        let d = UserDefaults.standard
        if d.object(forKey: "switcherKeyCode") != nil {
            return ShortcutSpec(keyCode: Int64(d.integer(forKey: "switcherKeyCode")),
                                mods: CGEventFlags(rawValue: UInt64(d.integer(forKey: "switcherMods"))),
                                label: d.string(forKey: "switcherLabel") ?? "Özel", isCustom: true)
        }
        let p = SwitcherShortcut.current
        return ShortcutSpec(keyCode: 48, mods: p.flag, label: p.title, isCustom: false)
    }
    /// Tuşu bırakınca seçim yapılsın diye izlenen değiştiriciler (⇧ hariç; ⇧ geri gitmek için).
    var holdMods: CGEventFlags {
        let m = mods.subtracting(.maskShift)
        return m.isEmpty ? mods : m
    }
}

var switcherEnabled: Bool {
    UserDefaults.standard.object(forKey: "switcherEnabled") as? Bool ?? true
}

// MARK: - Model

struct SwitchItem: Identifiable {
    let id: CGWindowID
    let pid: pid_t
    let title: String
    let appName: String
    let icon: NSImage?
    let ax: AXUIElement
    let minimized: Bool
    let hidden: Bool
    var image: CGImage?
    var otherSpace = false
}

final class SwitcherModel: ObservableObject {
    @Published var items: [SwitchItem] = []
    @Published var selected = 0
    @Published var columns = 5
    var onPick: (Int) -> Void = { _ in }
    var onAction: (Int, String) -> Void = { _, _ in }
}

enum SwitcherLayout {
    static let thumbW: CGFloat = 200
    static let thumbH: CGFloat = 125
    static let cellPad: CGFloat = 8
    static let labelH: CGFloat = 18
    static let controlsH: CGFloat = 20
    static let spacing: CGFloat = 8
    static let outer: CGFloat = 14
    static var cellW: CGFloat { thumbW + cellPad * 2 }
    static var cellH: CGFloat { labelH + 6 + thumbH + 6 + controlsH + cellPad * 2 }
}

// MARK: - Görünüm

struct SwitcherView: View {
    @ObservedObject var model: SwitcherModel

    var body: some View {
        let rows = stride(from: 0, to: model.items.count, by: max(model.columns, 1)).map {
            Array($0..<min($0 + model.columns, model.items.count))
        }
        VStack(spacing: SwitcherLayout.spacing) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: SwitcherLayout.spacing) {
                    ForEach(row, id: \.self) { i in
                        SwitchCell(item: model.items[i], selected: i == model.selected,
                                   pick: { model.onPick(i) }, action: { model.onAction(i, $0) })
                            .onHover { if $0 { model.selected = i } }
                    }
                }
            }
        }
        .padding(SwitcherLayout.outer)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SwitchCell: View {
    let item: SwitchItem
    let selected: Bool
    let pick: () -> Void
    let action: (String) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Üstte uygulama simgesi ve pencere adı
            HStack(spacing: 5) {
                if let icon = item.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                Text(item.title.isEmpty ? item.appName : item.title)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .frame(width: SwitcherLayout.thumbW, height: SwitcherLayout.labelH)
            .contentShape(Rectangle())
            .onTapGesture(perform: pick)

            ZStack {
                if let img = item.image {
                    Image(decorative: img, scale: 1)
                        .resizable().interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                } else if let icon = item.icon {
                    Image(nsImage: icon).resizable().frame(width: 64, height: 64).opacity(0.85)
                }
                if item.minimized || item.hidden || item.otherSpace {
                    Text(item.minimized ? "Küçültüldü" : item.hidden ? "Gizli" : "Diğer masaüstü")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.5)))
                        .foregroundStyle(.white)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 6)
                }
            }
            .frame(width: SwitcherLayout.thumbW, height: SwitcherLayout.thumbH)
            .contentShape(Rectangle())
            .onTapGesture(perform: pick)

            // Altta Dock önizlemesindeki kontrol düğmeleri
            WindowControls(onNew: { action("new") }, onMinimize: { action("minimize") },
                           onFill: { action("fill") }, onFullScreen: { action("full") },
                           onClose: { action("close") })
                .frame(width: SwitcherLayout.thumbW, height: SwitcherLayout.controlsH, alignment: .center)
        }
        .padding(SwitcherLayout.cellPad)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.30) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor.opacity(0.9) : Color.clear, lineWidth: 2)
        )
    }
}

// MARK: - Kontrolcü

@MainActor
final class SwitcherController {
    static var shared: SwitcherController?

    let model = SwitcherModel()
    let panel: NSPanel
    var visible = false
    var recording = false        // kısayol kaydedilirken tuşları yakalama
    var token = 0
    var retryTimer: Timer?
    var loggedTapFailure = false

    init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Tam ekran oyunlar ekranı "kalkan" katmanıyla kaplayabiliyor; değiştirici onun da üstünde açılsın.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.hidesOnDeactivate = false
        // Her masaüstünde ve tam ekran uygulamaların üstünde görünebilsin.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let glass = NSGlassEffectView()
        glass.cornerRadius = 22
        glass.contentView = ClickThroughHostingView(rootView: SwitcherView(model: model))
        panel.contentView = glass

        model.onPick = { [weak self] i in
            self?.model.selected = i
            self?.commit()
        }
        model.onAction = { [weak self] i, a in self?.perform(a, at: i) }
        Self.shared = self
    }

    // MARK: Klavye dinleme (Erişilebilirlik izni gerekir)
    //
    // Klavye dinleyicisi ana iş parçacığında DEĞİL, kendi arka plan iş parçacığında çalışır.
    // Böylece HexDock bir an meşgul olsa bile (ör. donmuş bir uygulamayı sorgularken) yazdığın
    // tuşlar gecikmez. İlgisiz tuşlar mikro saniyeler içinde, hiç dokunulmadan geçirilir.

    func start() {
        refreshTapState()
        installTap()
        // İzin sonradan verilirse kur; izin geri alınırsa hemen kaldır (aksi halde macOS klavyeyi kilitleyebilir).
        retryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchdog() }
        }
    }

    /// Ayarları dinleyicinin okuyacağı anlık kopyaya aktarır.
    func refreshTapState() {
        let spec = ShortcutSpec.current
        tapState.lock.lock()
        tapState.enabled = switcherEnabled
        tapState.recording = recording
        tapState.keyCode = spec.keyCode
        tapState.mods = spec.mods
        tapState.holdMods = spec.holdMods
        tapState.lock.unlock()
    }

    func setVisible(_ v: Bool) {
        visible = v
        tapState.lock.lock(); tapState.visible = v; tapState.lock.unlock()
    }

    func watchdog() {
        refreshTapState()
        let trusted = AXIsProcessTrusted()
        if trusted && tapState.tap == nil { installTap() }
        if !trusted && tapState.tap != nil { removeTap() }
        // Tuş bırakma olayı kaçırıldıysa değiştirici açık kalmasın.
        if visible && !CGEventSource.flagsState(.combinedSessionState).contains(ShortcutSpec.current.holdMods) {
            commit()
        }
    }

    func installTap() {
        guard tapState.tap == nil, AXIsProcessTrusted() else { return }
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
            guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                            eventsOfInterest: mask, callback: switcherTapCallback, userInfo: nil) else {
                ready.signal()
                return
            }
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0), .commonModes)
            CGEvent.tapEnable(tap: t, enable: true)
            tapState.lock.lock(); tapState.tap = t; tapState.runLoop = rl; tapState.lock.unlock()
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "HexDock.keyboard"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        if tapState.tap == nil && !loggedTapFailure {   // her saniye diske yazmasın: yalnızca bir kez
            loggedTapFailure = true
            dlog("switcher: event tap could not be created")
        }
    }

    func removeTap() {
        tapState.lock.lock()
        let t = tapState.tap, rl = tapState.runLoop
        tapState.tap = nil; tapState.runLoop = nil
        tapState.lock.unlock()
        if let t { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let rl { CFRunLoopStop(rl) }
        if visible { cancel() }
    }

    /// Kısayola basıldı (ana iş parçacığında).
    func shortcutPressed(back: Bool) {
        if visible { move(back ? -1 : 1) } else { show(back: back) }
    }

    /// Değiştirici açıkken basılan diğer tuşlar (ana iş parçacığında).
    func keyWhileVisible(_ keyCode: Int64) {
        guard visible else { return }
        switch keyCode {
        case 53: cancel()                          // Esc
        case 36, 76: commit()                      // Return / Enter
        case 123: move(-1)                         // ←
        case 124: move(1)                          // →
        case 126: move(-model.columns)             // ↑
        case 125: move(model.columns)              // ↓
        default: break
        }
    }

    // MARK: Pencereleri topla

    func gatherWindows() -> [SwitchItem] {
        let me = getpid()
        var axCache: [pid_t: (byID: [CGWindowID: AXUIElement], unmatched: [AXUIElement])] = [:]
        func ax(_ pid: pid_t) -> (byID: [CGWindowID: AXUIElement], unmatched: [AXUIElement]) {
            if let c = axCache[pid] { return c }
            let r = WindowFinder.axWindows(pid); axCache[pid] = r; return r
        }

        var items: [SwitchItem] = []
        var seen = Set<CGWindowID>()
        // 1) Ekrandaki pencereler, önden arkaya (en son kullanılan önce)
        for c in WindowFinder.onScreen() where c.pid != me {
            guard let app = NSRunningApplication(processIdentifier: c.pid), app.activationPolicy == .regular else { continue }
            let a = ax(c.pid)
            let el = a.byID[c.id] ?? WindowFinder.match(c.bounds, in: a.unmatched)
            seen.insert(c.id)
            items.append(SwitchItem(id: c.id, pid: c.pid,
                                    title: el.flatMap { axString($0, kAXTitleAttribute) } ?? c.name,
                                    appName: app.localizedName ?? "", icon: app.icon,
                                    ax: el ?? AXUIElementCreateApplication(c.pid), minimized: false, hidden: false))
        }
        // 2) Başka masaüstündeki ve tam ekrandaki pencereler (oyunlar dahil)
        for c in WindowFinder.allSpaces() where !c.onScreen && !seen.contains(c.id) && c.pid != me {
            guard let app = NSRunningApplication(processIdentifier: c.pid), app.activationPolicy == .regular, !app.isHidden,
                  let el = WindowFinder.isRealOffscreen(id: c.id, bounds: c.bounds, ax: ax(c.pid)) else { continue }
            seen.insert(c.id)
            items.append(SwitchItem(id: c.id, pid: c.pid,
                                    title: el.flatMap { axString($0, kAXTitleAttribute) } ?? c.name,
                                    appName: app.localizedName ?? "", icon: app.icon,
                                    ax: el ?? AXUIElementCreateApplication(c.pid), minimized: false, hidden: false,
                                    otherSpace: true))
        }
        // 3) Ekranı ele geçiren tam ekran oyunlar (normal penceresi olmayan uygulamalar)
        let listed = Set(items.map(\.pid))
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && app.processIdentifier != me && !listed.contains(app.processIdentifier) {
            guard let g = WindowFinder.capturedFullscreen(pid: app.processIdentifier) else { continue }
            seen.insert(g.id)
            items.append(SwitchItem(id: g.id, pid: app.processIdentifier,
                                    title: g.name.isEmpty ? (app.localizedName ?? "") : g.name,
                                    appName: app.localizedName ?? "", icon: app.icon,
                                    ax: AXUIElementCreateApplication(app.processIdentifier),
                                    minimized: false, hidden: false, otherSpace: true))
        }
        // 4) Küçültülmüş ve gizli uygulamaların pencereleri sona
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app.processIdentifier != me {
            for (id, el) in ax(app.processIdentifier).byID where !seen.contains(id) {
                let minimized = axBool(el, kAXMinimizedAttribute)
                guard minimized || app.isHidden else { continue }
                guard axString(el, kAXSubroleAttribute) == kAXStandardWindowSubrole as String || minimized else { continue }
                items.append(SwitchItem(id: id, pid: app.processIdentifier, title: axString(el, kAXTitleAttribute) ?? "",
                                        appName: app.localizedName ?? "", icon: app.icon, ax: el,
                                        minimized: minimized, hidden: app.isHidden))
            }
        }
        return items
    }

    // MARK: Göster / seç / kapat

    func show(back: Bool) {
        let items = gatherWindows()
        guard !items.isEmpty else { setVisible(false); return }
        setVisible(true)
        token += 1
        model.items = items
        // Windows'taki gibi: ilk Tab bir önceki pencereye geçer.
        model.selected = items.count > 1 ? (back ? items.count - 1 : 1) : 0

        layoutPanel()
        panel.orderFrontRegardless()
        captureThumbnails(token: token)
    }

    func layoutPanel() {
        let items = model.items
        guard !items.isEmpty else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        let maxCols = max(1, Int((vf.width * 0.9 - SwitcherLayout.outer * 2 + SwitcherLayout.spacing)
                                 / (SwitcherLayout.cellW + SwitcherLayout.spacing)))
        let cols = min(items.count, maxCols)
        let rows = Int(ceil(Double(items.count) / Double(cols)))
        model.columns = cols
        let w = CGFloat(cols) * SwitcherLayout.cellW + CGFloat(cols - 1) * SwitcherLayout.spacing + SwitcherLayout.outer * 2
        let h = min(CGFloat(rows) * SwitcherLayout.cellH + CGFloat(rows - 1) * SwitcherLayout.spacing + SwitcherLayout.outer * 2,
                    vf.height * 0.9)
        panel.setFrame(NSRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h), display: true)
    }

    /// Hücredeki düğmeler. Küçült/kapat değiştiriciyi açık tutar; diğerleri pencereye geçip değiştiriciyi kapatır.
    func perform(_ action: String, at i: Int) {
        guard model.items.indices.contains(i) else { return }
        let item = model.items[i]
        switch action {
        case "minimize":
            let v = !item.minimized
            WindowActions.setMinimized(item.ax, v)
            model.items[i] = SwitchItem(id: item.id, pid: item.pid, title: item.title, appName: item.appName,
                                        icon: item.icon, ax: item.ax, minimized: v, hidden: item.hidden, image: item.image)
        case "close":
            // Değiştiricide × her zaman yalnızca bu pencereyi kapatır.
            if WindowActions.close(item.ax, id: item.id, pid: item.pid, allowQuit: false) {
                model.items.removeAll { $0.pid == item.pid }   // son penceresiydi: uygulama kapandı
            } else {
                model.items.remove(at: i)
            }
            if model.items.isEmpty { cancel(); return }
            model.selected = min(model.selected, model.items.count - 1)
            layoutPanel()
        case "fill":
            cancel(); WindowActions.fill(item.ax, pid: item.pid)
        case "full":
            cancel(); WindowActions.toggleFullScreen(item.ax, pid: item.pid)
        case "new":
            cancel(); WindowActions.newWindow(pid: item.pid)
        default: break
        }
    }

    func move(_ delta: Int) {
        let n = model.items.count
        guard n > 0 else { return }
        model.selected = ((model.selected + delta) % n + n) % n
    }

    func cancel() {
        setVisible(false)
        token += 1
        panel.orderOut(nil)
        model.items = []          // görüntüleri bellekten bırak
    }

    func commit() {
        guard visible, model.items.indices.contains(model.selected) else { cancel(); return }
        let item = model.items[model.selected]
        cancel()
        WindowActions.focus(item.ax, pid: item.pid)
    }

    func captureThumbnails(token: Int) {
        guard CGPreflightScreenCaptureAccess() else { return }
        let ids = model.items.filter { !$0.minimized && !$0.hidden }.map(\.id)   // diğer masaüstündekiler de denenir
        Task { @MainActor in
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            for id in ids {
                guard token == self.token else { return }
                guard let win = content.windows.first(where: { $0.windowID == id }) else { continue }
                let cfg = SCStreamConfiguration()
                let scale = min(1, 400 / max(win.frame.width, 1))
                cfg.width = max(1, Int(win.frame.width * scale))
                cfg.height = max(1, Int(win.frame.height * scale))
                cfg.showsCursor = false
                guard let img = try? await SCScreenshotManager.captureImage(
                        contentFilter: SCContentFilter(desktopIndependentWindow: win), configuration: cfg),
                      token == self.token,
                      let i = self.model.items.firstIndex(where: { $0.id == id }) else { continue }
                self.model.items[i].image = img
            }
        }
    }
}

/// Dinleyicinin okuduğu ayar kopyası (kilitle korunur; arka plan iş parçacığından okunur).
final class TapState: @unchecked Sendable {
    let lock = NSLock()
    var enabled = true
    var recording = false
    var visible = false
    var keyCode: Int64 = 48
    var mods: CGEventFlags = .maskAlternate
    var holdMods: CGEventFlags = .maskAlternate
    var tap: CFMachPort?
    var runLoop: CFRunLoop?
}
let tapState = TapState()

/// Klavye olayları buraya ARKA PLAN iş parçacığında gelir. Ana iş parçacığını asla beklemez:
/// ilgisiz tuşları hemen geçirir, yalnızca kısayol ve değiştirici açıkken gereken tuşları yutar.
func switcherTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        tapState.lock.lock(); let t = tapState.tap; tapState.lock.unlock()
        if let t { CGEvent.tapEnable(tap: t, enable: true) }
        return pass
    }
    tapState.lock.lock()
    let enabled = tapState.enabled, recording = tapState.recording, visible = tapState.visible
    let keyCode = tapState.keyCode, mods = tapState.mods, holdMods = tapState.holdMods
    tapState.lock.unlock()
    guard enabled, !recording else { return pass }

    let flags = event.flags
    switch type {
    case .keyDown:
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let held = flags.intersection(ShortcutSpec.relevant)
        if code == keyCode && held.contains(mods) && held.subtracting(mods).isSubset(of: .maskShift) {
            let back = held.contains(.maskShift) && !mods.contains(.maskShift)
            tapState.lock.lock(); tapState.visible = true; tapState.lock.unlock()
            DispatchQueue.main.async { MainActor.assumeIsolated { SwitcherController.shared?.shortcutPressed(back: back) } }
            return nil
        }
        guard visible else { return pass }
        // Güvenlik: değiştirici tuş artık basılı değilse hiçbir tuşu yutma.
        guard flags.contains(holdMods) else {
            DispatchQueue.main.async { MainActor.assumeIsolated { SwitcherController.shared?.commit() } }
            return pass
        }
        DispatchQueue.main.async { MainActor.assumeIsolated { SwitcherController.shared?.keyWhileVisible(code) } }
        return nil
    case .keyUp:
        return visible ? nil : pass
    case .flagsChanged:
        if visible && !flags.contains(holdMods) {
            DispatchQueue.main.async { MainActor.assumeIsolated { SwitcherController.shared?.commit() } }
        }
        return pass                                   // değiştirici tuşlar hiçbir zaman yutulmaz
    default:
        return pass
    }
}

// MARK: - Özel kısayol kaydedici

@MainActor
final class ShortcutRecorder: NSObject, NSWindowDelegate {
    static var current: ShortcutRecorder?
    let window: NSWindow
    let keyLabel = NSTextField(labelWithString: "…")
    let hint = NSTextField(labelWithString: "En az bir ⌘ ⌥ ⌃ tuşu ve bir tuşa birlikte basın. Vazgeçmek için Esc.")
    var monitor: Any?
    var onDone: () -> Void = {}

    static func open(onDone: @escaping () -> Void) {
        current?.window.close()
        let r = ShortcutRecorder()
        r.onDone = onDone
        current = r
        r.start()
    }

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 150),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Pencere değiştirici kısayolu"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating

        let title = NSTextField(labelWithString: "Yeni kısayola basın")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        keyLabel.font = .monospacedSystemFont(ofSize: 22, weight: .medium)
        keyLabel.stringValue = ShortcutSpec.current.label
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping
        hint.preferredMaxLayoutWidth = 340
        let stack = NSStackView(views: [title, keyLabel, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 18, left: 20, bottom: 18, right: 20)
        window.contentView = stack
    }

    func start() {
        SwitcherController.shared?.recording = true
        SwitcherController.shared?.refreshTapState()
        NSApp.activate()
        window.center()
        window.makeKeyAndOrderFront(nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e) }
            return nil
        }
    }

    static func symbols(_ m: NSEvent.ModifierFlags) -> String {
        (m.contains(.control) ? "⌃" : "") + (m.contains(.option) ? "⌥" : "")
            + (m.contains(.shift) ? "⇧" : "") + (m.contains(.command) ? "⌘" : "")
    }

    static func keyName(_ e: NSEvent) -> String {
        switch e.keyCode {
        case 48: return "Tab"
        case 49: return "Space"
        case 36: return "Return"
        case 51: return "Delete"
        case 50: return "`"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return e.charactersIgnoringModifiers?.uppercased() ?? "#\(e.keyCode)"
        }
    }

    func handle(_ e: NSEvent) {
        let m = e.modifierFlags.intersection([.command, .option, .control, .shift])
        if e.type == .flagsChanged {
            keyLabel.stringValue = m.isEmpty ? ShortcutSpec.current.label : Self.symbols(m) + " …"
            return
        }
        if e.keyCode == 53 && m.isEmpty { finish(); return }                 // Esc: vazgeç
        guard !m.intersection([.command, .option, .control]).isEmpty else {
            hint.stringValue = "Bir ⌘, ⌥ ya da ⌃ tuşu gerekli (basılı tutup bırakınca pencere seçilir)."
            hint.textColor = .systemRed
            return
        }
        var flags: CGEventFlags = []
        if m.contains(.command) { flags.insert(.maskCommand) }
        if m.contains(.option) { flags.insert(.maskAlternate) }
        if m.contains(.control) { flags.insert(.maskControl) }
        if m.contains(.shift) { flags.insert(.maskShift) }
        let label = Self.symbols(m) + " " + Self.keyName(e)
        let d = UserDefaults.standard
        d.set(Int(e.keyCode), forKey: "switcherKeyCode")
        d.set(Int(flags.rawValue), forKey: "switcherMods")
        d.set(label, forKey: "switcherLabel")
        keyLabel.stringValue = label
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { MainActor.assumeIsolated { self.finish() } }
    }

    func finish() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        SwitcherController.shared?.recording = false
        SwitcherController.shared?.refreshTapState()
        window.close()
        onDone()
    }

    func windowWillClose(_ notification: Notification) {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        SwitcherController.shared?.recording = false
        SwitcherController.shared?.refreshTapState()
        if Self.current === self { Self.current = nil }
    }
}
