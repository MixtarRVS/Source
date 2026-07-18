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
