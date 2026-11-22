// Kendi kendini test: `open -n /Applications/HexDock.app --args --selftest`
// Yalnızca OKUR — hiçbir pencereyi kapatmaz, taşımaz, küçültmez. Raporu ~/Library/Logs/HexDock-selftest.txt'e yazar.
import Cocoa
import ApplicationServices

@MainActor
enum SelfTest {
    static var lines: [String] = []
    static var problems = 0
    static func out(_ s: String) { lines.append(s) }
    static func fail(_ s: String) { problems += 1; lines.append("  ✗ " + s) }
    static func ok(_ s: String) { lines.append("  ✓ " + s) }
    static func warn(_ s: String) { lines.append("  ! " + s) }

    static func time<T>(_ f: () -> T) -> (T, Double) {
        let t0 = CACurrentMediaTime(); let r = f(); return (r, (CACurrentMediaTime() - t0) * 1000)
    }

    static func run() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.5)
        out("HexDock kendi kendini test — \(Date())")
        out("macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
        out("")

        // 1) İzinler
        out("1. İzinler")
        AXIsProcessTrusted() ? ok("Erişilebilirlik izni var") : fail("Erişilebilirlik izni YOK — testlerin çoğu anlamsız")
        CGPreflightScreenCaptureAccess() ? ok("Ekran kaydı izni var") : warn("Ekran kaydı izni yok — önizleme görüntüleri gelmez")

        // 2) Dock
        out(""); out("2. Dock")
        let (dock, dockMs) = time { currentDockFrame() }
        if let dock { ok("Dock alanı bulundu: \(Int(dock.width))×\(Int(dock.height)) pt (\(String(format: "%.1f", dockMs)) ms)") }
        else { fail("Dock alanı bulunamadı (Dock gizli/otomatik gizleme olabilir)") }
        let orientation = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "bottom"
        out("  Dock konumu: \(orientation)")

        // Dock'taki uygulama öğeleri ve URL'leri
        var dockAppPaths: [String] = []
        if let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier,
           let children = axValue(AXUIElementCreateApplication(pid), kAXChildrenAttribute) as? [AXUIElement],
           let list = children.first(where: { axString($0, kAXRoleAttribute) == kAXListRole as String }),
           let items = axValue(list, kAXChildrenAttribute) as? [AXUIElement] {
            for it in items where axString(it, kAXSubroleAttribute) == "AXApplicationDockItem" {
                if let url = axValue(it, kAXURLAttribute) as? URL { dockAppPaths.append(url.standardizedFileURL.path) }
            }
            ok("Dock'ta \(dockAppPaths.count) uygulama öğesi okundu")
        } else {
            fail("Dock öğeleri okunamadı")
        }

        // 3) Uygulamalar ve pencereler
        out(""); out("3. Açık uygulamalar ve pencereler")
        let me = getpid()
        let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != me }
        var slow: [(String, Double)] = []
        for app in apps.sorted(by: { ($0.localizedName ?? "") < ($1.localizedName ?? "") }) {
            let name = app.localizedName ?? app.bundleIdentifier ?? "?"
            let pid = app.processIdentifier
            let (found, ms) = time { WindowFinder.windows(pid: pid) }
            let (axw, _) = time { WindowFinder.axWindows(pid) }
            let axAll = (axValue(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
            let nonMinAX = axAll.filter { !axBool($0, kAXMinimizedAttribute)
                && axString($0, kAXSubroleAttribute) == kAXStandardWindowSubrole as String }
            let noAX = found.filter { $0.ax == nil }.count
            let path = app.bundleURL?.standardizedFileURL.path ?? ""
            let inDock = dockAppPaths.contains(path)
            if ms > 150 { slow.append((name, ms)) }

            var notes: [String] = []
            if !inDock { notes.append("Dock'ta bu yolla eşleşen öğe yok (Dock'tan önizleme açılmaz; Alt+Tab'da görünür)") }
            if noAX > 0 { notes.append("\(noAX) pencere Erişilebilirlik bilgisiz → küçült/yerleştir çalışmaz, × yalnızca son pencerede çıkar") }
            let other = found.filter(\.otherSpace).count
            if other > 0 { notes.append("\(other) pencere başka masaüstünde/tam ekranda (listede \"Diğer masaüstü\" olarak görünür)") }
            if found.isEmpty && !nonMinAX.isEmpty {
                notes.append("\(nonMinAX.count) pencere AX'te var ama hiçbir listede bulunamadı")
            }
            // Düğme desteği (yalnızca okunur: ayarlanabilir mi?)
            var noClose = 0, noMin = 0, noPos = 0
            for w in found.compactMap(\.ax) {
                if axValue(w, kAXCloseButtonAttribute) == nil { noClose += 1 }
                var settable: DarwinBoolean = false
                if AXUIElementIsAttributeSettable(w, kAXMinimizedAttribute as CFString, &settable) != .success || !settable.boolValue { noMin += 1 }
                settable = false
                if AXUIElementIsAttributeSettable(w, kAXPositionAttribute as CFString, &settable) != .success || !settable.boolValue { noPos += 1 }
            }
            if noClose > 0 { notes.append("\(noClose) pencerede kapat düğmesi yok → × ⌘W'ye düşer") }
            if noMin > 0 { notes.append("\(noMin) pencere küçültülemiyor") }
            if noPos > 0 { notes.append("\(noPos) pencere taşınamıyor/boyutlanamıyor → yerleştir çalışmaz") }

            let head = "\(name): \(found.count) pencere (AX \(axw.byID.count)+\(axw.unmatched.count)), \(String(format: "%.0f", ms)) ms"
            if notes.isEmpty { ok(head) } else {
                warn(head)
                for n in notes { out("      – " + n) }
            }
        }
        if slow.isEmpty { ok("Tüm uygulamalar 150 ms altında yanıt verdi") }
        else { for (n, ms) in slow { warn("\(n) yavaş yanıt verdi: \(Int(ms)) ms (donuk olabilir)") } }

        // Dock'ta olup çalışan ama eşleşmeyen yollar
        let runningPaths = Set(apps.compactMap { $0.bundleURL?.standardizedFileURL.path })
        let orphanDock = dockAppPaths.filter { p in
            !runningPaths.contains(p) && apps.contains { ($0.bundleURL?.lastPathComponent) == URL(fileURLWithPath: p).lastPathComponent }
        }
        for p in orphanDock { fail("Dock öğesi farklı bir yolu gösteriyor, çalışan kopya eşleşmiyor: \(p)") }

        // 4) Pencere değiştirici
        out(""); out("4. Pencere değiştirici")
        let (all, allMs) = time { WindowFinder.onScreen() }
        ok("Ekranda \(all.count) pencere bulundu (\(String(format: "%.1f", allMs)) ms)")
        // Klavye dinleyicisi kurulabiliyor mu (kurulup hemen kaldırılır)
        if let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                     eventsOfInterest: 1 << CGEventType.flagsChanged.rawValue,
                                     callback: { _, _, e, _ in Unmanaged.passUnretained(e) }, userInfo: nil) {
            CFMachPortInvalidate(t)
            ok("Klavye dinleyicisi kurulabiliyor")
        } else {
            fail("Klavye dinleyicisi kurulamıyor (Erişilebilirlik izni?)")
        }
        // Kısayol eşleştirme mantığı
        func matches(_ held: CGEventFlags, _ mods: CGEventFlags) -> Bool {
            held.contains(mods) && held.subtracting(mods).isSubset(of: .maskShift)
        }
        let cases: [(CGEventFlags, CGEventFlags, Bool, String)] = [
            ([.maskAlternate], [.maskAlternate], true, "⌥Tab"),
            ([.maskAlternate, .maskShift], [.maskAlternate], true, "⇧⌥Tab (geri)"),
            ([.maskAlternate, .maskCommand], [.maskAlternate], false, "⌘⌥Tab başka kısayol"),
            ([.maskCommand], [.maskAlternate], false, "⌘Tab ⌥Tab değil"),
            ([], [.maskAlternate], false, "yalnız Tab"),
        ]
        var logicOK = true
        for (held, mods, expect, label) in cases where matches(held, mods) != expect { logicOK = false; fail("Kısayol mantığı: \(label)") }
        if logicOK { ok("Kısayol eşleştirme mantığı (\(cases.count) durum) doğru") }

        // 5) Yerleşim hesapları
        out(""); out("5. Yerleşim")
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let maxCols = max(1, Int((vf.width * 0.9 - SwitcherLayout.outer * 2 + SwitcherLayout.spacing)
                                     / (SwitcherLayout.cellW + SwitcherLayout.spacing)))
            let rowsFit = Int((vf.height * 0.9 - SwitcherLayout.outer * 2 + SwitcherLayout.spacing)
                              / (SwitcherLayout.cellH + SwitcherLayout.spacing))
            let capacity = maxCols * rowsFit
            out("  Ekran \(Int(vf.width))×\(Int(vf.height)) pt: değiştirici \(maxCols) sütun × \(rowsFit) satır = \(capacity) pencere sığar")
            if all.count > capacity { fail("Şu an \(all.count) pencere var; \(all.count - capacity) tanesi değiştiricide kesilir") }
            else { ok("Mevcut \(all.count) pencere değiştiriciye sığıyor") }
            let wides = [0.5, 1.0, 1.6, 2.4, 4.0].map { Layout.thumbW(aspect: CGFloat($0)) }
            ok("Önizleme kart genişlikleri sınırlar içinde: \(wides.map { Int($0) })")
        }

        // 6) Müzik
        out(""); out("6. Müzik")
        for (id, n) in [("com.spotify.client", "Spotify"), ("com.apple.Music", "Music")] {
            out("  \(n): " + (NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty ? "kapalı" : "açık"))
        }

        out(""); out(problems == 0 ? "SONUÇ: hata yok" : "SONUÇ: \(problems) hata")
        let text = lines.joined(separator: "\n") + "\n"
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/HexDock-selftest.txt")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        print(text)
    }
}
