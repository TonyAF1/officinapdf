//! OfficinaPDF: Help ▸ What's new. What each OfficinaPDF version brought, newest first. The notes
//! are written in Italian only, like the fork they describe; add a row to [`RELEASES`] with every
//! version (`aggiorna-da-pdfcraft.ps1` adds one by itself).
//!
//! Above the notes, Help ▸ Check for updates: whether PdfCraft's open-source code has something
//! new, and the button that makes and installs the next OfficinaPDF from it (`update`).

use egui::RichText;

use crate::theme::{self, Tokens};
use crate::{Dialog, PdfCraftApp, widgets};

#[cfg(not(target_arch = "wasm32"))]
mod update;

/// The lists scroll inside this height.
const LIST_HEIGHT: f32 = 420.0;

/// One OfficinaPDF version: its number, its date and what it brought.
pub struct Release {
    pub version: &'static str,
    pub date: &'static str,
    pub notes: &'static [&'static str],
}

pub const RELEASES: &[Release] = &[
    Release { version: "0.6.0", date: "novembre 2026", notes: &["Aggiornamento a PdfCraft 0.21.1: 13 modifiche tra correzioni e novità."] },
    Release {
        version: "0.5.0",
        date: "novembre 2026",
        notes: &[
            "Aggiornamenti direttamente dal codice open source di PdfCraft: Aiuto > Verifica aggiornamenti controlla se ci sono novità e, con \"Aggiorna ora\", prepara e installa da solo la nuova versione di OfficinaPDF. Il controllo si fa anche all'avvio (si può spegnere nelle Preferenze) e, dopo aver proposto un aggiornamento, non lo ripropone per una settimana.",
            "Base aggiornata da PdfCraft 0.16 a PdfCraft 0.21.1: 2636 modifiche, tra cui circa 400 correzioni.",
            "Vista divisa: due riquadri affiancati, con lo stesso documento o con due documenti diversi.",
            "Pagina iniziale: puoi fissare gli strumenti che usi di più.",
            "Stampa: formati di carta personalizzati, ricordati per ogni stampante, e stampa di un'area selezionata.",
            "OCR: può usare anche Tesseract, se è installato sul computer. La correzione degli accenti italiani resta per il motore incorporato.",
            "Segnalibri da esportare, importare e copiare; ricerca degli IBAN in Cerca e oscura; barra degli strumenti rapidi personalizzabile.",
            "Nel menu del tasto destro dei PDF: \"Unisci file con OfficinaPDF\".",
            "Traduzione italiana: ora viene dai cataloghi di PdfCraft, più completi, con le frasi proprie di OfficinaPDF.",
        ],
    },
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

impl PdfCraftApp {
    /// The desktop app turns on the updates from PdfCraft's source: Help ▸ Check for updates, and
    /// the check at start (which the preference "Check for updates when OfficinaPDF starts" can
    /// still turn off). Tests never call this, so they never run git.
    #[cfg(not(target_arch = "wasm32"))]
    pub fn set_source_update_check(&mut self) {
        update::enable();
    }
}

/// Help ▸ Check for updates: ask whether PdfCraft has something new and show the answer.
pub(crate) fn check_for_updates(app: &mut PdfCraftApp) {
    #[cfg(not(target_arch = "wasm32"))]
    if update::enabled() {
        update::check_now();
        app.dialog = Some(Dialog::WhatsNew);
        return;
    }
    // Not the desktop app (a test, the web build): PdfCraft's own check, which asks only the
    // source it was given.
    app.check_for_updates();
}

/// Each frame: the check at start, which opens this window when PdfCraft has something new.
pub(super) fn poll(app: &mut PdfCraftApp) {
    #[cfg(not(target_arch = "wasm32"))]
    {
        let settings = crate::portable::data_dir().map(std::path::Path::to_path_buf).or_else(|| eframe::storage_dir("OfficinaPDF"));
        if update::poll(app.update_check_at_start, settings.as_deref()) && app.dialog.is_none() {
            app.dialog = Some(Dialog::WhatsNew);
        }
        // The answer comes from another thread: look again soon, even with no input.
        if update::status() == update::Status::Checking
            && let Some(ctx) = &app.ctx
        {
            ctx.request_repaint_after(std::time::Duration::from_millis(300));
        }
    }
    #[cfg(target_arch = "wasm32")]
    let _ = app;
}

/// The update panel: what the check found, and the button for what can be done next.
#[cfg(not(target_arch = "wasm32"))]
fn update_ui(ui: &mut egui::Ui, t: &Tokens) {
    use update::Status;
    let status = update::status();
    egui::Frame::NONE
        .fill(t.card)
        .stroke(egui::Stroke::new(1.0, t.border))
        .corner_radius(egui::CornerRadius::same(10))
        .inner_margin(egui::Margin::same(12))
        .show(ui, |ui| {
            ui.set_width(ui.available_width());
            ui.label(RichText::new("Aggiornamenti da PdfCraft").font(theme::semibold(15.0)));
            ui.add_space(4.0);
            let (text, button) = match &status {
                Status::Idle => ("OfficinaPDF prende le novità direttamente dal codice open source di PdfCraft.".to_owned(), Some("Verifica aggiornamenti")),
                Status::Checking => ("Controllo le novità di PdfCraft…".to_owned(), None),
                Status::UpToDate => ("OfficinaPDF ha già tutte le novità di PdfCraft.".to_owned(), Some("Verifica di nuovo")),
                Status::Available => (
                    "PdfCraft ha pubblicato delle novità. \"Aggiorna ora\" le scarica, prepara la nuova versione di OfficinaPDF e la installa: ci vuole \
                     circa un'ora e intanto puoi continuare a lavorare. Alla fine OfficinaPDF si chiude e si riapre aggiornato."
                        .to_owned(),
                    Some("Aggiorna ora"),
                ),
                Status::Started => (
                    "Aggiornamento avviato in una finestra a parte: lasciala aperta. Alla fine OfficinaPDF si chiude e si riapre aggiornato. Se qualcosa \
                     non va, la finestra lo dice e OfficinaPDF resta com'è."
                        .to_owned(),
                    None,
                ),
                Status::NoSource => (
                    "Questa copia di OfficinaPDF non trova la cartella del suo codice sorgente: l'aggiornamento automatico funziona solo sul computer \
                     dove OfficinaPDF viene preparato."
                        .to_owned(),
                    None,
                ),
                Status::Failed(why) => (format!("Non riesco a controllare gli aggiornamenti: {why}."), Some("Riprova")),
            };
            ui.horizontal_wrapped(|ui| {
                if status == Status::Checking {
                    ui.spinner();
                    ui.ctx().request_repaint_after(std::time::Duration::from_millis(200));
                }
                ui.label(RichText::new(text).color(t.text_muted));
            });
            if let Some(label) = button {
                ui.add_space(8.0);
                let primary = status == Status::Available;
                if widgets::pill_button(ui, label, primary).clicked() {
                    if primary { update::start() } else { update::check_now() }
                }
            }
        });
    ui.add_space(12.0);
}

/// The dialog's content.
pub fn ui(ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    ui.label(RichText::new(tl!("What's new")).font(theme::semibold(18.0)));
    ui.add_space(8.0);
    #[cfg(not(target_arch = "wasm32"))]
    update_ui(ui, &t);
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
