# Mixtar HIG v0.1 — reguły interfejsu Workbencha

Zasada nadrzędna: UI podąża za tymi regułami, nie za gustem autora zmiany.
Każdy nowy element ma wskazać token/metrykę z tej listy albo zaproponować
zmianę TUTAJ (commit w tym pliku), nigdy wartość ad-hoc w kodzie.

## Siatka i odstępy
- Bazowa jednostka: **4 px**. Wszystkie marginesy/paddingi to wielokrotności 4.
- Odstęp między kontrolkami w rzędzie: 8. Między sekcjami: 12 lub 16.
- Zawartość okna od krawędzi: 12.

## Typografia (przy skali 100%)
- Body: **13 px** (Noto Sans). Body-mono: 12 px (Noto Sans Mono).
- Secondary/caption: 11 px. Minimum absolutne: **10 px** — nic mniejszego.
- Tytuł okna: 12 px mono, bold, tracking 0.6.
- Tekst zawsze wycentrowany w pionie względem swojej kontrolki.

## Kontrolki
- Wysokość standardowa: **32 px** (przyciski, pola tekstowe, wiersze list).
- Kompaktowa (toolbar): 28 px. Nic poniżej 24 px.
- Minimalny obszar kliknięcia: **24x24 px** niezależnie od wizualnego rozmiaru.
- Promień narożników: 4 (kontrolki), 8 (okna/karty), pełny (kropki okna).

## Okna (wzorzec: Windows, nie macOS)
- Pasek tytułu: wysokość 34. Przyciski sterujące PROSTOKĄTNE, przy prawej
  krawędzi, w kolejności — □ ✕; obszar 34x26, glif wycentrowany; hover
  rozjaśnia, hover zamknięcia = czerwień (#C42B1C).
- BRAK globalnego górnego paska menu. Zegar/status żyją w pasku zadań.
- KAŻDE okno (w tym menu Start) ma zmienialny rozmiar: uchwyty na
  krawędziach/rogach, min. rozmiar zdefiniowany per okno. [do implementacji]
- Aktywne okno: mocniejsza ramka + cień; nieaktywne przygaszone. Nigdy dwa
  okna „aktywne" naraz.

## Interakcje
- Klik poza menu/popup/edycją ZAMYKA je (light dismiss) — wszędzie, bez wyjątków.
- Escape zamyka najbardziej wewnętrzną warstwę (popup → menu → edycja).
- Dwuklik otwiera; pojedynczy zaznacza. Enter = otwórz, Backspace = w górę.
- Operacje niszczące: dwustopniowe (Delete → Confirm?) albo dialog.
- Każde pole edycji przywraca poprzedni widok po utracie kontekstu.

## Kolor (tokeny — wartości w MainWindow.axaml Resources)
- Panel, PanelSoft, Stroke, StrokeStrong, Accent, Text, Soft, Muted, Mono.
- Tekst na panelu musi mieć kontrast ≥ 4.5:1 (WCAG AA). Czerwony tylko dla
  destrukcji/błędów, żółty dla ostrzeżeń, zielony dla potwierdzeń.
- Kierunek estetyczny: nowoczesny, ciemny, z LEKKIM akcentem "Uplink";
  nie retro, nie neonowy przesyt. Docelowa tożsamość: duch Windows
  (czytelność, spokój) w mixtarowej kolorystyce.

## Dane
- Zero atrap: każda liczba/nazwa na ekranie pochodzi z systemu albo elementu
  nie ma. Elementy "preview" są jawnie oznaczone banerem.

## Backlog funkcjonalny Workbencha
Źródło: pierwszy koncept pulpitu (FreeBSD-Mixtar-Theme/desktop-env/client,
~95 funkcji — odhaczać po weryfikacji na podglądzie/obrazie).

### Zarządzanie oknami
- [x] otwieranie okien z kaskadą pozycji
- [x] przeciąganie za pasek tytułu
- [x] resize w 8 kierunkach (krawędzie+narożniki, kursory)
- [ ] snapping krawędziowy i narożnikowy z podglądem
- [x] minimalizacja / maksymalizacja / przywracanie
- [ ] przywracanie przez odciągnięcie od krawędzi
- [x] kolejność Z + fokus aktywnego okna
- [ ] recykling z-index
- [ ] always-on-top (np. menedżer zadań)
- [ ] Alt+Tab cykliczne przełączanie okien
- [ ] pokaż pulpit / minimalizuj wszystko
- [ ] karty w oknach (add/switch/close)
- [ ] zapis pozycji okien między sesjami

### Pasek zadań / dock / Start
- [x] pasek zadań z przyciskami okien
- [ ] przypinanie/odpinanie aplikacji z persistencją
- [ ] drag-reorder przypiętych ikon
- [ ] menu kontekstowe docka
- [x] dwukolumnowe menu Start
- [ ] działająca wyszukiwarka w menu Start
- [ ] "All Programs" (lista aplikacji APX)
- [ ] skróty lokalizacji w Starcie (Dokumenty itd.)
- [ ] ustawienia paska (układ, ukrywanie)
- [x] zegar w tacce
- [ ] panel sieci w tacce
- [ ] panel baterii w tacce (laptop/T480)
- [x] menu Start: zmienny rozmiar (wymóg HIG "resize wszystkiego")

### Logowanie / sesja / zasilanie
- [ ] graficzny ekran logowania (spec: login.html pierwszego konceptu)
- [ ] auto-login (opcja)
- [ ] zegar/data na ekranie logowania
- [x] menu zasilania: reboot / power off (przez openrc-shutdown)
- [ ] wylogowanie (po wprowadzeniu sesji użytkownika)
- [ ] overlay z animacją przy wylogowaniu/restarcie
- [ ] Guru Meditation — systemowy ekran błędu

### Menedżer plików
- [x] przeglądanie prawdziwego systemu plików
- [x] historia wstecz/naprzód/w górę
- [x] breadcrumb klikalny + edytowalny pasek adresu
- [x] dropdown lokacji przy pasku adresu
- [x] sortowanie kolumn
- [ ] resize / reorder / drag kolumn
- [ ] zaznaczanie wielokrotne + gumka (rubber-band)
- [x] podgląd plików tekstowych
- [ ] podgląd obrazów
- [ ] menu kontekstowe pliku i tła
- [ ] kopiuj / wklej
- [x] usuń (dwustopniowe)
- [ ] zmiana nazwy (inline)
- [ ] właściwości pliku
- [x] nowy folder
- [ ] nowy plik z szablonów
- [x] wyszukiwanie w bieżącym katalogu
- [x] sidebar lokalizacji
- [x] wolne miejsce wolumenu w pasku statusu

### Terminal
- [ ] prawdziwy PTY do zsh (przez Executor; devpts w /System/Devices/pts)
- [ ] Ctrl+C / Ctrl+D do procesu
- [ ] obsługa sekwencji ANSI
- [x] historia komend (góra/dół)
- [x] built-iny na realnych danych (ls/cat/ps/free/df/state...)

### Ustawienia
- [x] okno ustawień
- [x] skala UI (auto + kroki)
- [ ] persistencja ustawień (plik w /System/State lub profilu)
- [ ] ustawienia zegara (sekundy, 12/24h)
- [ ] tryb wydajności (globalne wyłączenie efektów)
- [ ] ustawienia tapety

### Powiadomienia i widgety
- [ ] toasty powiadomień (ikona/tytuł/treść, kolejka)
- [ ] widget zegara/kalendarza na pulpicie
- [ ] widget pogody (po sieci w Workbenchu)

### Tapeta
- [ ] statyczna tapeta z pliku
- [ ] Aurora / animowana tapeta (po przejściu na GLES2)
- [ ] reakcja tapety na porę dnia / obciążenie

### Wyszukiwanie globalne
- [ ] Spotlight: aplikacje + pliki, nawigacja klawiaturą

### Aplikacje
- [ ] odkrywanie zainstalowanych APX + uruchamianie
- [ ] menedżer zadań: lista procesów, sortowanie, filtr, kill
- [ ] zakładka wydajności (wykresy CPU/RAM) — częściowo w Runtime Monitor
- [x] Runtime Monitor: CPU/RAM/procesy/uptime/stany serwisów
- [ ] przeglądarka (daleka przyszłość)
- [ ] Snake / gra demo (na deser)

### Ikony pulpitu
- [ ] ikony na siatce + przeciąganie + zapis układu
- [ ] inline rename ikon
- [ ] menu kontekstowe pulpitu

### Skróty klawiszowe
- [x] Ctrl+K paleta, Ctrl+L adres, Escape zamyka warstwę
- [ ] konfigurowalne skróty z pliku TOML (~17 akcji jak w koncepcie)

### Warstwy ekranu (screen manager z pierwszego konceptu)
- [x] konsola systemowa ściągana gestem z górnej-środkowej krawędzi pulpitu
      (strefa ~36% szerokości na środku, próg otwarcia 25% wysokości) + F12;
      Escape zamyka
- REGUŁA: warstwa konsoli NIE działa w tle — dopóki użytkownik jej nie
  ściągnie, jest wyłączona (zero renderowania, timerów i logiki); koszt
  ponosi się wyłącznie, gdy jest widoczna. Dotyczy też przyszłej tapety
  shaderowej pod konsolą (Aurora aktywuje się razem z warstwą)
- [ ] tło konsoli = aktywna tapeta shaderowa (po GLES2)

### Boot / infrastruktura
- [ ] sekwencja bootowania z logiem czasów (splash)
- [ ] globalna obsługa błędów UI (odpowiednik window.onerror)
- [ ] lokalizacja/języki
- [ ] tryb mobilny / launcher dotykowy (kiedyś, po desktopie)
Dalej: Alt+Tab, pokaż pulpit, ikony pulpitu z siatką i zapisem, toasty
powiadomień, widget pogody/kalendarza, panele sieci/baterii, menu zasilania
z overlayami, ekran logowania (spec: login.html tamtego repo), Guru
Meditation jako ekran błędu, sekwencja bootowania z logiem czasów,
odkrywanie i launch aplikacji (APX zamiast .desktop), tapeta Aurora
(po przejściu na GLES2), tryb mobilny/launcher — na końcu.
