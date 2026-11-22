# HexDock

A macOS menu bar app that shows **live window previews** when you hover over Dock icons.

![HexDock](docs/screenshot.png)

## Features
- Live window thumbnails above Dock icons; click to switch to a window
- Shows minimized windows too; close, minimize, fill or full-screen right from the preview
- **Window switcher** opened with a shortcut (custom shortcut supported)
- **Now playing** card with playback controls for Spotify and Music
- Appearance options such as distance from the Dock and zoom button

## Build & install
Requirements: macOS 14+, Xcode Command Line Tools.

```bash
./build.sh   # build and install as /Applications/HexDock.app
```
Needs **Accessibility** and **Screen Recording** permissions (menu bar icon → Permissions).

---

## Türkçe

Dock ikonlarının üzerine gelince o uygulamanın **canlı pencere önizlemelerini** gösteren macOS menü çubuğu uygulaması.

**Özellikler**
- Dock ikonu üzerinde canlı pencere küçük resimleri; tıklayarak pencereye geçiş
- Küçültülmüş pencereleri de gösterir; önizlemeden kapatma, küçültme, doldurma, tam ekran
- Kısayolla açılan **pencere değiştirici** (özel kısayol atanabilir)
- Spotify ve Müzik için **şu an çalan** kartı ve oynatma kontrolleri
- Dock'a mesafe, büyütme düğmesi gibi görünüm ayarları

**Kurulum:** macOS 14+ ve Xcode Command Line Tools gerekir. `./build.sh` derler ve `/Applications/HexDock.app` olarak kurar. **Erişilebilirlik** ve **Ekran Kaydı** izinleri gerekir (menü çubuğu simgesi → İzinler).
