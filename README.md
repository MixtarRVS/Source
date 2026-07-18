# MixtarRVS

To repozytorium jest główną i najnowszą linią MixtarRVS.

MixtarRVS to samodzielny system operacyjny z kernelem Linux, OpenZFS jako
natywnym systemem plików, OpenRC jako PID 1, BusyBox ash jako technicznym `sh`
i zsh/GRML jako powłoką użytkownika. Nie jest dystrybucją Debiana, nie używa
APT, `dpkg` ani publicznego FHS.

Publiczny layout:

```text
/System
/Users
/Volumes
/Temporary
```

Przestrzenie kernela są dostępne pod natywnymi nazwami:

```text
/System/Processes
/System/Hardware
/System/Devices
/System/Runtime
```

## Stan wydania

- P0, P1, P2 i P3 są zakończone.
- M1 jest stabilnym wydaniem konsolowym z przypiętym Linux `7.1.3` i OpenZFS `2.4.2`.
- QEMU/OVMF i Hyper-V Generation 2 są platformami akceptacyjnymi.
- P4 jest odblokowane, ale nie zostało rozpoczęte.
- Pulpit, APX, AILang, MDDM, MWM i Server pozostają poza zakresem M1.
- Komunikaty systemu i pierwszy boot używają języka angielskiego.

## Jedno polecenie

```powershell
.\scripts\build-m1.ps1 -CleanCache -TestHyperV
```

Polecenie buduje system od pustego cache, tworzy RAW i VHDX, podpisuje
artefakty oraz wykonuje testy QEMU/OVMF i Hyper-V. Bez `-CleanCache` builder
używa cache kompilatora. Bez `-TestHyperV` pomija wyłącznie test wymagający
administracyjnych uprawnień Hyper-V.

Końcowy kontrakt wydania znajduje się w `Output/P3/M1.release.json`, a jego
podpis w `Output/P3/M1.release.sig`.

## Wersje i aktualizacje źródeł

Dokładny zestaw źródeł M1 znajduje się w `Release/M1.lock.config`. Wykrycie
nowszego stabilnego kernela jest oddzielną, informacyjną operacją:

```powershell
py -3 scripts/resolve-m1.py
```

Resolver nie zmienia locka ani wejść aktywnego wydania. OpenZFS pozostaje
kotwicą doboru kolejnej pary kernel/OpenZFS.

## Dokumentacja

- `BUILDER.md`: wymagania hosta, pipeline i artefakty.
- `P3.md`: uruchomienie, instalacja, aktualizacja, rollback i recovery.
- `ROADMAP.md`: zamknięte P0-P3 oraz dalszy zakres P4.
