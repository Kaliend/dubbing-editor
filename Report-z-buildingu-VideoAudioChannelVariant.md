**Shrnutí**

- MTAudioProcessingTap už nebyl vhodný pro produkční Mute L/R, protože A/B debug zúžil bug na seek/replay nad stejným AVPlayerItem s aktivním tapem. Channel isolation teď neběží v runtime render path, ale přes derived stems v ChannelDerivedAudioService.swift.
- Zavedl jsem model VideoAudioChannelVariant se stavy .stereo, .leftOnly, .rightOnly, .muted v ChannelDerivedAudioService.swift. EditorViewModel teď mapuje Mute L/R na variantu a dělá rebuild playback source se zachováním playback position a resume stavu v EditorViewModel.swift.
- External audio zůstává samostatná vrstva v composition a Mute L/R ho neovlivňuje. Routing je v PlaybackCompositionService.swift.
- Cacheuju jen derived left/right stems, ne projektová data. Cache je lokální pod ~/Library/Caches/DubbingEditor/ChannelDerivedAudio/ a klíčuje se podle source video path + modification date + file size + varianty. Implementace je v ChannelDerivedAudioService.swift.
- Hotspot EditorViewModel.swift jsem nechal jen jako owner stavu, preserve-position rebuild routingu a failure rollbacku. Stem generation a cache logika zůstala mimo něj.

**Změněné soubory**

- ChannelDerivedAudioService.swift
- PlaybackCompositionService.swift
- EditorViewModel.swift
- PlaybackPanelView.swift
- AppSettingsView.swift
- PlaybackCompositionServiceTests.swift
- ChannelDerivedAudioServiceTests.swift

**Ověření**

- swift build
- swift test
- ./scripts/run_stabilization_report.sh
- report: stabilization-20260405-175521.md

Doplnil jsem testy pro mapování mute stavu na VideoAudioChannelVariant, pro PlaybackCompositionService audio-mix kontrakt bez tapu a pro cache identity/invalidation rozhodování. Nepřidával jsem unit test na samotnou AVAssetReader/AVAudioFile stem generation pipeline; tohle je v praxi spíš integrační AVFoundation chování a dává větší smysl ověřit ho manuálně.

Reality check: invazivnější než se čekalo bylo oddělit „source video má audio“ od „aktuální composition právě obsahuje video audio track“, aby se při .muted variantě nerozbilo UI. Nejvyšší další ROI je teď čistě manuální QA na původní repro: video bez external audia i s external audiem, seek za běhu, replay, loop a první přepnutí L/R při cold cache. Hlavní rizika zůstávají první čekání na stem generation, preserve-position při rebuildu a předpoklad, že kanál 0/1 odpovídá zamýšlenému L/R u všech zdrojů. Not now: žádný AVAudioEngine rewrite, žádný mixer, žádný playback UI redesign.