# AGENTS.md

## Ucel
Tenhle projekt je macOS desktop editor dabingoveho textu nad videem. Agent workflow ma kopirovat realne hranice domen v aplikaci, ne jen vrstvy SwiftUI.

Cil:
- zmensit kolize v `EditorViewModel.swift` a `ContentView.swift`
- mit jasneho ownera pro kazdy task
- nutit integracni review u zmen s vysokym rizikem regresi

## Zakladni pravidla
- V jednom tasku pouzij jen minimalni pocet agentu, ktery staci.
- Kazdy task musi mit presne jednoho hlavniho ownera.
- Druhy agent se priziva jen kdyz task prechazi pres hranici domeny nebo zasahuje hotspot soubor.
- Kdyz je potreba vice agentu, postup je `Orchestrator -> domain owner -> QA/Performance`.
- Pokud zmena zasahuje import/export, persistence nebo playback seek chovani, QA review je povinne.

## Agenti

### 1. Product Orchestrator Agent
Pouziti:
- rozklad pozadavku
- urceni ownera
- plan handoffu mezi domenami
- finalni integracni kontrola

Nevlastni vetsinu kodu. Ma ridit, ne absorbovat implementaci.

### 2. Transcript IO Agent
Owner pro:
- Word import
- Word export
- format detection
- IYUNO/classic pipeline
- DOC/DOCX kompatibilitu
- exportni sablony a fallbacky

Primarni soubory:
- `Sources/DubbingEditor/Services/WordImportService.swift`
- `Sources/DubbingEditor/Services/WordExportPipelineService.swift`
- `Sources/DubbingEditor/Services/WordExportService.swift`
- `Tests/DubbingEditorTests/WordImportServiceTests.swift`
- `Tests/DubbingEditorTests/WordExportPipelineServiceTests.swift`
- `Tests/DubbingEditorTests/WordExportServiceTests.swift`

Pouzij ho kdyz task obsahuje slova:
- import
- export
- docx
- doc
- iyuno
- classic format
- template

### 3. Editing Workflow Agent
Owner pro:
- CRUD replik
- selection model
- edit mode
- drag and drop
- copy/paste replik
- find/replace
- undo/redo
- row level UX

Primarni soubory:
- `Sources/DubbingEditor/Models/EditorViewModel.swift`
- `Sources/DubbingEditor/Views/ContentView.swift`
- `Sources/DubbingEditor/Views/DialogueRowView.swift`
- `Tests/DubbingEditorTests/EditorViewModelTests.swift`

Pouzij ho kdyz task meni chovani editoru seznamu replik.

### 4. Timecode Validation Agent
Owner pro:
- parse a format timecodu
- capture start/end TC
- auto advance
- offsety textu a videa
- chrono kontroly
- validace TC a speaker chyb

Primarni soubory:
- `Sources/DubbingEditor/Services/TimecodeService.swift`
- relevantni casti `Sources/DubbingEditor/Models/EditorViewModel.swift`
- `Tests/DubbingEditorTests/TimecodeServiceTests.swift`

Pouzij ho kdyz task obsahuje slova:
- timecode
- TC
- chrono
- offset
- validation

### 5. Playback Media Agent
Owner pro:
- AVPlayer integraci
- seek policy
- loop playback
- waveform build/cache
- audio channels a mute
- playback panel a player container

Primarni soubory:
- `Sources/DubbingEditor/Services/WaveformService.swift`
- `Sources/DubbingEditor/Services/StereoChannelMuteService.swift`
- `Sources/DubbingEditor/Views/PlaybackPanelView.swift`
- `Sources/DubbingEditor/Views/PlayerContainerView.swift`
- `Sources/DubbingEditor/Views/WaveformView.swift`

Pouzij ho kdyz task obsahuje slova:
- playback
- player
- video
- waveform
- audio
- seek
- loop

### 6. Project Persistence Agent
Owner pro:
- `.dbeproj`
- autosave
- recovery po padu
- recent projects
- settings persistence
- schema versioning a backward compatibility

Primarni soubory:
- `Sources/DubbingEditor/Services/ProjectService.swift`
- `Sources/DubbingEditor/Services/AutosaveService.swift`
- `Sources/DubbingEditor/Views/AppSettingsView.swift`
- relevantni casti `Sources/DubbingEditor/Models/EditorViewModel.swift`
- `Tests/DubbingEditorTests/ProjectServiceTests.swift`

Pouzij ho kdyz task obsahuje slova:
- save
- open project
- autosave
- restore
- settings
- schema

### 7. QA Performance Agent
Owner pro:
- regresni test plan
- smoke testy
- performance smoke testy
- stabilizacni reporty
- kontrolu coverage pro rizikove zmeny

Primarni soubory:
- `Tests/DubbingEditorTests/*`
- `docs/STABILIZATION_CHECKLIST.md`
- `docs/ROADMAP.md`
- `scripts/run_stabilization_report.sh`
- `docs/reports/*`

Pouzij ho:
- po kazde zmene import/export
- po kazde zmene persistence
- po kazde zmene playback seek/loop logiky
- po kazde zmene s dopadem na vykon velkych projektu

## Handoff pravidla

### Povinne handoffy
- `Transcript IO Agent -> QA Performance Agent`
- `Project Persistence Agent -> QA Performance Agent`
- `Playback Media Agent -> QA Performance Agent`

### Doporucene handoffy
- `Editing Workflow Agent -> Timecode Validation Agent`
  kdyz editacni zmena mutuje start/end TC nebo selection seek
- `Editing Workflow Agent -> Playback Media Agent`
  kdyz klik nebo selection meni prehravani
- `Project Persistence Agent -> Editing Workflow Agent`
  kdyz restore/open meni selection, focus nebo edit state

## Hotspot soubory
Tyto soubory jsou bottleneck a nesmi se menit bez extra opatrnosti:
- `Sources/DubbingEditor/Models/EditorViewModel.swift`
- `Sources/DubbingEditor/Views/ContentView.swift`

Pravidla pro hotspoty:
- vzdy urci jednoho ownera, i kdyz zmena technicky zasahuje vice domen
- pred editaci popis, ktera cast je domenova a ktera jen integracni
- po editaci udelej aspon jedno krizove review druhym agentem
- nepridavej dalsi nesouvisejici odpovednosti do techto souboru, pokud jde logiku vytahnout do sluzby

## Routing podle typu tasku
- "Import z Wordu pada / spatne mapuje radky" -> Transcript IO Agent
- "Export je rozbity / tabulka nema spravne bunky" -> Transcript IO Agent
- "Klikani, vyber, editace, drag/drop, copy/paste" -> Editing Workflow Agent
- "TC mod, capture, offsety, chrono chyby" -> Timecode Validation Agent
- "Player, waveform, audio kanaly, loop, seek" -> Playback Media Agent
- "Ukladani projektu, autosave, recovery, settings" -> Project Persistence Agent
- "Regrese, smoke test, vykon, stabilizace" -> QA Performance Agent

## Definition of Done pro zmenu
- owner agent implementuje zmenu jen ve sve domene a nutnych integracnich bodech
- jsou doplneny nebo upraveny testy v odpovidajici test sade, pokud jde o logickou zmenu
- jsou spusteny aspon relevantni testy pro danou domenu
- u rizikovych zmen probehne QA/Performance kontrola
- je explicitne uvedeno, jestli zmena zasahla hotspot soubor

## Refactoring smer
Pri vetsich upravach smeruj architekturu timto smerem:
- z `EditorViewModel` postupne oddelovat `EditingSession`
- z `EditorViewModel` postupne oddelovat `PlaybackController`
- z `EditorViewModel` postupne oddelovat `ProjectSession`
- z `ContentView` postupne oddelovat cache/validation/search koordinator

Nevytvarej samostatneho "UI agenta" a "ViewModel agenta". V tomhle projektu by to duplikovalo ownership misto toho, aby ho zjednodusilo.
