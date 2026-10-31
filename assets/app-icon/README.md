# OfficinaPDF app icon

<img src="pdfcraft.svg" alt="OfficinaPDF app icon: a page with OP and a pencil on red" width="128">

A white page with a folded corner, the "OP" monogram and a pencil, on a red rounded tile
(`#C62828`, `viewBox="0 0 128 128"`, `rx=28`). Small sizes use simpler drawings so "OP" stays
legible: 24–32 px drop the pencil's details, 16–20 px drop the pencil.

The files keep their upstream names (`pdfcraft.*`, `hicolor/*/apps/ai.storyteller.pdfcraft.png`) so the
build scripts and packaging need no changes.

| File | What it is |
|---|---|
| `pdfcraft.svg` | the master vector; also the logo in the About dialog |
| `pdfcraft-small.svg` | copy of the master |
| `pdfcraft-1024.png` | 1024 px on Apple's grid (macOS) |
| `pdfcraft.icns` | macOS icon |
| `pdfcraft.ico` | Windows icon (16–256 px), embedded in `officinapdf.exe` by `apps/pdfcraft/build.rs` |
| `hicolor/<n>x<n>/apps/ai.storyteller.pdfcraft.png` | 16–512 px; the 256 px one is the window icon |
| `pdfcraft-document.*` | Windows PDF file icon, unchanged from upstream (see LICENSE-document.txt) |
