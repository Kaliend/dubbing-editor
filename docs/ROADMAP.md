# Roadmapa (DubbingEditor)

## Pristi funkcni kroky

1. Jednoduche pridavani nove repliky (novy radek).
2. Jednoduchy mod na pridavani timecode pro jednotlive repliky.

## Potvrzene dalsi body

3. Kliknuti funguje v cele plose repliky (v hranicich zvyrazneni)
- 1x klik kdekoliv v karte repliky:
  - vybere repliku (modre zvyrazneni)
  - skoci video na Start TC vybrane repliky
- 2x klik kdekoliv v karte repliky:
  - prepne repliku do editu (oranzove zvyrazneni)
- Nemusi se klikat jen do textoveho pole.

4. Chronologicka kontrola Start TC + seznam chyb s proklikem
- Pravidlo chyby:
  - porovnava se pouze Start TC
  - chyba je jen kdyz `next.start < prev.start`
  - `next.start == prev.start` je v poradku
- Repliky bez validniho Start TC se do chrono porovnani neberou.
- Aplikace zobrazi seznam chrono chyb:
  - pocet chyb
  - `Predchozi/Dalsi chyba`
  - klik na chybu skoci na repliku
- Chybove repliky se vizualne oznaci (marker/upraveny border u Start TC).

## Performance dalsi kroky

5. Debounce metadata validaci po potvrzeni hodnot
- Pri commitu `Start/End/Speaker` neprepocitavat validace okamzite pri kazde zmene.
- Zavest kratky debounce (cca 120-200 ms) pro metadata cache update.
- Cilem je plynulejsi fokus a rychlejsi reakce po kliknuti do poli.
- Stav: hotovo.

6. Validace pocitat prioritne pro viewport + aktivni repliku
- Pri beznem zobrazeni prepocitavat validace jen pro viditelne repliky a aktivni radek.
- Pro plny prepocet zachovat fallback pri explicitnich akcich (napr. "Jen problematicke").
- Cilem je snizit zatizeni pri scrollu velkych projektu.
- Stav: hotovo.

7. Agresivnejsi virtualizace seznamu replik (viewport windowing)
- Misto celeho `LazyVStack` drzet renderovane jen okolni okno kolem viewportu + buffer.
- Cilem je mensi pocet aktivnich SwiftUI view pri velmi dlouhych projektech.

8. Dalsi oddeleni lokalniho edit stavu od modelu (row transaction)
- Bhem editace drzet cele metadata/text lokalne a commitovat jednou transakci po potvrzeni.
- Cilem je minimalizovat `lines` mutace behem editace.

9. Presun tezsich prepoctu mimo main thread
- Vypocet validaci/hledaciho haystacku pocitat v background tasku.
- Na main thread aplikovat jen vysledny diff.

10. Adaptivni seek policy pri editaci
- Pri aktivnim psani omezit nebo odlozit automaticky seek videa z vyberu.
- Cilem je mene dekoder tlaku v okamziku fokus/prepis.

11. Dev mode metriky a profiling markery
- Pridat mereni `click->focus`, `commit->linesChanged`, `linesChanged->cacheDone`.
- Cilem je mit tvrda data pro dalsi optimalizace a regresni kontrolu.

12. Timeline mini-mapa (overview)
- Pridat komprimovany horizontalni pruh pro cely cas videa.
- Kazdou repliku vykreslit jako segment dle `start/end` (pri chybejicim `end` pouzit fallback).
- Zobrazit playhead, viewport a aktivni repliku.
- Interakce:
  - klik = skok videa + seznamu na dany cas
  - drag viewportu = posun casu
  - hover = tooltip (index, speaker, TC)
- Render oddelit na:
  - statickou vrstvu segmentu (prekreslit jen pri zmene dat)
  - dynamickou vrstvu playhead/viewport (throttle)
- Cilem je rychla orientace v dlouhem projektu bez zateze listu.
