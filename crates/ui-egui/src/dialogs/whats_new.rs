//! OfficinaPDF: Help ▸ What's new. What each OfficinaPDF version brought, newest first. The notes
//! are written in Italian only, like the fork they describe; add a row to [`RELEASES`] with every
//! version.

use egui::RichText;

use crate::theme::{self, Tokens};

/// The lists scroll inside this height.
const LIST_HEIGHT: f32 = 420.0;

/// One OfficinaPDF version: its number, its date and what it brought.
pub struct Release {
    pub version: &'static str,
    pub date: &'static str,
    pub notes: &'static [&'static str],
}

pub const RELEASES: &[Release] = &[
    Release {
        version: "0.4.0",
        date: "novembre 2026",
        notes: &[
            "La versione è scritta accanto al titolo nella pagina iniziale e nel titolo della finestra.",
            "Nuovo sottotitolo della pagina iniziale: \"La tua officina per i PDF: ogni attrezzo a portata di mano.\"",
            "OCR: gli accenti italiani vengono ricostruiti quando la parola giusta è una sola (\"citt?\" e \"citta\" diventano \"città\"). Le parole ambigue, come \"gi?\" (già o giù), restano come lette.",
            "Questa finestra: Aiuto > Novità.",
            "Versione portatile: uno zip da estrarre dove vuoi, anche su una chiavetta USB, con le impostazioni nella cartella del programma.",
            "Script per recuperare da solo gli aggiornamenti di PdfCraft.",
            "Ultime correzioni di PdfCraft.",
        ],
    },
    Release {
        version: "0.3.0",
        date: "novembre 2026",
        notes: &[
            "Installer in italiano (.msi): menu Start, collegamento sul desktop, \"Apri con\" e App predefinite di Windows.",
            "Nel menu del tasto destro: \"Modifica con OfficinaPDF\" sui PDF e \"Crea PDF con OfficinaPDF…\" sulle immagini.",
        ],
    },
    Release {
        version: "0.2.0",
        date: "novembre 2026",
        notes: &[
            "OCR: rende ricercabili e selezionabili le pagine scansionate.",
            "Interfaccia italiana completa.",
            "Correzioni di PdfCraft: salvataggio completo dopo aver eliminato pagine, ombre facoltative ai bordi delle pagine, opzione --two-paged.",
        ],
    },
    Release {
        version: "0.1.0",
        date: "ottobre 2026",
        notes: &[
            "Prima versione di OfficinaPDF, basata su PdfCraft 0.16.1: nuovo nome e nuovo logo.",
            "Impostazioni e file recenti separati da PdfCraft; nessun controllo automatico degli aggiornamenti di PdfCraft.",
        ],
    },
];

/// The dialog's content.
pub fn ui(ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    ui.label(RichText::new(tl!("What's new")).font(theme::semibold(18.0)));
    ui.add_space(8.0);
    egui::ScrollArea::vertical().max_height(LIST_HEIGHT).auto_shrink([false, true]).show(ui, |ui| {
        for release in RELEASES {
            ui.horizontal(|ui| {
                ui.label(RichText::new(format!("OfficinaPDF {}", release.version)).font(theme::semibold(15.0)));
                ui.label(RichText::new(release.date).color(t.text_muted));
            });
            for note in release.notes {
                ui.horizontal_wrapped(|ui| {
                    ui.label("•");
                    ui.label(*note);
                });
            }
            ui.add_space(10.0);
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The newest notes belong to the version being built, so a release can't ship with last
    /// version's list on top.
    #[test]
    fn the_newest_notes_are_for_this_version() {
        assert_eq!(RELEASES.first().map(|r| r.version), Some(env!("CARGO_PKG_VERSION")));
    }
}
