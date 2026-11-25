# DONNA — Tests (ohne Bildschirm)

## Status
✅ Eingerichtet am 25.11.2026 — 54 Tests, alle grün (`xcodebuild test`, ~1 Min).
Hinweis: Xcode hatte das Test-Target zunächst als **visionOS** angelegt (`SDKROOT = xros`) →
„Could not find test host … Debug-xros". Auf `SDKROOT = auto`, iOS + macOS umgestellt.

## Einmalig einrichten (erledigt — nur zur Referenz)
1. `DONNA.xcodeproj` öffnen → **File → New → Target… → macOS → Unit Testing Bundle**
2. Product Name: **`DONNATests`**, Target to be Tested: **DONNA**, Language Swift, Testing System **XCTest** → Finish
3. Xcode legt einen Ordner `DONNATests` mit einer Beispieldatei an — die Beispieldatei löschen.
   Den vorhandenen Ordner `DONNA/DONNATests/` (mit `CoreLogicTests.swift`, `ScienceEngineTests.swift`)
   per Drag & Drop als **Folder** (blaues Symbol) zum Target `DONNATests` hinzufügen, falls Xcode ihn nicht selbst nimmt.
4. Einmal **⌘U** drücken. Danach kann Claude alles per Terminal ausführen.

## Ausführen
```bash
cd ~/Developer/DONNAv1/DONNA
xcodebuild test -scheme DONNA -destination 'platform=macOS' 2>&1 | grep -E "Test Case|error:|Executed|TEST" | tail -40
```

## Was abgedeckt ist (`CoreLogicTests.swift`, In-Memory-Datenbank — echte Daten bleiben unberührt)
- Undo: Erstellen und Löschen rückgängig, Chat-Nachrichten überschreiben das Undo nicht
- Serientermine: 12 Wochen erzeugt, „diesen und alle folgenden" beendet die Serie, keine Neu-Erzeugung, Undo
- Schlafschutz gilt jede Nacht (nicht nur die Anlage-Nacht)
- Routinen werden 30 Tage vorrätig gehalten, ohne doppelte Tage
- Erholungstag macht heutige Routinen optional, Undo stellt sie wieder her
- Spalten-Layout überlappender Termine
- „Ändern"-Editor: Felder bleiben erhalten, Ende vor Beginn wird korrigiert

`ScienceEngineTests.swift` stammt aus V1 und wurde nie gebaut — falls es nach dem Einrichten nicht kompiliert, ist das der erste Fix.

## Visuelle Gesamtprüfung (später, mit mehr Nutzungslimit)
Per Bildschirmfreigabe alles durchklicken, inkl. Randfälle: leere Datenbank, viele Termine an einem Tag,
Serien über Monatsgrenzen, Themenwechsel in jedem Tab, iPhone-Layout, Gemini offline / ohne Schlüssel.
