# Samodzielny prototyp pulpitu MixtarRVS w RmlUi

Ten katalog buduje natywny program `MixtarRVS.exe`. Nie jest to strona HTML,
WebView ani biblioteka oczekująca na przyszły host. Program tworzy własne okno,
obsługuje wejście, aktualizuje model RML i renderuje pulpit przez OpenGL 3.3.

## Warstwy

- RmlUi interpretuje `Desktop.rml` i `Desktop.rcss`.
- SDL3 zapewnia wyłącznie okno, klawiaturę, mysz, IME i kontekst OpenGL.
- FreeType rasteruje font do atlasu używanego przez RmlUi.
- `DesktopHost.cpp` zawiera pętlę programu i jest miejscem przyszłej wymiany SDL
  na natywny host MWM/Mixtara.
- `DesktopModel.cpp` wiąże zegar i zdarzenia interfejsu z RML.

## Budowanie na Windows

Wymagane są Git, CMake 3.24+ i Visual Studio 2022 z komponentem C++ Desktop.
Pozostałe zależności są pobierane i budowane automatycznie.

```powershell
cmake -S Prototypes/RmlUi -B out/rmlui -G "Visual Studio 17 2022" -A x64
cmake --build out/rmlui --config Release --parallel
```

Program i komplet zasobów pojawią się tutaj:

```text
out/rmlui/bin/MixtarRVS.exe
out/rmlui/bin/Resources/
out/rmlui/bin/Licenses/
```

Po zbudowaniu `bin` można przenieść jako całość. Program odnajduje `Resources`
względem własnego pliku wykonywalnego, a nie względem katalogu uruchomienia.

## Kanały zależności

SDL i SDL_image śledzą stabilne gałęzie `release-3.4.x`. RmlUi i FreeType nie
publikują równoważnego kanału o wystarczająco przewidywalnym kontrakcie, dlatego
domyślnie używane są przejrzane wydania. Każdy ref jest wpisem cache CMake, więc
można go zmienić bez edycji pliku:

```powershell
cmake -S Prototypes/RmlUi -B out/rmlui `
  -DMIXTAR_RMLUI_REF=6.2 `
  -DMIXTAR_SDL_REF=release-3.4.x
```

## Licencje

Kod prototypu nie używa Qt ani .NET. RmlUi jest na licencji MIT, SDL i SDL_image
na zlib, FreeType zachowuje własną licencję FTL/GPL, a LatoLatin zachowuje SIL
Open Font License. Teksty licencji są kopiowane obok programu do `Licenses`.

To nadal prototyp hosta graficznego, nie MWM ani MDDM. Granica hosta jest jednak
jawna: wymiana SDL na interfejs systemowy Mixtara nie wymaga przepisywania RML,
RCSS ani modelu pulpitu.
