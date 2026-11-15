# OfficinaPDF

Lettore ed editor PDF per uso privato, scritto in Rust. Versione attuale: **0.5.0**.

OfficinaPDF è un fork di [PdfCraft](https://github.com/storytold/pdfcraft) (0.21.1) degli autori di
PdfCraft, distribuito con la stessa licenza: MIT oppure Apache-2.0, a scelta. Le note di copyright
sono in [LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE), [NOTICE](NOTICE) e
[ATTRIBUTION.md](ATTRIBUTION.md). Il README originale è in [docs/README-pdfcraft.md](docs/README-pdfcraft.md).

## Differenze da PdfCraft

- Nome **OfficinaPDF** e nuovo logo (foglio con "OP" e matita, su rosso).
- Eseguibili `officinapdf.exe` e `officinapdf-cli.exe`.
- Impostazioni e file di recupero in cartelle proprie (`OfficinaPDF`), separate da PdfCraft.
- Aggiornamenti dal codice sorgente di PdfCraft, non dai suoi programmi già pronti, che
  sostituirebbero questa versione (vedi sotto).
- Nessun link ad ArtCraft (Discord, sito web) e nessun marchio ArtCraft.
- Interfaccia italiana: i cataloghi di PdfCraft più le frasi proprie di OfficinaPDF.

## OCR

I modelli per il riconoscimento del testo (progetto ocrs, licenza CC-BY-SA-4.0) si scaricano con
`cargo xtask models` in `assets/models/` e, nelle versioni compilate, vanno nella cartella `models`
accanto a `officinapdf.exe`. Leggono l'alfabeto latino senza accenti: OfficinaPDF rimette gli
accenti italiani quando la parola giusta è una sola (`crates/ocr/src/accents.rs`).

## Aggiornamenti da PdfCraft

OfficinaPDF si aggiorna dal codice open source di PdfCraft (`github.com/storytold/pdfcraft`, il
remote `upstream`), su questo computer: scarica le novità, le unisce, compila e installa.

- **Dal programma:** Aiuto > Verifica aggiornamenti. Se PdfCraft ha novità, "Aggiorna ora" apre
  una finestra che fa tutto da sola (circa un'ora) e alla fine riapre OfficinaPDF aggiornato. Lo
  stesso controllo si fa all'avvio (Preferenze lo spegne) e, dopo aver proposto un
  aggiornamento, tace per una settimana.
- **A mano:**

```powershell
pwsh .ggiorna-da-pdfcraft.ps1 -SoloControllo     # ci sono novità?
pwsh .ggiorna-da-pdfcraft.ps1                    # nuova versione in ..\Versioni (0.5.0 -> 0.6.0)
pwsh .ggiorna-da-pdfcraft.ps1 -Installa          # … e la installa
```

Lo script lavora in un ramo di prova e porta il risultato su `main` solo se i test passano.
Prima di unire dà al codice di PdfCraft il nome e la versione di OfficinaPDF
(`packaging/windows/officinapdf-nome.ps1`): così le due parti si scontrano solo dove OfficinaPDF
ha davvero cambiato qualcosa, non a ogni riga che cita il nome. Se PdfCraft ha cambiato proprio
quelle righe, o un test fallisce, si ferma, lo dice e lascia `main` e il programma installato
com'erano; il registro è in `..\Versioniggiornamento-<data>.log`.

Le traduzioni non sono più in questo repository: PdfCraft le tiene in `storytold/craft-i18n`.
`packaging/windows/officinapdf-traduzioni.ps1` le scarica in `..\craft-i18n` (alla versione
scritta in `craft-i18n.rev`), mette il nome OfficinaPDF e aggiunge le righe italiane di
`packaging/windows/officinapdf-it.tsv`; il risultato va a cargo in `CRAFT_I18N_DIR`.

Il programma installato sa dove si trova questa cartella perché la ricorda da quando è stato
compilato: una copia portata su un altro computer dice che lì l'aggiornamento non c'è.

Il commit iniziale (lo zip) è collegato a PdfCraft `13655d0` con `git replace --graft`; il
collegamento è locale a questo repository.

## Compilare

Serve Rust 1.95 o più recente.

```sh
# le traduzioni (senza, l'interfaccia è in inglese); in PowerShell:
#   $env:CRAFT_I18N_DIR = & .\packaging\windows\officinapdf-traduzioni.ps1
cargo run -p pdfcraft -- file.pdf                  # app desktop (debug)
cargo build --release -p pdfcraft -p pdfcraft-cli  # versione ottimizzata in target/release
```

I pacchetti Rust interni mantengono il nome `pdfcraft-*`, così è più semplice recuperare le
correzioni da PdfCraft.

## Installer

```powershell
pwsh packaging/windows/package-officinapdf.ps1 -OutDir "..\Versioni\OfficinaPDF v0.x"
```

Crea `OfficinaPDF-<versione>-x64.msi`, un installer in italiano: menu Start, collegamento sul
desktop, "Apri con" e App predefinite di Windows, "Modifica con OfficinaPDF" e "Unisci file con OfficinaPDF" nel
menu del tasto destro. Crea anche `OfficinaPDF-<versione>-portable.zip`, da usare senza installare (con
`portable.txt` le impostazioni restano in `OfficinaPDFData` accanto al programma). Serve WiX 5 (`dotnet tool install --global wix --version 5.0.2`, oppure `-Wix` con il
percorso di `wix.exe`). I file `officinapdf*.wxs`, `officinapdf-policy.wxi` e
`package-officinapdf.ps1` sono copie di quelli di PdfCraft con nomi, codici e registro propri:
così OfficinaPDF si installa accanto a un PdfCraft ufficiale e i merge restano senza conflitti.

## Versioni

Ogni versione compilata va in una cartella propria in `..\Versioni\`.
