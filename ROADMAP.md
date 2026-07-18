# MixtarRVS: roadmap

## 1. Status

- P0 jest zakończone: minimalny łańcuch kernel, OpenRC, BusyBox i zsh jest powtarzalny.
- P1 jest zakończone: Mixtar startuje z rootem OpenZFS przez UEFI w QEMU i Hyper-V Gen2.
- P2 jest zakończone: pełna dystrybucja konsolowa przeszła dwubootową akceptację w QEMU/OVMF i Hyper-V Generation 2.
- P3 jest zakończone: M1 ma odtwarzalny build, atomowe aktualizacje, rollback, recovery i podpisane artefakty.
- P4 jest aktywne: P4-pre i 1.0 są zakończone, a kanoniczny obraz 1.1 uruchamia w QEMU łańcuch DRM/KMS -> MDDM -> MWM/Wayland -> Avalonia Workbench z działającą myszą i klawiaturą.
- MDDM i MWM wróciły jako jawnie wybrane komponenty P4; AILang, msh i archiwalny RVS pozostają poza bieżącą ścieżką krytyczną.
- Workbench pozostaje prototypem funkcjonalnym: wizualny Terminal nie jest jeszcze prawdziwą sesją zsh, a bramka graficzna Hyper-V nadal jest otwarta.

## 2. Cel wydania M1

MixtarRVS M1 jest autonomicznym systemem opartym na kernelu Linux,
który:

- startuje z obrazu dysku przez UEFI w QEMU i Hyper-V;
- używa OpenZFS jako głównego systemu plików;
- używa OpenRC jako PID 1;
- udostępnia natywny układ `/System` bez publicznego FHS;
- pozwala zalogować się do zsh;
- zachowuje konfigurację, stan i dane użytkownika;
- obsługuje urządzenia, wolumeny, czas, logi, sieć i DNS;
- poprawnie wykonuje reboot i poweroff;
- daje się odtworzyć z jawnych źródeł i konfiguracji;
- posiada manifest integralności, aktualizację i rollback.

## 3. Stałe decyzje architektoniczne

- Kernel: najnowszy stabilny Linux bez `-rc`, który przechodzi bramkę z przypiętym OpenZFS.
- Mixtar nie stosuje polityki LTS. Gdy najnowszy kernel nie przechodzi bramki OpenZFS, pozostaje ostatnia zaliczona para do czasu dostępności poprawki.
- Init: OpenRC 0.63, bez systemd i bez własnego initu.
- Systemowy `sh`: BusyBox ash.
- Shell użytkownika: zsh 5.9.
- Główny system plików: OpenZFS; ESP pozostaje FAT32 zgodnie z UEFI.
- Aktywny EFI Stub: `/System/EFI/BOOT/BOOTX64.EFI`.
- Moduły kernela: `/System/Kernel/Linux/<kernel-release>/Modules`.
- Publiczny root Mixtara: `/System`.
- Procesy: `/System/Processes`.
- Sprzęt i sysfs: `/System/Hardware`.
- Urządzenia: `/System/Devices`.
- Dane runtime: `/System/Runtime`.
- Konfiguracja: `/System/Configuration`.
- Stan trwały: `/System/State`.
- Cache odtwarzalny: `/System/Cache`.
- Logi: `/System/Logs`.
- Dane użytkowników: `/Users`.
- Wolumeny: `/Volumes`.
- Nie tworzymy publicznych aliasów `/proc`, `/sys`, `/dev` ani `/run`.
- Nie budujemy publicznego `/usr`, `/etc`, `/lib` ani `/var`.
- Prywatny initramfs może używać standardowych nazw wymaganych przez kernel i narzędzia startowe; znikają one po `switch_root`.
- Debian, `dpkg`, APT, FreeBSD i RVS nie są bazą ani warstwą zgodności.
- Pliki Mixtara `*.config` używają składni i struktury TOML.
- Konfiguracja tekstowa jest źródłem prawdy, a cache binarny może być tylko odtwarzalnym przyspieszeniem.

## 4. Zakres poza M1

- pulpit i cały stos graficzny;
- MDDM (MixtarRVS Display Driver Model) i MWM (MixtarRVS Window Manager);
- APX i docelowy system pakietów;
- AILang i Verifier jako runtime systemowy;
- msh i Server Track;
- Wayland, X11, audio, powiadomienia i sesja graficzna;
- import zasobów wizualnych z archiwalnego `MixtarRVS.zip`.

Tematy te wracają wyłącznie jako kolejne kamienie milowe P4. Zsh pozostaje
częścią działającego systemu konsolowego M1.

Zakres P4 jest odblokowany, ale nie może przywracać odrzuconej bazy Alpine,
ext4, GRUB, FreeBSD/RVS ani publicznego FHS. Archiwalne projekty mogą dostarczać
wymagania i wzorce interakcji, nie dawną architekturę.

## 5. P0: powtarzalny łańcuch bootowania

**Cel:** każde wejście, artefakt i wynik minimalnego bootu są jawne,
powtarzalne i niezależne od prywatnych ścieżek autora.

- [x] Zbudować kernel, OpenRC, BusyBox i initramfs jednym poleceniem.
- [x] Uruchomić test QEMU w tym samym poleceniu.
- [x] Udowodnić start OpenRC, start zsh i kontrolowany poweroff.
- [x] Udowodnić kontrolowany reboot.
- [x] Nie wpisywać ścieżki repozytorium ani katalogu WSL na stałe.
- [x] Utworzyć `/System/Configuration/Layout.config`.
- [x] Generować manifest źródeł, wersji, patchy i sum SHA-256.
- [x] Walidować brak publicznych odwołań do FHS.
- [x] Powtórzyć build od pustego cache.

**Kryterium wyjścia P0: spełnione.**

Dowód wykonania: [P0.md](P0.md).

## 6. P1: bootowalny obraz z rootem OpenZFS

**Cel:** Mixtar startuje jak system operacyjny z wirtualnego dysku, bez
przekazywania kernela lub initramfs przez hypervisor.

- [x] Zbudować dedykowany pipeline obrazu P1.
- [x] Umieścić Linux EFI Stub jako `\EFI\BOOT\BOOTX64.EFI` na ESP.
- [x] Osadzić minimalny initramfs ZFS bezpośrednio w EFI Stub.
- [x] Usunąć ext4 z docelowego generatora P1.
- [x] Utworzyć partycję GPT typu `bf01` z pulą `mixtar`.
- [x] Utworzyć dataset root `mixtar/ROOT/default` i ustawić `bootfs`.
- [x] Zbudować OpenZFS dla dokładnie tej samej wersji i konfiguracji kernela.
- [x] Traktować kernel, moduły OpenZFS, initramfs i narzędzia ZFS jako jeden zestaw builda.
- [x] Uruchomić import puli i `switch_root` do `/System/Init/MixtarRVS`.
- [x] Zachować tryb ratunkowy BusyBox ash przy błędzie importu.
- [x] Zweryfikować zapis i odczyt, snapshot, rollback, scrub oraz eksport puli.
- [x] Zweryfikować OpenRC, interaktywny zsh, konsolę i kontrolowane wyłączenie w QEMU/OVMF.
- [x] Utworzyć VHDX z tego samego obrazu i uruchomić go w Hyper-V Generation 2.
- [x] Zweryfikować OpenRC, zsh, konsolę i kontrolowane wyłączenie w Hyper-V.
- [x] Zapisać oddzielne raporty provisioningu, QEMU, rescue i Hyper-V.
- [x] Nie dostarczać gościowi kernela ani initramfs poza obrazem podczas testu UEFI.

Zaliczona para P1:

- Linux `7.1.3`, stabilny i bez `-rc`;
- OpenZFS `2.4.2`, przypięty adresem źródła i SHA-256;
- root `mixtar/ROOT/default`, `ashift=12`, `compression=lz4`, `atime=off`, POSIX ACL;
- EFI Stub z prywatnym initramfs i publicznym layoutem bez FHS.

Raporty wykonania:

- [provisioning i testy danych](Output/P1/Qemu-zfs-provision.json);
- [boot QEMU/OVMF](Output/P1/Qemu-p1.json);
- [tryb ratunkowy](Output/P1/Qemu-zfs-rescue.json);
- [Hyper-V Generation 2](Output/P1/HyperV-p1.json);
- [manifest obrazu](Output/P1/MixtarRVS-0.1-x86_64.manifest.json).

**Kryterium wyjścia P1: spełnione.**

## Model wydań Mixtara

- [x] Mixtar jest wydawany jako jeden system operacyjny; Linux, OpenZFS, BusyBox, OpenRC, zsh i pozostałe składniki są wewnętrzną częścią Mixtar Base.
- [x] OpenZFS jest kotwicą zwykłego cyklu wydań: dobór kernela i odświeżenie pozostałych składników następują wokół stabilnego wydania OpenZFS.
- [x] Mixtar M1 oznacza pierwsze kompletne, używalne i stabilne wydanie konsolowe.
- [ ] Mixtar M1.1 oznacza atomową aktualizację całego Mixtar Base prowadzoną przez kolejne zaakceptowane wydanie OpenZFS.
- [x] Konkretne wersje, źródła, sumy SHA i patche znajdują się w `Release/M1.lock.config`; `Layout.config` opisuje układ i możliwości systemu.

## 7. P2: używalna dystrybucja konsolowa

**Cel:** po autonomicznym starcie użytkownik otrzymuje trwały system
konsolowy, a nie tylko techniczny prompt roota.

- [x] Zbudować natywny rootfs bez dystrybucji bazowej.
- [x] Montować root z datasetu OpenZFS.
- [x] Uruchamiać trwały root przez osadzony initramfs i `switch_root`.
- [x] Udostępnić podstawową kontrolę usług przez OpenRC.
- [x] Wykonać reboot i poweroff z testowej sesji zsh.
- [x] Rozdzielić konfigurację, stan, cache, logi i runtime według cyklu życia.
- [x] Utworzyć trwałe `/Users` i pierwsze konto użytkownika.
- [x] Dodać uwierzytelnianie, getty i logowanie do zsh.
- [x] Ustawić prawa oraz właścicieli danych użytkownika.
- [x] Dodać trwałe logi, czas systemowy i nazwę hosta.
- [x] Dodać zarządzanie urządzeniami wymaganymi po starcie.
- [x] Dodać wykrywanie i montowanie wolumenów w `/Volumes`.
- [x] Dodać sieć i DNS bez importowania warstwy innej dystrybucji.
- [x] Zachować konfigurację, stan i dane użytkownika po restarcie.
- [x] Dodać adaptacyjne strojenie OpenZFS zależne od RAM, CPU i rodzaju nośnika.
- [x] Ustawić bezpieczne limity ARC zamiast maksymalizować zużycie pamięci.
- [x] Powtórzyć pełny test konta i konsoli P2 w QEMU/OVMF.
- [x] Powtórzyć pełny test P2 w Hyper-V.

**Kryterium wyjścia P2:** użytkownik uruchamia obraz, loguje się do zsh,
korzysta z trwałego systemu plików i sieci, wykonuje reboot i nie traci danych.

**Stan kryterium: spełnione.** Mixtar zapewnia trwałe konto i zsh/GRML, czas, logi, mdev, wolumeny `/Volumes`, DHCP/DNS oraz adaptacyjne strojenie OpenZFS z ograniczonym ARC. Ten sam obraz przeszedł dwa kolejne uruchomienia w QEMU/OVMF i Hyper-V Generation 2.

### GRML i powłoka użytkownika

- [x] Włączyć grml-zsh-config do Mixtar Base jako domyślną konfigurację interaktywnego zsh.
- [x] Dopasować uruchamianie GRML do natywnego layoutu Mixtara bez wystawiania publicznego FHS.
- [x] Zachować ash jako powłokę techniczną POSIX dla initu i skryptów, a zsh z GRML jako powłokę konta użytkownika.

### Kryteria akceptacji konsoli P2

- [x] Pierwsze konto uprzywilejowane jest początkowo zablokowane i nie ma hasła w obrazie.
- [x] Pierwszy boot wymaga ustawienia hasła przez użytkownika i komunikuje się po angielsku.
- [x] root, Administrator i Superuser prowadzą do jednej tożsamości UID 0 i jednego hasła.
- [x] OpenRC uruchamia getty oraz BusyBox login zamiast bezpośredniej powłoki root.
- [x] Po uwierzytelnieniu uruchamia się loginowy zsh z natywnym profilem GRML; ash pozostaje powłoką initu i skryptów.
- [x] Historia i cache zsh należą do użytkownika i znajdują się w trwałym /Users.
- [x] Test `scripts/test-p2-console.py` przechodzi dwa kolejne bootowania tego samego obrazu: konfigurację konta, oba aliasy, zsh/GRML i trwałą historię.
- [x] Test `scripts/test-p2-hyperv.ps1` przechodzi dwa kolejne bootowania VHDX w Hyper-V Generation 2, łącznie z siecią, DNS, stanem trwałym i kontrolowanym poweroff.

### Wynik pełnej akceptacji P2 z 16 lipca 2026

- Pipeline `scripts/build-p1.ps1 -TestHyperV` obejmuje P0, obraz EFI/ZFS, RAW, VHDX, tryb ratunkowy, dwubootowy test QEMU/OVMF i dwubootowy test Hyper-V.
- QEMU/OVMF zakończyło dwa kolejne uruchomienia znacznikiem `MIXTAR_P2_CONSOLE_OK`.
- Hyper-V Generation 2 zakończyło dwa kolejne uruchomienia znacznikiem `HYPERV_P2_OK` na tym samym VHDX.
- OpenRC uruchomił czas, trwałe logi, mdev, wykrywanie wolumenów, DHCP/DNS i strojenie OpenZFS przed konsolą logowania.
- ESP zostało wykryte i zamontowane tylko do odczytu w `/Volumes`; root pozostał na `mixtar/ROOT/default`.
- DHCP i DNS przeszły w QEMU przez VirtIO oraz w Hyper-V przez pojedynczy adapter `hv_netvsc` podłączony do `Default Switch`.
- ARC zostało ograniczone adaptacyjnie na podstawie RAM i rodzaju nośnika, a zastosowane wartości zapisano w trwałym stanie OpenZFS.
- Historia zsh, ostatni czas kontrolowanego wyłączenia, log zakończenia usług i stan użytkownika przetrwały restart.

Raporty wykonania:

- [pełna akceptacja P2 w QEMU/OVMF](Output/P1/Qemu-p2.json);
- [pełna akceptacja P2 w Hyper-V Generation 2](Output/P1/HyperV-p2.json).

**Kryterium wyjścia P2: spełnione.**
## 8. P3: stabilne wydanie konsolowe

**Cel:** MixtarRVS M1 można odtworzyć, zaktualizować, sprawdzić i
odzyskać po nieudanej zmianie.

- [x] Budować kompletny obraz jednym poleceniem na czystym środowisku.
- [x] Rozdzielić wykrywanie nowych wersji od powtarzalnego buildu przez lock pary kernel/OpenZFS.
- [x] Przypiąć wszystkie źródła, commity, patche i sumy SHA-256 wydania.
- [x] Zapisywać osobne czasy pobierania, patchowania, kompilacji i testów.
- [x] Przechowywać nagłówki, `Module.symvers` i interfejs budowania modułów.
- [x] Oddzielić niezmienny system od trwałego stanu i danych użytkownika.
- [x] Aktualizować kernel, moduły OpenZFS, initramfs i userspace ZFS atomowo.
- [x] Zachowywać poprzednią zaliczoną parę do rollbacku.
- [x] Dodać niezależny tryb odzyskiwania i test uszkodzonej aktualizacji.
- [x] Podpisywać moduły, EFI Stub i manifest przed włączeniem Secure Boot.
- [x] Automatycznie testować boot, logowanie, sieć, zapis, reboot i poweroff.
- [x] Utrzymywać próby akceptacyjne QEMU/OVMF i Hyper-V.
- [x] Weryfikować brak publicznego FHS i zależności od hosta.
- [x] Opisać wymagania hosta, uruchamianie obrazu i procedurę odzyskiwania.

**Kryterium wyjścia P3:** opublikowany zestaw artefaktów ma podpisany manifest,
przechodzi pełną próbę na obu hypervisorach i pozwala wrócić do poprzedniej
wersji po nieudanej aktualizacji.
### Dowody zamknięcia P3

- `scripts/build-m1.ps1` jest jedynym pipeline’em M1 i obsługuje pusty cache.
- `Release/M1.lock.config` przypina źródła, commity, patche i SHA-256.
- `Output/P3/M1.release.json` oraz `M1.release.sig` są końcowym kontraktem wydania.
- `Output/P3/Qemu-p3.json` obejmuje uszkodzoną aktualizację, slot B i rollback do A.
- `Output/P3/Module-SDK.json` sprawdza zewnętrzny moduł i podpis.
- `Output/P3/Release-validation.json` sprawdza FHS, hashe, podpisy i niezmienny root.
- `Output/P1/Qemu-p2.json` i `Output/P1/HyperV-p2.json` potwierdzają dwa booty, trwałość, sieć i kontrolowane wyłączenie.

### Wynik pełnej akceptacji P3 z 16 lipca 2026

- `scripts/build-m1.ps1 -CleanCache -TestHyperV` zakończył się znacznikiem `MIXTAR_M1_PIPELINE_OK`.
- Build użył pustego namespace `m1-clean-89dacb223a7148d8896ffb6a51ea0f39` i trwał `2719,7 s`.
- QEMU/OVMF zaliczyło P2 oraz sekwencję uszkodzony update, M1-B, akceptacja, recovery i M1-A.
- Hyper-V Generation 2 zaliczyło dwa booty tego samego VHDX.
- Zewnętrzny moduł został zbudowany z opublikowanego SDK i podpisany kluczem M1.
- Walidator potwierdził 10 artefaktów, 10/10 podpisanych modułów, trzy podpisane EFI, brak publicznego FHS i brak ścieżek hosta.
- `M1.release.sig` przeszedł niezależną weryfikację OpenSSL.
- Procedury instalacji, aktualizacji i recovery opisuje [P3.md](P3.md).

**Kryterium wyjścia P3: spełnione.**
### Porada eksploatacyjna: czas budowy M1

Pełne `scripts/build-m1.ps1 -CleanCache -TestHyperV` jest certyfikacją wydania,
a nie benchmarkiem pojedynczej kompilacji kernela. Zimny przebieg M1 buduje
cztery produkty z tego samego Linuxa: techniczny kernel P0, EFI dla M1-A, EFI
dla M1-B i EFI recovery. Następnie wykonuje wielobootowe testy QEMU/OVMF oraz
Hyper-V. Wynik `2719,7 s` obejmuje około `1263 s` P0, `942 s` obrazu i `501 s`
akceptacji.

Codzienny build powinien korzystać z cache i uruchamiać tylko potrzebne bramki.
Pełny zimny przebieg pozostaje obowiązkowy dla kandydata wydania. Następna
optymalizacja buildera powinna zachować jeden wspólny katalog Kbuild, budować
kod kernela raz, a M1-A, M1-B i recovery tworzyć przez przyrostowe osadzenie
initramfs oraz końcowy relink. A i B powinny również współdzielić przygotowaną
bazę initramfs. Optymalizacja nie może osłabić kontroli SHA-256, izolacji slotów
ani pełnej bramki `-CleanCache -TestHyperV`.
## 9. P4: warstwa produktu Mixtar 1.0+

**Cel:** na stabilnym Mixtar Base z P3 zbudować pełne środowisko produktu:
APX/Executor, pulpit, graficzny namespace, izolowane środowiska zgodności,
politykę bezpieczeństwa oraz narzędzia aktualizacji i odzyskiwania.

Normatywny kontrakt produktu: `P4.md`.

### Źródła archiwalne i ich interpretacja

Archiwum `MixtarRVS.zip` zawiera dwa różne ciągi historyczne:

- `pre-v0` oraz techniczne generacje `0001–0005` starego instalatora;
- linię produktu `1.0–1.9` opisaną w `1.0 & future.md`.

Archiwum nie definiuje osobnej, nazwanej sekwencji wydań `0.1–1.0`. Nie należy
jej dopisywać z pamięci jako faktu. Udokumentowane generacje `0001–0005`
oznaczały kolejno layout, bootstrap Alpine, test chroot/proot, artefakt
instalacyjny i test bootu. Ich rezultat został zastąpiony przez obecne P0–P3:
natywny root Mixtara, OpenZFS, EFI Stub, OpenRC oraz akceptację QEMU/Hyper-V.

P4 zachowuje wymagania produktowe archiwum, ale nie jego dawną implementację:
bez Alpine jako bazy, `apk` jako tożsamości, ext4, GRUB, kernela `-rc`, RVS ani
publicznych aliasów FHS.

### Bramka wejścia do P4

- [x] Zaliczyć pełne kryterium P3 i zbudować stabilny zestaw artefaktów Mixtar M1.
- [x] Przenieść wymagania produktowe z archiwum do aktualnych specyfikacji bez kopiowania starej architektury. Źródło normatywne: `P4.md`.
- [x] Zdefiniować stabilne kontrakty APX, Executor, sesji, uprawnień i namespace przed implementacją pulpitu. Kontrakty: `P4.md`.
- [x] Ustalić mierzalne budżety startu, RAM, CPU i I/O dla całej warstwy produktu. Limity: `Root/System/Configuration/Product/P4.config`.
- [x] Zachować działającą dystrybucję konsolową jako tryb niezależny od P4. Bramka: `scripts/validate-console-independence.py`.

### Decyzja o stosie graficznym P4

- [x] Wybrać Avalonię jako jedyny framework interfejsu produktu. RmlUi i Qt/QML pozostają wyłącznie prototypami porównawczymi.
- [x] Przyjąć Avalonię 12.1 jako linię startową. Konkretne wydanie poprawkowe należy do blokady wydania Mixtara, a nie do kontraktu architektury.
- [x] Przyjąć stabilną linię .NET 10 z Native AOT. Wydania preview .NET nie wchodzą do Mixtar Base.
- [x] Użyć natywnego backendu `Avalonia.Wayland`; X11 i Xwayland pozostają prywatną warstwą zgodności dla obcych aplikacji.
- [x] Pozostawić MWM osobnym kompozytorem Wayland i właścicielem powierzchni, fokusu, położenia oraz dekoracji okien. Avalonia jest klientem UI, nie kompozytorem.
- [x] Ustalić granice grafiki: natywny MDDM jako model sterowników obrazu, MWM jako kompozytor Wayland, a Login UI, pulpit i aplikacje jako klienci Avalonia oraz `.APX`.
- [x] Publikować systemowe aplikacje jako samodzielne obrazy Native AOT, bez JIT i bez wymagania współdzielonej instalacji runtime .NET.
- [x] Zbudować Avalonię, .NET Native AOT, Wayland, EGL/GBM, fontconfig, FreeType i HarfBuzz z prefiksem `/System` oraz kontrolowanymi zależnościami ELF.
- [x] Zbudować minimalny MWM 0.1 nad wlroots 0.20.2 jako własną politykę okien Mixtara, bez X11 i Xwayland.
- [x] Uruchomić bramkę zagnieżdżoną MDDM/Wayland -> MWM/pixman+shm -> Workbench/Avalonia pod `strace` i `perf`.
- [x] Dostarczyć w overlayu P4 fizyczne, kanoniczne ABI `/System/Libraries` i loader `/System/Libraries/Loader`, bez symlinków i hardlinków.
- [x] Wyprofilować i obniżyć zużycie CPU Workbencha: jawny framebuffer Waylanda (`MIXTAR_GRAPHICS_MODE=software`) zużywa 0,029 rdzenia, 1,97 IPC i 1,89% branch-miss w ośmiosekundowym teście WSL, zamiast bazowych 0,968 rdzenia, 2,15 IPC i 1,68% branch-miss; to spadek użycia CPU o około 97%, a tryb `auto` zachowuje ścieżkę EGL/GPU dla obrazu Mixtara.
- [x] Uruchomić kanoniczny cold boot ścieżki Linux GPU/DRM/KMS -> MDDM -> MWM/Wayland -> Avalonia Workbench w QEMU. Dowód tury 7: mysz i fokus okien w `Output/P4/InputProof3-*.png`, klawiatura i akcja UI w `Output/P4/InputProof5-*.png`.
- [ ] Uruchomić i zmierzyć tę samą ścieżkę graficzną w Hyper-V.
- [ ] Zastąpić symulowany wizualny Terminal prawdziwą sesją zsh/APX; obecna bramka potwierdza transport wejścia i akcje UI, nie wykonanie komend w oknie.
- [ ] Przed wydaniem produktu zamknąć eksperymentalność backendu Wayland testami zgodności Mixtara albo przypiąć zaakceptowaną wersję upstream do czasu jego stabilizacji.

### Linia wydań P4

- [x] **P4-pre — Product contracts:** kontrakt `P4.md`, maszynowe budżety, bramka konsoli oraz prototyp `mixtar_builder.apx` definiują APX, Executor, sesję, namespace i UI bez uznawania prototypu za publiczne API.
- [x] **1.0 — Core Identity:** APX, Executor, `zsh.apx`, init/runtime i podstawowy boot produktu na czystym publicznym root Mixtara. Dowód: [Core.release.json](Output/P4/Core.release.json).
- [ ] **1.1 — Mixtar Workbench:** okna, pasek zadań, Start, `Ctrl+K` i pełny lifecycle aplikacji. Bramka platformowa QEMU (rendering, fokus, mysz i klawiatura) jest zaliczona; prawdziwy Terminal i pełny lifecycle pozostają otwarte.
- [ ] **1.2 — Namespace:** aplikacja Files oraz graficzna obsługa `/Applications`, `/System`, `/Users`, `/Volumes` i `/Temporary`.
- [ ] **1.3 — Connected System:** SSH, Network Inspector, traceroute i monitoring runtime nad siecią dostarczoną już przez P2.
- [ ] **1.4 — Visual and Interaction Freeze:** zamrożony język wizualny, dostępność, DPI, pełna klawiatura, finalne zachowanie okien i stabilne Mixtar UI API.
- [ ] **1.5 — Optional Compatibility Providers:** opcjonalny Windows Guest Provider i inne izolowane środowiska zgodności.
- [ ] **1.6 — POSIX Islands:** prywatne profile Linux, OpenBSD i FreeBSD bez publikowania FHS w hoście Mixtara.
- [ ] **1.7 — Policy and Audit:** zarządzanie capabilities, historia uprawnień, inspekcja APX i kompletne narzędzia polityki; separacja procesów obowiązuje już od 1.0.
- [ ] **1.8 — Recovery and Updates:** interfejs użytkownika i diagnostyka dla atomowych aktualizacji, rollbacku i recovery dostarczonych technicznie w P3.
- [ ] **1.9 — Stabilization:** kompatybilność API, migracje konfiguracji, testy długotrwałe i przygotowanie kontraktu Storage 2.0.
- [ ] **Granica 2.0:** zaprojektować Mixtar Storage Authority z dostawcami OpenZFS, Temporary i Remote; nie tworzyć forka OpenZFS pod nazwą MixtarFS.

Wygląd zostaje zamrożony w 1.4. Wydania 1.5–1.9 rozwijają możliwości bez
ponownego projektowania całego pulpitu.

**Kryterium wyjścia P4:** Mixtar działa jako kompletne środowisko produktu nad
Mixtar Base, zachowuje niezależny tryb konsolowy, uruchamia APX przez
kontrolowany Executor, izoluje obce środowiska i przechodzi testy pulpitu,
sieci, polityki, aktualizacji oraz odzyskiwania bez publicznego FHS.

## 10. Zgodność FHS i zaplecze P4

Publiczny układ Mixtara pozostaje natywny. Obcy program wymagający FHS otrzyma
prywatną przestrzeń montowań utworzoną tylko dla jego procesu. Nie powstaną
publiczne aliasy ani linki do `/usr`, `/etc`, `/lib`, `/var`, `/run`, `/dev`,
`/proc` lub `/sys`.

- [ ] Zbudować prototyp prywatnej przestrzeni zgodności FHS.
- [ ] Obsłużyć obce interpretery ELF bez publikowania `/lib64`.
- [ ] Mapować prywatny runtime programu na natywny `/System/Runtime`.
- [ ] Przygotować adapter instalacji zewnętrznych sterowników.
- [ ] Zbudować Wayland z prefiksem `/System` i uruchamiać Xwayland prywatnie.
- [ ] Zaimplementować MDDM jako model sterowników obrazu, MWM jako compositor/window manager, a następnie osobny Login UI, APX i pozostałe elementy pulpitu.

## 11. Najbliższa kolejność prac

1. Zamrozić publiczne kontrakty Mixtar Base M1 jako podstawę dalszych prac.
2. Rozpocząć P4-pre od kontraktów APX, Executor, sesji, capabilities i namespace.
3. Ustalić mierzalne budżety startu, RAM, CPU i I/O dla warstwy produktu.
4. Zachować konsolowe M1 jako niezależny tryb i stałą bramkę regresji.
5. Dopiero po zamknięciu kontraktów rozpocząć warstwę 1.0 jedną ścieżką: MWM/Wayland + Avalonia Native AOT; RmlUi i Qt/QML pozostają prototypami, nie równoległymi stosami produktu.
## 12. Zasada ograniczania zakresu

M1 jest zamkniętą bazą regresji. Nowy komponent może wejść do P4 tylko wtedy,
gdy odblokowuje konkretny kamień milowy linii P4-pre lub 1.0–1.9. Nie należy
tworzyć równoległych implementacji pulpitu, APX ani środowisk zgodności przed
zamrożeniem ich kontraktów.
