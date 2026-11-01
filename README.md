# OfficinaPDF

Lettore ed editor PDF per uso privato, scritto in Rust. Versione attuale: **0.2.0**.

OfficinaPDF è un fork di [PdfCraft](https://github.com/storytold/pdfcraft) (0.16.1) degli autori di
PdfCraft, distribuito con la stessa licenza: MIT oppure Apache-2.0, a scelta. Le note di copyright
sono in [LICENSE-MIT](LICENSE-MIT), [LICENSE-APACHE](LICENSE-APACHE), [NOTICE](NOTICE) e
[ATTRIBUTION.md](ATTRIBUTION.md). Il README originale è in [docs/README-pdfcraft.md](docs/README-pdfcraft.md).

## Differenze da PdfCraft

- Nome **OfficinaPDF** e nuovo logo (foglio con "OP" e matita, su rosso).
- Eseguibili `officinapdf.exe` e `officinapdf-cli.exe`.
- Impostazioni e file di recupero in cartelle proprie (`OfficinaPDF`), separate da PdfCraft.
- Nessun controllo degli aggiornamenti: gli aggiornamenti di PdfCraft sostituirebbero questa versione.
- Nessun link ad ArtCraft (Discord, sito web) e nessun marchio ArtCraft.
- Interfaccia italiana completa.

## OCR

I modelli per il riconoscimento del testo (progetto ocrs, licenza CC-BY-SA-4.0) si scaricano con
`cargo xtask models` in `assets/models/` e, nelle versioni compilate, vanno nella cartella `models`
accanto a `officinapdf.exe`. Leggono l'alfabeto latino senza accenti: le lettere accentate
italiane (à, è, ì, ò, ù) vengono perse.

## Aggiornamenti da PdfCraft

```sh
git fetch upstream main
git merge upstream/main   # poi riapplicare il nome OfficinaPDF ai file cambiati e rifare i test
```

Il commit iniziale (lo zip) è collegato a PdfCraft `13655d0` con `git replace --graft`; il
collegamento è locale a questo repository.

## Compilare

Serve Rust 1.95 o più recente.

```sh
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
desktop, "Apri con" e App predefinite di Windows, "Modifica con OfficinaPDF" nel menu del tasto
destro. Serve WiX 5 (`dotnet tool install --global wix --version 5.0.2`, oppure `-Wix` con il
percorso di `wix.exe`). I file `officinapdf*.wxs`, `officinapdf-policy.wxi` e
`package-officinapdf.ps1` sono copie di quelli di PdfCraft con nomi, codici e registro propri:
così OfficinaPDF si installa accanto a un PdfCraft ufficiale e i merge restano senza conflitti.

## Versioni

Ogni versione compilata va in una cartella propria in `..\Versioni\`.
