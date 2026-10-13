# Translator

**Gizlilik odaklı, cihaz üzerinde çalışan macOS çeviri aracı — DeepL'in "seç ve çevir" deneyimi, ama metniniz Mac'inizden hiç çıkmadan.**

Herhangi bir uygulamada metni seçin, **⌃⌥T**'ye basın; menü çubuğu simgesinin altında çeviri açılır.
Çeviri Apple'ın [Translation](https://developer.apple.com/documentation/translation) framework'üyle
(isteğe bağlı olarak Apple Intelligence ile) tamamen yerel yapılır. Dil paketleri bir kez indirildikten sonra internet gerekmez.

*On-device macOS translator: select text anywhere, press a hotkey, get a translation from Apple's built-in
Translation framework or Apple Intelligence. Nothing is sent to any server.*

## Özellikler

- 🔒 **Tamamen cihaz üzerinde** — Apple Translation veya Apple Intelligence (Foundation Models)
- ⌨️ **Sistem geneli kısayol** (varsayılan ⌃⌥T, değiştirilebilir, açılıp kapatılabilir) ve isteğe bağlı **⌘C ⌘C**
- 🌐 **Otomatik dil algılama** — metin ana dilinizde değilse ona, zaten ana dilinizdeyse ikinci dile çevirir
- 📋 **Kopyala** (⌘↩) ve **Değiştir** (⇧⌘↩): seçili metni doğrudan çeviriyle değiştirir
- 🪶 Menü çubuğu popover'ı — Dock simgesi ya da ayrı pencere yok; başka yere tıklayınca kapanır
- 📌 Sabitleme, girişte başlatma, pano içeriğini koruyan seçim okuma

## Gereksinimler

- macOS 15 Sequoia veya üzeri
- Xcode veya Command Line Tools (derlemek için)
- Apple Intelligence motoru için: macOS 26+, Apple Silicon, Apple Intelligence açık

## Kurulum (kendi Mac'inde)

```bash
git clone https://github.com/cryptooth/macTranslator.git
cd Translator
./build.sh install      # derler, /Applications'a kopyalar ve başlatır
```

İlk açılışta **Erişilebilirlik** izni gerekir:
Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik → *Translator* açık.
Popover'daki **İzin ver…** düğmesi bu sayfayı doğrudan açar.

> `build.sh`, Keychain'de *Apple Development* sertifikası varsa onunla, yoksa ad-hoc imzalar.
> Ad-hoc imzada her yeniden derlemeden sonra izni sıfırlamak gerekir:
> `tccutil reset Accessibility com.kayhanbelek.translator`

## Kullanım

| Kısayol | İşlev |
|---|---|
| **⌃⌥T** | Seçili metni çevir |
| **⌘C ⌘C** | İki kez kopyala ile çevir (Ayarlar'dan açılır) |
| **⌘↩** | Çeviriyi kopyala |
| **⇧⌘↩** | Kaynak uygulamadaki seçili metni çeviriyle değiştir |
| **Esc** | Kapat |

- Simgeye **sol tık**: çeviri kutusu · **sağ tık**: kısayolu aç/kapat, Ayarlar, Çıkış
- Bir dil çifti ilk kez kullanıldığında macOS dil paketini indirmek için onay ister.
  Paketler: Sistem Ayarları → Genel → Dil ve Bölge → Çeviri Dilleri

## Dağıtım (başkalarına göndermek)

Başkasının Mac'inde uyarısız açılması için uygulamanın **Developer ID** ile imzalanıp Apple'a **notarize** ettirilmesi gerekir:

```bash
# bir kerelik
xcrun notarytool store-credentials "translator-notary" \
  --apple-id "APPLE_ID" --team-id "TEAM_ID" --password "uygulamaya-özel-parola"

./release.sh            # → dist/Translator.zip
```

Ayrıntılar `release.sh` dosyasının başında. Developer ID olmadan gönderilen bir kopya,
alıcı tarafında Sistem Ayarları → Gizlilik ve Güvenlik → **Yine de Aç** ile açılabilir.

## Proje yapısı

```
Sources/
  Main.swift                    giriş noktası (menü çubuğu uygulaması)
  AppDelegate.swift             kısayol, ⌘C⌘C izleme, gizli Düzen menüsü
  PanelController.swift         menü çubuğu simgesi + popover
  TranslatorView.swift          SwiftUI çeviri arayüzü (.translationTask)
  TranslatorModel.swift         dil algılama ve çeviri akışı
  SettingsView.swift            ayarlar + kısayol kaydedici
  HotKeyManager.swift           sistem geneli kısayol (Carbon)
  SelectionGrabber.swift        seçili metni alma (AX API → ⌘C yedeği, panoyu geri yükler)
  Languages.swift               dil listesi / algılama
  IntelligenceTranslator.swift  Apple Intelligence motoru
Info.plist
build.sh                        yerel derleme / kurulum
release.sh                      Developer ID imza + notarization
```

Xcode projesi gerekmez; `swiftc` ile doğrudan derlenir.

## Lisans

[MIT](LICENSE)
