# HexDock

A macOS menu bar app that shows **live window previews** when you hover over Dock icons.

![HexDock](docs/screenshot.png)

## How to install & open
Requires macOS 26+ on an Apple Silicon Mac (M1 or later).

1. **[⬇ Download HexDock.dmg](https://github.com/Huseyinkayaw/HexDock/raw/main/release/HexDock.dmg)**
2. Open the DMG and drag **HexDock** into the **Applications** folder.
3. Open HexDock. Because the app is free and not notarized by Apple, macOS shows *"HexDock" Not Opened — Apple could not verify…*. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down to *"HexDock" was blocked…* and click **Open Anyway**, then enter your Mac password. You only need to do this once.
5. When asked, allow **Accessibility** and **Screen Recording** in System Settings → Privacy & Security.

Prefer Terminal? Steps 3–4 can be replaced with:

```bash
xattr -dr com.apple.quarantine /Applications/HexDock.app
```

SHA-256 of the DMG: `5d7ca26fc6df5796109251d181982db6c154f2eca5343fe5a4b8876cce10b71e`

## Features
- Live window thumbnails above Dock icons; click to switch to a window
- Shows minimized windows too; close, minimize, fill or full-screen right from the preview
- **Window switcher** opened with a shortcut (custom shortcut supported)
- **Now playing** card with playback controls for Spotify and Music
- Appearance options such as distance from the Dock and zoom button

**Window switcher:**

![HexDock window switcher](docs/switcher.png)

## Privacy & security
- The only network request: when Spotify is playing, the album cover is fetched over HTTPS from Spotify's own image servers (no cookies, no disk cache). No other address is ever contacted. Apple Music covers are read locally.
- The keyboard listener only reacts to the window switcher shortcut; keystrokes are never recorded or stored.
- Debug logging is off by default.

## Build from source
Requirements: macOS 26+, Xcode Command Line Tools.

```bash
./build.sh   # build and install as /Applications/HexDock.app
```
Needs **Accessibility** and **Screen Recording** permissions (menu bar icon → Permissions).

---

## Türkçe

Dock ikonlarının üzerine gelince o uygulamanın **canlı pencere önizlemelerini** gösteren macOS menü çubuğu uygulaması.

**Kurulum ve ilk açılış** (macOS 26+, Apple Silicon / M1 ve üstü)

1. **[⬇ HexDock.dmg dosyasını indirin](https://github.com/Huseyinkayaw/HexDock/raw/main/release/HexDock.dmg)**
2. DMG'yi açın ve **HexDock**'i **Uygulamalar** klasörüne sürükleyin.
3. HexDock'i açın. Uygulama ücretsiz olduğu ve Apple tarafından onaylanmadığı için macOS *"HexDock" Açılmadı — Apple … doğrulayamadı* uyarısı gösterir. **Bitti**'ye basın.
4. **Sistem Ayarları → Gizlilik ve Güvenlik**'i açın, aşağı inip *"HexDock" engellendi* satırındaki **Yine de Aç**'a tıklayın ve Mac şifrenizi girin. Bu yalnızca bir kez yapılır.
5. İstendiğinde Sistem Ayarları → Gizlilik ve Güvenlik'ten **Erişilebilirlik** ve **Ekran Kaydı** izni verin.

Terminal kullanıyorsanız 3–4. adımların yerine: `xattr -dr com.apple.quarantine /Applications/HexDock.app`

DMG SHA-256: `5d7ca26fc6df5796109251d181982db6c154f2eca5343fe5a4b8876cce10b71e`

**Özellikler**
- Dock ikonu üzerinde canlı pencere küçük resimleri; tıklayarak pencereye geçiş
- Küçültülmüş pencereleri de gösterir; önizlemeden kapatma, küçültme, doldurma, tam ekran
- Kısayolla açılan **pencere değiştirici** (özel kısayol atanabilir) — görüntüsü yukarıda
- Spotify ve Müzik için **şu an çalan** kartı ve oynatma kontrolleri
- Dock'a mesafe, büyütme düğmesi gibi görünüm ayarları

**Gizlilik ve güvenlik**
- Tek ağ isteği: Spotify çalarken albüm kapağı HTTPS ile yalnızca Spotify'ın kendi görsel sunucularından alınır (çerez ve disk önbelleği yok). Başka hiçbir adrese bağlanmaz. Apple Music kapakları yerelden okunur.
- Klavye dinleyici yalnızca pencere değiştirici kısayoluna tepki verir; tuş vuruşları kaydedilmez.
- Ayrıntılı kayıt (log) varsayılan olarak kapalıdır.

**Kaynaktan derleme:** macOS 26+ ve Xcode Command Line Tools gerekir. `./build.sh` derler ve `/Applications/HexDock.app` olarak kurar. **Erişilebilirlik** ve **Ekran Kaydı** izinleri gerekir (menü çubuğu simgesi → İzinler).
