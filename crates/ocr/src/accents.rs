//! OfficinaPDF: Italian accents for recognised words.
//!
//! The recognition model has no accented letters, so an Italian "città" comes back either as
//! "citt?" (the model's `?` for a letter it doesn't know) or as "citta" (the accent dropped).
//! [`restore`] puts the accent back, but only when the answer is not a guess:
//!
//! - a `?` inside or at the end of a word is tried as each accented vowel, and kept only when
//!   exactly one of them makes a word of [`ACCENTED`] ("Perch?" → "Perché", "caff?" → "caffè");
//! - a word written without its accent is changed only when it is one of [`SAFE`], words whose
//!   unaccented spelling is not itself an Italian word ("citta" → "città", "piu" → "più"; never
//!   "e", "la" or "pero"-like pairs where both spellings exist, except the few listed);
//! - an apostrophe written for the accent, as in capitals ("CITTA'"), becomes the accent.
//!
//! Anything else is left exactly as recognised. The word lists are written for OfficinaPDF.

/// Accented vowels an Italian word can end in (or carry), in the order they are tried.
const VOWELS: &[char] = &['à', 'è', 'é', 'ì', 'ò', 'ù'];

/// Italian words written with an accent. Used to resolve a `?` in a recognised word.
#[rustfmt::skip]
pub const ACCENTED: &[&str] = &[
    // Short words, adverbs and conjunctions.
    "è", "é", "già", "più", "può", "però", "ciò", "perciò", "così", "cioè", "là", "lì", "giù", "sì", "sé", "né", "dà", "tè",
    "dì", "perché", "poiché", "benché", "affinché", "finché", "sicché", "anziché", "nonché", "purché", "giacché",
    "cosicché", "granché", "lassù", "laggiù", "quaggiù", "quassù", "costì", "colà", "ahimè", "ohimè", "mercé",
    // Days of the week.
    "lunedì", "martedì", "mercoledì", "giovedì", "venerdì",
    // Nouns.
    "caffè", "tribù", "virtù", "gioventù", "schiavitù", "servitù", "menù", "tabù", "bambù", "ragù", "falò", "oblò",
    "comò", "bordò", "papà", "babbà", "sofà", "gilè", "bebè", "purè", "canapè", "karatè",
    "città", "qualità", "quantità", "età", "verità", "libertà", "società", "università", "attività", "possibilità",
    "necessità", "novità", "realtà", "metà", "unità", "comunità", "capacità", "difficoltà", "volontà", "identità",
    "priorità", "proprietà", "responsabilità", "opportunità", "autorità", "facoltà", "felicità", "velocità",
    "pubblicità", "specialità", "umanità", "varietà", "validità", "maturità", "nazionalità", "normalità", "utilità",
    "eternità", "gravità", "intensità", "densità", "curiosità", "dignità", "semplicità", "complessità", "continuità",
    "disponibilità", "affidabilità", "sostenibilità", "visibilità", "stabilità", "mobilità", "abilità", "fedeltà",
    "lealtà", "bontà", "beltà", "carità", "civiltà", "crudeltà", "onestà", "povertà", "sanità", "santità", "serenità",
    "solidarietà", "totalità", "tranquillità", "umiltà", "vanità", "viltà", "località", "modalità", "mentalità",
    "funzionalità", "formalità", "finalità", "fiscalità", "criminalità", "legalità", "legittimità", "festività",
    "produttività", "competitività", "creatività", "sensibilità", "flessibilità", "compatibilità", "conformità",
    "contabilità", "entità", "enormità", "eredità", "estremità", "integrità", "irregolarità", "obesità", "ostilità",
    "parità", "particolarità", "personalità", "popolarità", "precarietà", "pietà", "regolarità", "rarità", "rapidità",
    "sobrietà", "sincerità", "singolarità", "specificità", "tonalità", "umidità", "unicità", "volgarità", "castità",
    "oscurità", "maestà", "potestà", "podestà", "sovranità", "fertilità", "fragilità", "immunità", "infermità",
    "ingenuità", "intimità", "nobiltà", "ospitalità", "perplessità", "prosperità", "prossimità", "scarsità",
    "severità", "stupidità", "tenacità", "timidità", "unanimità", "vivacità", "avidità", "comodità", "elettricità",
    "eventualità", "facilità", "fatalità", "generalità", "genialità", "gratuità", "impossibilità", "incapacità",
    "infinità", "instabilità", "invalidità", "lucidità", "mortalità", "natalità", "neutralità", "nullità", "opacità",
    "originalità", "periodicità", "pluralità", "positività", "negatività", "praticità", "profondità", "puntualità",
    "quotidianità", "razionalità", "reciprocità", "rigidità", "solidità", "spiritualità", "sterilità", "tossicità",
    "universalità", "veridicità", "vitalità", "vulnerabilità", "agibilità", "ammissibilità", "applicabilità",
    "accessibilità", "imparzialità", "inammissibilità", "irreperibilità", "morosità", "nullità", "obbligatorietà",
    "onerosità", "redditività", "titolarità", "tracciabilità",
    // Future tense: first and third person singular.
    "sarò", "sarà", "farò", "farà", "avrò", "avrà", "potrò", "potrà", "dovrò", "dovrà", "vorrò", "vorrà", "andrò",
    "andrà", "verrò", "verrà", "terrò", "terrà", "darò", "darà", "starò", "starà", "dirò", "dirà", "vedrò", "vedrà",
    "saprò", "saprà", "vivrò", "vivrà", "rimarrò", "rimarrà", "parlerò", "parlerà", "lavorerò", "lavorerà", "pagherò",
    "pagherà", "manderò", "manderà", "chiamerò", "chiamerà", "troverò", "troverà", "porterò", "porterà", "scriverò",
    "scriverà", "leggerò", "leggerà", "prenderò", "prenderà", "metterò", "metterà", "partirò", "partirà", "finirò",
    "finirà", "sentirò", "sentirà", "capirò", "capirà", "aprirò", "aprirà", "uscirò", "uscirà", "tornerò", "tornerà",
    "arriverò", "arriverà", "comincerò", "comincerà", "cercherò", "cercherà", "aspetterò", "aspetterà", "penserò",
    "penserà", "userò", "userà", "proverò", "proverà", "servirà", "conterrà", "otterrà", "scadrà", "seguirà",
    "riceverà", "riceverò", "invierà", "invierò", "costerà", "durerà", "inizierà", "terminerà", "resterà", "entrerà",
    "avverrà", "verrà", "provvederà", "provvederò", "comunicherà", "comunicherò",
    // Past tense (passato remoto): third person singular.
    "parlò", "andò", "tornò", "arrivò", "entrò", "lavorò", "pagò", "mandò", "chiamò", "trovò", "portò", "cominciò",
    "iniziò", "cercò", "aspettò", "pensò", "usò", "provò", "ricordò", "mangiò", "lasciò", "passò", "dichiarò",
    "decretò", "approvò", "firmò", "inviò", "comunicò", "dimostrò", "confermò", "affermò", "rappresentò",
    "determinò", "sbagliò", "studiò", "giocò", "sognò", "salutò", "ordinò", "organizzò", "realizzò", "utilizzò",
    "presentò", "osservò", "notò", "considerò", "accettò", "rifiutò", "cambiò", "creò", "guidò", "aiutò", "invitò",
    "visitò", "viaggiò", "morì", "partì", "finì", "uscì", "capì", "sentì", "dormì", "aprì", "seguì", "colpì",
    "costruì", "offrì", "soffrì", "riuscì", "servì", "scoprì", "apparì", "unì", "fornì", "pulì", "gestì", "spedì",
    "preferì", "definì", "garantì", "sparì", "chiarì", "impedì", "stabilì", "subì", "riunì", "investì", "tradì",
    "avvertì",
];

/// Words of [`ACCENTED`] whose spelling without the accent is not an Italian word of its own, so a
/// recognised "citta" can only have been "città". Verb forms are left out ("parlo" and "parlò",
/// "fini" and "finì" are both words), and so are nouns whose bare spelling is another word
/// ("unita", "stabilita", "eredita", "necessita", "meta", "papa", "menu", "como").
#[rustfmt::skip]
pub const SAFE: &[&str] = &[
    "già", "più", "può", "però", "ciò", "perciò", "così", "cioè", "perché", "poiché", "benché", "affinché", "finché",
    "sicché", "anziché", "nonché", "purché", "giacché", "cosicché", "granché", "lassù", "laggiù", "quaggiù", "quassù",
    "ahimè", "ohimè", "lunedì", "martedì", "mercoledì", "giovedì", "venerdì", "caffè", "tribù", "virtù", "gioventù",
    "schiavitù", "servitù", "tabù", "bambù", "ragù", "falò", "oblò", "città", "qualità", "quantità", "età", "verità",
    "libertà", "società", "università", "attività", "possibilità", "novità", "realtà", "comunità", "capacità",
    "difficoltà", "volontà", "identità", "priorità", "proprietà", "responsabilità", "opportunità", "autorità",
    "facoltà", "velocità", "pubblicità", "specialità", "umanità", "varietà", "validità", "maturità", "nazionalità",
    "normalità", "utilità", "eternità", "intensità", "densità", "curiosità", "dignità", "semplicità", "complessità",
    "continuità", "disponibilità", "affidabilità", "sostenibilità", "visibilità", "fedeltà", "lealtà", "bontà",
    "beltà", "carità", "civiltà", "crudeltà", "povertà", "sanità", "santità", "serenità", "solidarietà", "totalità",
    "tranquillità", "umiltà", "vanità", "località", "modalità", "mentalità", "funzionalità", "formalità",
    "finalità", "fiscalità", "criminalità", "legalità", "legittimità", "festività", "produttività", "competitività",
    "creatività", "sensibilità", "flessibilità", "compatibilità", "conformità", "contabilità", "entità", "enormità",
    "estremità", "integrità", "irregolarità", "obesità", "ostilità", "parità", "particolarità", "personalità",
    "popolarità", "precarietà", "pietà", "regolarità", "rarità", "rapidità", "sobrietà", "sincerità",
    "singolarità", "specificità", "tonalità", "umidità", "unicità", "volgarità", "castità", "oscurità", "maestà",
    "potestà", "podestà", "sovranità", "fertilità", "fragilità", "immunità", "infermità", "ingenuità", "intimità",
    "nobiltà", "ospitalità", "perplessità", "prosperità", "prossimità", "scarsità", "severità", "stupidità",
    "tenacità", "timidità", "unanimità", "vivacità", "avidità", "comodità", "elettricità", "eventualità",
    "fatalità", "generalità", "genialità", "impossibilità", "incapacità", "instabilità", "invalidità",
    "lucidità", "mortalità", "natalità", "neutralità", "nullità", "opacità", "originalità", "periodicità",
    "pluralità", "positività", "negatività", "praticità", "profondità", "puntualità", "quotidianità", "razionalità",
    "reciprocità", "rigidità", "solidità", "spiritualità", "sterilità", "tossicità", "universalità", "veridicità",
    "vitalità", "vulnerabilità", "agibilità", "ammissibilità", "applicabilità", "accessibilità", "imparzialità",
    "inammissibilità", "irreperibilità", "morosità", "obbligatorietà", "onerosità", "redditività", "titolarità",
    "tracciabilità",
];

fn strip_accents(word: &str) -> String {
    word.chars()
        .map(|c| match c {
            'à' => 'a',
            'è' | 'é' => 'e',
            'ì' => 'i',
            'ò' => 'o',
            'ù' => 'u',
            other => other,
        })
        .collect()
}

fn accented(word: &str) -> bool {
    ACCENTED.contains(&word)
}

/// `word` (lower case) written in the case of `like`: all capitals, a capital first letter, or
/// lower case.
fn in_case_of(word: &str, like: &str) -> String {
    let letters: Vec<char> = like.chars().filter(|c| c.is_alphabetic()).collect();
    if letters.len() > 1 && letters.iter().all(|c| c.is_uppercase()) {
        return word.to_uppercase();
    }
    if letters.first().is_some_and(|c| c.is_uppercase()) {
        let mut chars = word.chars();
        return chars.next().map(|first| first.to_uppercase().chain(chars).collect()).unwrap_or_default();
    }
    word.to_owned()
}

/// The one word of `list` that `candidates` names, if there is exactly one.
fn only_one(candidates: impl Iterator<Item = String>, list: fn(&str) -> bool) -> Option<String> {
    let mut found: Vec<String> = candidates.filter(|w| list(w)).collect();
    found.dedup();
    if found.len() == 1 { found.pop() } else { None }
}

/// The accented word a bare spelling stands for, when it can stand for only one ([`SAFE`]).
fn safe(bare: &str) -> Option<String> {
    only_one(SAFE.iter().filter(|w| strip_accents(w) == bare).map(|w| (*w).to_owned()), |_| true)
}

/// `core`, letters with `?` or a final apostrophe, with its accent restored, or `None`.
fn fix(core: &str) -> Option<String> {
    if let Some(cut) = core.trim_end_matches('\'').rfind('\'') {
        // "L'universita": the word after an elided article.
        let (article, word) = core.split_at(cut + 1);
        return fix(word).map(|word| format!("{article}{word}"));
    }
    let lower = core.to_lowercase();
    let marks = lower.chars().filter(|&c| c == '?').count();
    if marks > 0 {
        // One `?` stands for one accented vowel. Two or more are left alone: every combination
        // would have to be tried, and real words rarely carry two accents.
        if marks == 1 && lower.chars().any(char::is_alphabetic) {
            let tries = VOWELS.iter().map(|v| lower.replacen('?', &v.to_string(), 1));
            if let Some(word) = only_one(tries, accented) {
                return Some(in_case_of(&word, core));
            }
        }
        // A `?` after the word is a question mark: the word itself may still lack its accent.
        let stem = lower.trim_end_matches('?');
        if !stem.is_empty() && !stem.contains('?') {
            let word = safe(stem)?;
            let marks = core.get(core.trim_end_matches('?').len()..).unwrap_or_default();
            return Some(format!("{}{marks}", in_case_of(&word, core)));
        }
        return None;
    }
    if let Some(stem) = lower.strip_suffix('\'') {
        // "CITTA'": the apostrophe written for the accent on the last vowel.
        let last = stem.chars().last()?;
        let head = stem.get(..stem.len() - last.len_utf8())?;
        let tries = VOWELS.iter().filter(|v| strip_accents(&v.to_string()) == last.to_string()).map(|v| format!("{head}{v}"));
        return only_one(tries, accented).map(|word| in_case_of(&word, core));
    }
    safe(&lower).map(|word| in_case_of(&word, core))
}

/// `text`, a recognised word with any punctuation around it, with its Italian accent restored
/// when that is certain; otherwise `text` unchanged.
pub fn restore(text: &str) -> String {
    let Some(start) = text.find(|c: char| c.is_alphabetic()) else {
        return text.to_owned();
    };
    let rest = &text[start..];
    let len = rest.find(|c: char| !(c.is_alphabetic() || c == '?' || c == '\'')).unwrap_or(rest.len());
    let core = &rest[..len];
    match fix(core) {
        Some(fixed) => format!("{}{fixed}{}", &text[..start], &rest[len..]),
        None => text.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_question_mark_becomes_the_one_accent_that_makes_a_word() {
        assert_eq!(restore("Perch?"), "Perché");
        assert_eq!(restore("caff?"), "caffè");
        assert_eq!(restore("pi?"), "più");
        assert_eq!(restore("qualit?"), "qualità");
        assert_eq!(restore("citt?,"), "città,");
        assert_eq!(restore("(citt?)"), "(città)");
    }

    #[test]
    fn a_dropped_accent_comes_back_only_where_the_bare_word_is_not_a_word() {
        assert_eq!(restore("citta"), "città");
        assert_eq!(restore("piu"), "più");
        assert_eq!(restore("cosi"), "così");
        assert_eq!(restore("Pero"), "Però");
        assert_eq!(restore("universita."), "università.");
        // Both spellings are words: left as recognised.
        for word in ["e", "la", "li", "se", "si", "ne", "da", "di", "te", "parlo", "fini", "unita", "meta", "papa", "menu"] {
            assert_eq!(restore(word), word);
        }
    }

    #[test]
    fn a_question_mark_after_a_word_stays_a_question_mark() {
        assert_eq!(restore("piu?"), "più?");
        assert_eq!(restore("what?"), "what?");
        assert_eq!(restore("perche?"), "perché?");
    }

    #[test]
    fn ambiguous_marks_are_left_alone() {
        // sarà or sarò; già or giù; sé or sì.
        assert_eq!(restore("sar?"), "sar?");
        assert_eq!(restore("gi?"), "gi?");
        assert_eq!(restore("s?"), "s?");
        assert_eq!(restore("c??"), "c??");
        assert_eq!(restore("?"), "?");
    }

    #[test]
    fn capitals_and_apostrophes() {
        assert_eq!(restore("CITTA'"), "CITTÀ");
        assert_eq!(restore("CITTA"), "CITTÀ");
        assert_eq!(restore("PERCH?"), "PERCHÉ");
        assert_eq!(restore("Universita'"), "Università");
        // "po'" is written with an apostrophe.
        assert_eq!(restore("po'"), "po'");
        assert_eq!(restore("l'"), "l'");
        assert_eq!(restore("L'universita"), "L'università");
        assert_eq!(restore("dell'attivit?."), "dell'attività.");
        assert_eq!(restore("L'UNIVERSITA'"), "L'UNIVERSITÀ");
        assert_eq!(restore("''"), "''");
    }

    #[test]
    fn english_and_other_text_is_untouched() {
        for word in ["Total", "250", "euro,", "invoice:", "€250", "Hello", "Plu", "-", "", "D"] {
            assert_eq!(restore(word), word);
        }
    }

    #[test]
    fn every_safe_word_is_in_the_accented_list_and_its_bare_spelling_is_unique() {
        for word in SAFE {
            assert!(ACCENTED.contains(word), "{word} is safe but not in ACCENTED");
            assert_eq!(safe(&strip_accents(word)).as_deref(), Some(*word), "{word}");
        }
    }

    #[test]
    fn restored_words_fit_the_text_layer_font() {
        for word in ACCENTED {
            assert_eq!(pdfcraft_fonts::first_undrawable(word), None, "{word}");
            assert_eq!(pdfcraft_fonts::first_undrawable(&word.to_uppercase()), None, "{word}");
        }
    }
}
