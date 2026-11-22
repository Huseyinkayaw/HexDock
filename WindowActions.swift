// Pencere işlemleri: hem Dock önizlemesi hem pencere değiştirici bunları kullanır.
import Cocoa
import SwiftUI
import ApplicationServices

@MainActor
enum WindowActions {
    /// Bir uygulamaya klavye kısayolu gönderir (ör. ⌘W, ⌘N).
    static func sendKey(_ key: CGKeyCode, flags: CGEventFlags, to pid: pid_t) {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.postToPid(pid)
        up?.postToPid(pid)
    }

    /// Pencereyi öne getirir (gerekirse küçültmeden çıkarır, gizli uygulamayı gösterir).
    static func focus(_ win: AXUIElement, pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        if axBool(win, kAXMinimizedAttribute) {
            AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// Kapat. `allowQuit` true ise ve "× uygulamadan çıksın" ayarı açıksa uygulamadan çıkar;
    /// aksi halde yalnızca bu pencereyi kapatır (diğer pencere ve sekmelere dokunmaz).
    /// Dönüş değeri: uygulamadan çıkıldıysa true.
    @discardableResult
    static func close(_ win: AXUIElement, id: CGWindowID, pid: pid_t, allowQuit: Bool) -> Bool {
        let app = NSRunningApplication(processIdentifier: pid)
        // Son (ya da tek) pencereyse uygulamadan çık. Finder hariç: o hep açık kalmalı.
        // (Adobe gibi pencerelerini Erişilebilirlik'e bildirmeyen uygulamalarda da çalışır;
        //  kaydedilmemiş iş varsa uygulama kendisi "Kaydedilsin mi?" diye sorar.)
        let isLast = standardWindowCount(pid) <= 1 && app?.bundleIdentifier != "com.apple.finder"
        if isLast || (allowQuit && UserDefaults.standard.bool(forKey: "closeQuitsApp")) {
            app?.terminate()
            return true
        }
        // Pencere AX ile eşleşmediyse tek bir pencereyi güvenle kapatamayız (⌘W yanlış şeyi kapatabilir):
        // uygulamayı öne getir, kullanıcı kendisi kapatsın.
        guard axString(win, kAXRoleAttribute) == kAXWindowRole as String else {
            focus(win, pid: pid)
            return false
        }
        // Pencerenin kendi kırmızı kapat düğmesine bas.
        if let btn = axValue(win, kAXCloseButtonAttribute), CFGetTypeID(btn) == AXUIElementGetTypeID(),
           AXUIElementPerformAction(btn as! AXUIElement, kAXPressAction as CFString) == .success {
            return false   // Uygulama "emin misiniz?" diye sorarsa karar kullanıcıda; ⌘W göndermiyoruz
                     // (tarayıcılarda ⌘W pencereyi değil sekmeyi kapatır).
        }
        // Kapat düğmesi yoksa: pencereyi öne alıp ⌘W.
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        sendKey(13 /* W */, flags: .maskCommand, to: pid)
        return false
    }

    /// Uygulamanın normal pencere sayısı (küçültülmüşler dahil).
    static func standardWindowCount(_ pid: pid_t) -> Int {
        let app = AXUIElementCreateApplication(pid)
        _ = app
        return max(WindowFinder.windows(pid: pid).count,
                   ((axValue(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [])
                    .filter { axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole as String }.count)
    }

    static func setMinimized(_ win: AXUIElement, _ value: Bool) {
        AXUIElementSetAttributeValue(win, kAXMinimizedAttribute as CFString, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    /// Yerleştir: pencereyi bulunduğu ekranın görünen alanına (menü çubuğu ve Dock hariç) oturtur.
    static func fill(_ win: AXUIElement, pid: pid_t) {
        if axBool(win, kAXMinimizedAttribute) { setMinimized(win, false) }
        guard let primary = NSScreen.screens.first else { return }
        let pos = axPoint(win, kAXPositionAttribute) ?? .zero
        let size = axSize(win, kAXSizeAttribute) ?? .zero
        let center = CGPoint(x: pos.x + size.width / 2, y: primary.frame.height - (pos.y + size.height / 2))
        let vf = (NSScreen.screens.first { $0.frame.contains(center) } ?? primary).visibleFrame
        var newPos = CGPoint(x: vf.minX, y: primary.frame.height - vf.maxY)
        var newSize = vf.size
        if let p = AXValueCreate(.cgPoint, &newPos), let s = AXValueCreate(.cgSize, &newSize) {
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
            AXUIElementSetAttributeValue(win, kAXSizeAttribute as CFString, s)
            AXUIElementSetAttributeValue(win, kAXPositionAttribute as CFString, p)
        }
        focus(win, pid: pid)
    }

    /// macOS'un gerçek tam ekranını açar/kapatır.
    static func toggleFullScreen(_ win: AXUIElement, pid: pid_t) {
        if axBool(win, kAXMinimizedAttribute) { setMinimized(win, false) }
        let isFull = axBool(win, "AXFullScreen")
        AXUIElementSetAttributeValue(win, "AXFullScreen" as CFString, isFull ? kCFBooleanFalse : kCFBooleanTrue)
        focus(win, pid: pid)
    }

    /// Yeni pencere: uygulamayı öne alıp ⌘N gönderir (uygulama destekliyorsa yeni pencere açılır).
    static func newWindow(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if app.isHidden { app.unhide() }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MainActor.assumeIsolated { sendKey(45 /* N */, flags: .maskCommand, to: pid) }
        }
    }
}

/// Önizleme ve değiştiricide ortak kontrol düğmeleri satırı: + – ▣ ⤢ ×
struct WindowControls: View {
    /// Kapat düğmesi uygulamadan çıkabilir mi (yalnızca Dock önizlemesinde, ayar açıksa).
    var closeQuits = false
    let onNew: () -> Void
    let onMinimize: () -> Void
    let onFill: () -> Void
    let onFullScreen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            CtrlButton(symbol: "plus", help: "Yeni pencere", action: onNew)
            CtrlButton(symbol: "minus", help: "Küçült", action: onMinimize)
            if middleMode != "full" {
                CtrlButton(symbol: "rectangle.inset.filled", help: "Ekrana yerleştir", action: onFill)
            }
            if middleMode != "fill" {
                CtrlButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Tam ekran", action: onFullScreen)
            }
            CtrlButton(symbol: "xmark",
                       help: closeQuits ? "Uygulamadan çık" : "Pencereyi kapat",
                       destructive: true, action: onClose)
        }
    }
}

// MARK: - Pencere bulma (AX + ekran listesi)
//
// Bazı uygulamalar (ör. Adobe programları) pencerelerini Erişilebilirlik (AX) sistemine eksik ya da
// standart dışı bildiriyor. Bu yüzden pencereleri macOS'un ekran listesinden (CGWindowList) alıp
// AX bilgisiyle eşleştiriyoruz; eşleşmeyen pencere de listede kalıyor (en azından öne getirilebiliyor).

struct FoundWindow {
    let id: CGWindowID
    let pid: pid_t
    let ax: AXUIElement?
    let title: String
    let minimized: Bool
    let size: CGSize
}

enum WindowFinder {
    /// Uygulamanın AX pencereleri: kimliği bilinenler ve kimliği alınamayanlar.
    static func axWindows(_ pid: pid_t) -> (byID: [CGWindowID: AXUIElement], unmatched: [AXUIElement]) {
        var byID: [CGWindowID: AXUIElement] = [:]
        var unmatched: [AXUIElement] = []
        let app = AXUIElementCreateApplication(pid)
        for w in (axValue(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
            let sub = axString(w, kAXSubroleAttribute) ?? ""
            if sub == "AXSystemDialog" || sub == "AXFloatingWindow" { continue }
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(w, &id) == .success, id != 0 { byID[id] = w } else { unmatched.append(w) }
        }
        return (byID, unmatched)
    }

    /// Konum ve boyutu aynı olan AX penceresini bul (kimlik alınamadığında).
    static func match(_ bounds: CGRect, in list: [AXUIElement]) -> AXUIElement? {
        list.first { w in
            guard let p = axPoint(w, kAXPositionAttribute), let s = axSize(w, kAXSizeAttribute) else { return false }
            return abs(p.x - bounds.minX) < 3 && abs(p.y - bounds.minY) < 3
                && abs(s.width - bounds.width) < 3 && abs(s.height - bounds.height) < 3
        }
    }

    /// Ekrandaki normal pencereler, önden arkaya. pid verilirse yalnızca o uygulama.
    static func onScreen(pid: pid_t? = nil) -> [(id: CGWindowID, pid: pid_t, bounds: CGRect, name: String)] {
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        return info.compactMap { w in
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  let owner = w[kCGWindowOwnerPID as String] as? pid_t, pid == nil || owner == pid,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  ((w[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let bd = w[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: bd as CFDictionary),
                  b.width >= 120, b.height >= 80 else { return nil }
            return (id, owner, b, w[kCGWindowName as String] as? String ?? "")
        }
    }

    /// Bir uygulamanın tüm pencereleri: önce ekrandakiler, sonra küçültülmüşler.
    static func windows(pid: pid_t) -> [FoundWindow] {
        let (byID, unmatched) = axWindows(pid)
        var out: [FoundWindow] = []
        var seen = Set<CGWindowID>()
        for c in onScreen(pid: pid) {
            let ax = byID[c.id] ?? match(c.bounds, in: unmatched)
            seen.insert(c.id)
            out.append(FoundWindow(id: c.id, pid: pid, ax: ax,
                                   title: ax.flatMap { axString($0, kAXTitleAttribute) } ?? c.name,
                                   minimized: false, size: c.bounds.size))
        }
        for (id, ax) in byID where !seen.contains(id) && axBool(ax, kAXMinimizedAttribute) {
            out.append(FoundWindow(id: id, pid: pid, ax: ax, title: axString(ax, kAXTitleAttribute) ?? "",
                                   minimized: true, size: axSize(ax, kAXSizeAttribute) ?? CGSize(width: 16, height: 10)))
        }
        if debugLogging {
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName ?? "?"
            dlog("windows \(name): ax=\(byID.count)+\(unmatched.count) unmatched, onscreen=\(seen.count), result=\(out.count), noAX=\(out.filter { $0.ax == nil }.count)")
        }
        return out
    }
}
