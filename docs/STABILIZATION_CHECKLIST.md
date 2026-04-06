# Stabilizacni Checklist (DubbingEditor)

Tento checklist slouzi pro opakovatelne overeni pred dalsim vyvojem nebo vydanim.

Automatizovany report:

```bash
./scripts/run_stabilization_report.sh
```

Skript vytvori `PASS/BLOCK` report v `docs/reports/latest.md` + archiv behu v `docs/reports/`.

## 1) Rychly Gate (10-15 min)

Pouzij pred kazdou vetsi zmenou nebo pred odevzdanim builda.

- [ ] `swift build` probehne bez chyby.
- [ ] App se spusti (`swift run`) a okno reaguje bez zaseku.
- [ ] Import Word (`.docx` nebo `.docm`) nacte repliky.
- [ ] Import video (`.mp4` nebo `.mov`) nacte prehravac.
- [ ] Klik na repliku: skok videa na start TC.
- [ ] Dvojklik na repliku: edit + oranzove zvyrazneni.
- [ ] Search `Dalsi/Predchozi`: vyber modre + auto-scroll na cil.
- [ ] `Option+Space`: rewind/replay funguje podle aktualni logiky.
- [ ] Export DOCX projde bez chyby.
- [ ] Save Project + Open Project: data se obnovi.

Gate pravidlo:
- Pokud cokoliv z bodu vyse selze, build nejde dal.

## 2) Plny Checklist (40-60 min)

### A) Core workflow

- [ ] Nacist Word bez timecodu a rucne doplnit `S/E`.
- [ ] Nacist Word s timecody a overit parsovani.
- [ ] Aplikovat offset (`+` i `-`) a overit realny posun.
- [ ] Loop ON/OFF funguje na vybrane replice.
- [ ] Enter spusti/ukonci edit podle aktualnich pravidel.
- [ ] Sipky nahoru/dolu meni vyber replik.

### B) Vyhledavani a nahrazovani

- [ ] Find najde text bez ohledu na diakritiku.
- [ ] `Predchozi/Dalsi` skace konzistentne mezi matchi.
- [ ] `Nahradit vybranou` meni jen cilovou repliku.
- [ ] `Nahradit vse` meni vsechny match repliky.
- [ ] Po replace zustane app responsivni.

### C) Projekt a persistence

- [ ] Save/Open `.dbeproj` obnovi:
- dokument title, fps, lines, selection, paths
- `Light Mode`, view volby, shortcuts (v2 settings)
- [ ] Legacy v1 projekt se otevre bez chyby.
- [ ] Autosave se vytvori pri zmene dat.
- [ ] Po killu aplikace se nabidne recovery latest snapshotu.

### D) Export

- [ ] Export DOCX ma format: `postava<TAB>timecode<TAB>text`.
- [ ] Volby timecode slozek (h/m/s/f) se projevi ve vystupu.
- [ ] Pri dostupnem source Word se zachova format/layout.
- [ ] Pri chybejicim source Word fallback export projde.

### E) Light Mode (vykon)

- [ ] Prepinac v `View > Light Mode` funguje.
- [ ] Pri zapnuti je app citelne plynulejsi na velkem projektu.
- [ ] Po ulozeni/otevreni projektu zustane Light Mode zachovan.

## 3) Performance Scenar (Large Project)

Cilovy scenar:
- ~2000 replik
- video nactene
- aktivni hledani + scroll + prehravani

Over:
- [ ] Psanim do `Find` nevznikaji dlouhe UI zaseky.
- [ ] Scroll panelu replik zustava plynuly.
- [ ] `Predchozi/Dalsi` reaguje bez viditelneho lagu.
- [ ] Edit jedne repliky nezpusobuje trhani celeho seznamu.

Doporucene prostredi testu:
- slabsi stroj (8 GB RAM) + normalni stroj, pro porovnani.

## 4) Defect triage pred vydanim

Zastav release pri:
- padu aplikace
- ztrate dat pri save/open/export
- rozbite klavesove ovladani editu
- rozbite obnoveni projektu/autosave

Muze pockat na dalsi iteraci:
- drobne vizualni nedokonalosti
- textove nepresnosti v UI
- mikro-lagy bez dopadu na data

## 5) Test Report (kopie sablony)

Datum:
Build/commit:
Tester:
Mac model + RAM:
macOS verze:

Rychly gate:
Plny checklist:
Performance scenar:

Nalezene chyby:
Release verdict: PASS / BLOCK
