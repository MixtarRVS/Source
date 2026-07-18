# Mixtar M1 Builder

`scripts/build-m1.ps1` jest jedynym pipeline'em stabilnego obrazu M1. Buduje
system z przypiętych źródeł, publikuje obraz RAW i VHDX, podpisuje artefakty i
uruchamia pełną akceptację.

## Wymagania hosta

- Windows z PowerShellem i WSL2;
- dystrybucja WSL wskazana przez `Layout.config` (obecnie Debian);
- Python 3.11 lub nowszy;
- toolchain kernela, musl, Meson, Ninja, patch, patchelf, ccache, cpio i zstd w WSL;
- `sbsign` i `sbverify` z pakietu `sbsigntool`;
- QEMU, OVMF i `qemu-img`;
- Hyper-V dla testu Generation 2, wraz z prawami administratora.

## Pełny build

```powershell
.\scripts\build-m1.ps1 -CleanCache -TestHyperV
```

`-CleanCache` tworzy unikalną pustą przestrzeń cache. `-TestHyperV` uruchamia
na końcu tymczasową maszynę Generation 2 i może wywołać elewację UAC. Brak
któregokolwiek znacznika akceptacji przerywa pipeline kodem różnym od zera.

## Kontrakt wydania

`Release/M1.lock.config` przypina dokładne wersje, URL-e, commity, patche i
SHA-256. `Layout.config` przechowuje layout, możliwości oraz parametry
uruchomieniowe, a nie wersje wydania. `scripts/resolve-m1.py` wykrywa kandydata
niezależnie od builda i nigdy nie aktualizuje locka automatycznie.

M1 jest zakotwiczony w OpenZFS. Kernel zmienia się dopiero wtedy, gdy wybrane
wydanie OpenZFS obsługuje jego dokładną wersję. Polityka nie preferuje LTS i
odrzuca wydania `-rc`.

## Etapy

1. Walidacja layoutu i release locka.
2. Budowa P0 z dokładnego archiwum Linux i przypiętych OpenRC/BusyBox.
3. Budowa OpenZFS i OpenSSL z kontrolą SHA-256.
4. Podpisanie modułów oraz eksport nagłówków, `Module.symvers`, `objtool` i SDK.
5. Budowa podpisanych EFI Stubów dla `M1-A`, `M1-B` i niezależnego recovery.
6. Utworzenie readonly `mixtar/ROOT/M1-A` oraz trwałych datasetów stanu i danych.
7. Utworzenie podpisanego bundle aktualizacji do `M1-B`.
8. Provisioning ZFS, obrazy RAW/VHDX i podpisane manifesty.
9. Akceptacja konsoli, sieci, trwałości, aktualizacji, rollbacku i braku FHS.
10. Akceptacja tego samego VHDX w Hyper-V Generation 2.
11. Podpisanie końcowego `M1.release.json`.

## Artefakty

- `Output/P1/MixtarRVS-M1-x86_64.disk.img`: surowy obraz GPT/UEFI.
- `Output/P1/MixtarRVS-M1-x86_64.vhdx`: dysk Hyper-V Generation 2.
- `Output/P1/MixtarRVS-M1-B.update.fat`: podpisany bundle aktualizacji.
- `Output/P1/MixtarRVS-M1-x86_64.Recovery.EFI`: niezależne recovery.
- `Output/P3/M1.release.json`: końcowy kontrakt i wyniki akceptacji.
- `Output/P3/M1.release.sig`: podpis końcowego kontraktu.

Prywatny klucz pozostaje w `Output/P3/Signing/M1.key.pem`; nie trafia do obrazu
ani manifestu wydania. Publiczny klucz jest osadzony jako
`/System/Configuration/Release/M1.public.pem`.

## Reprodukowalność i dowód M1

Końcowy przebieg z 16 lipca 2026 użył pustego namespace
`m1-clean-89dacb223a7148d8896ffb6a51ea0f39` i zakończył się znacznikiem
`MIXTAR_M1_PIPELINE_OK` po `2719,7 s`. Czasy każdego etapu są zapisane w
`Output/P3/M1.release.json`. Raporty w `Output/P1` i `Output/P3` potwierdzają
QEMU/OVMF, Hyper-V, zewnętrzny moduł, integralność, podpisy, update i recovery.

## Secure Boot

Wszystkie trzy EFI Stub-y oraz moduły są podpisane i przechodzą `sbverify` lub
weryfikację podpisu modułu. Automatyczna akceptacja Hyper-V działa z Secure
Boot wyłączonym, ponieważ standardowe szablony Hyper-V nie ufają lokalnemu
certyfikatowi M1. Włączenie egzekwowania Secure Boot wymaga wcześniejszego
zapisania zaufanego certyfikatu M1 w używanym firmware; pipeline nie wykonuje
tego enrollmentu automatycznie.
