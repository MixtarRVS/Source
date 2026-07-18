# Instrukcje dla agentów (Codex / Claude / inne)

**Zacznij od `HANDOFF.md`** — opisuje aktualny stan prac, otwarte bugi
i narzędzia. Potem: `ROADMAP.md` (porządek prac), `P4.md` (normatywny kontrakt
warstwy produktu), `BUILDER.md` (wymagania hosta i pipeline).

Twarde zasady projektu (szczegóły w ROADMAP.md, sekcja 3):

- Mixtar NIE publikuje FHS: żadnych `/usr`, `/etc`, `/dev`, `/proc`, `/sys`,
  `/run` w publicznym root. Urządzenia: `/System/Devices`, sysfs:
  `/System/Hardware`, procfs: `/System/Processes`. Upstream'owe biblioteki
  z zaszytymi ścieżkami FHS patchuje się w źródłach (wzorzec: `Patches/*.patch`
  + wpisy `patch`/`patch_sha256` w lockach `Release/*.lock.config`).
- Kolejność builda jest niezmiennikiem: wspólne drzewo kernela w WSL musi
  stać na aktualnym `Kernel/x86_64-mixtar.config` ZANIM buduje się OpenZFS
  lub cokolwiek liczonego z ABI kernela.
- Kanoniczne artefakty wydania w `Output/P1` i `Output/P3` są podpisane —
  nie nadpisywać ich ścieżkami deweloperskimi; dev-artefakty idą do
  `Output/P4/Dev/`.
- Pliki `*.config` to TOML (tekst = źródło prawdy). Komunikaty systemu po
  angielsku.
- Wersje, URL-e i SHA-256 źródeł przypinają locki w `Release/` — zmiana
  źródła lub patcha wymaga aktualizacji locka.

Repozytorium nie ma jeszcze commitów — pierwszy commit z sensownym
`.gitignore` to zaległe zadanie (patrz HANDOFF.md).
