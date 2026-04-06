# DubbingEditor (macOS)

## Stažení a instalace

**Požadavky:** macOS 13 nebo novější, Swift 5.9+

```bash
# Klonuj repozitář
git clone https://github.com/Kaliend/dubbing-editor.git
cd dubbing-editor

# Nainstaluj závislosti a spusť
swift run
```

Nebo jako plnohodnotná macOS aplikace s ikonou v Docku:

```bash
./run_as_app_bundle.sh
```

Lokální desktop MVP pro úpravu dabingového textu nad videem.

## Co umí

- Import `Word` souboru (`.docx`, `.docm`)
- Import videa (`.mp4`, `.mov`)
- Zobrazení a editace replik (speaker, text, start/end timecode)
- Jednoduche pridani nove repliky (novy radek)
- Klik na repliku => seek videa na start timecode
- Doplňování timecodů z aktuální pozice videa (`S` = start, `E` = end)
- Hromadny posun timecodu pres `Offset` (sekundy nebo timecode)
- Zobrazení audio waveform pod videem
- Export upraveného obsahu do `.docx`
- Autosave interního stavu + verzované JSON zálohy
- Export se zachovanim puvodniho formatovani pri importu z existujiciho Word souboru
- Export dialog s volbou slozek timecodu (hodiny/minuty/sekundy/framy)
- Ukladani a nacitani projektu (`.dbeproj`)
- Rychle hledani v replikach (text/postava/TC) + `Prev/Next`

## Spuštění

```bash
swift run
```

Spusteni jako macOS app bundle (Dock/Finder + app ikona):

```bash
./run_as_app_bundle.sh
```

## Testy

```bash
swift test
```

## Ikona aplikace

Vygenerovani moderni ikony (`.svg`, `1024 .png`, `.iconset`, `.icns`):

```bash
./scripts/build_app_icon.sh
```

Vystup:
- `assets/AppIcon.svg`
- `assets/AppIcon-1024.png`
- `assets/AppIcon.iconset`
- `assets/AppIcon.icns`

`run_as_app_bundle.sh` tohle nastavuje automaticky (`AppIcon.icns` + `CFBundleIconFile`).

Automatizovany stabilizacni report (PASS/BLOCK):

```bash
./scripts/run_stabilization_report.sh
```

Vystup:
- `docs/reports/stabilization-YYYYMMDD-HHMMSS.md`
- `docs/reports/latest.md`

Stabilizacni checklist:
- `docs/STABILIZATION_CHECKLIST.md`

Roadmapa:
- `docs/ROADMAP.md`

Po startu:
1. `Import Word`
2. `Import Video`
3. volitelne `Save Project` pro prubezne ulozeni projektu
4. upravuj repliky v pravém panelu
5. `Export DOCX`

## Poznámky k MVP

- Import Wordu načítá obsah po odstavcích z `word/document.xml`.
- Timecody se detekují automaticky, pokud jsou v textu (napr. `00:00:12` nebo `00:00:12:10`).
- Pokud timecody chybí, lze je doplnit ručně nebo tlacitky `S`/`E`.
- Fallback export vytvori novy cisty `.docx` s textovym obsahem.
- Pokud je dostupny puvodni importovany Word soubor, export pouzije jeho strukturu a zachova layout/styly.
- Kdyz puvodni soubor neni k dispozici, export se vrati na cisty fallback `.docx`.
- Exportovany radek ma vzdy format: `postava<TAB>timecode<TAB>text`.
- Projekt `.dbeproj` uklada stav editoru (repliky, fps, vyber, cesty na source Word/video).
- Autosave se ukládá do `~/Library/Application Support/DubbingEditor/Autosaves`.
- `latest.json` slouží pro obnovu po pádu, `versions/` drží historii (max 50 souborů).
