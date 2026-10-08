import Foundation

// Tests unitaires sans XCTest (les Command Line Tools n'embarquent pas XCTest).
// Lancer : ./build.sh test   (ou build/dictee-tests)

var failures = 0, passes = 0
func check(_ name: String, _ got: String, _ expected: String) {
    if got == expected { passes += 1; print("  ok   \(name)") }
    else { failures += 1; print("  FAIL \(name)\n       attendu : \(expected.debugDescription)\n       obtenu  : \(got.debugDescription)") }
}
func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    if cond { passes += 1; print("  ok   \(name)") } else { failures += 1; print("  FAIL \(name) \(detail)") }
}

Log.mirrorToStderr = false
let cleaner = Cleaner()
func clean(_ s: String, _ lang: String = "fr") -> String { cleaner.clean(s, lang: lang) }

print("== Hésitations")
check("euh au début", clean("Euh, je voulais te dire bonjour."), "Je voulais te dire bonjour.")
check("euh au milieu avec virgules", clean("Je pense, euh, que c'est bien."), "Je pense que c'est bien.")
check("hum / bah", clean("Bah hum, on verra demain."), "On verra demain.")
check("um / uh (EN)", clean("Um, we shipped it, uh, yesterday.", "en"), "We shipped it yesterday.")
check("mot contenant euh intact", clean("Le feu heurte la queue."), "Le feu heurte la queue.")
check("euh avant un point", clean("C'est bien euh. On continue."), "C'est bien. On continue.")

print("== Auto-corrections")
check("non pardon (mot seul)", clean("Envoie le mail mardi, non pardon, mercredi."), "Envoie le mail mercredi.")
check("enfin non avec repère", clean("On part à Lyon, enfin non, à Marseille demain."), "On part à Marseille demain.")
check("je veux dire avec repère", clean("PostHog suit tout, je veux dire Supabase suit les données."), "Supabase suit les données.")
check("I mean avec repère (EN)", clean("PostHog tracks everything, I mean Supabase tracks the data.", "en"), "Supabase tracks the data.")
check("I mean sans repère = juste retiré", clean("We shipped it, I mean, it's live now.", "en"), "We shipped it, it's live now.")
check("ce que je veux dire intact", clean("Ce que je veux dire, c'est que tout va bien."), "Ce que je veux dire, c'est que tout va bien.")
check("scratch that", clean("Call him Tuesday, scratch that, Thursday morning.", "en"), "Call him Thursday morning.")
check("ou plutôt", clean("Mets 3 options ou plutôt 2 options max."), "Mets 2 options max.")

print("== Ponctuation dictée")
check("point d'interrogation", clean("Tout est prêt point d'interrogation"), "Tout est prêt ?")
check("point d'interrogation + suite", clean("Tout est prêt, point d'interrogation, et moi je commence demain."), "Tout est prêt ? Et moi je commence demain.")
check("nouvelle ligne", clean("On a branché Stripe. Nouvelle ligne. Vérifie Vercel."), "On a branché Stripe.\nVérifie Vercel.")
check("à la ligne sans point", clean("Première idée à la ligne deuxième idée."), "Première idée\nDeuxième idée.")
check("nouveau paragraphe", clean("Fin du bloc. Nouveau paragraphe. Suite."), "Fin du bloc.\n\nSuite.")
check("question mark (EN)", clean("Is it live question mark", "en"), "Is it live?")
check("virgule non convertie par défaut", clean("Mets une virgule ici."), "Mets une virgule ici.")
var ext = Cleaner(); ext.config.spokenPunctuationExtended = true
check("virgule (mode étendu)", ext.clean("Envoie-lui le doc virgule puis appelle-le.", lang: "fr"), "Envoie-lui le doc, puis appelle-le.")
check("deux points (mode étendu)", ext.clean("Deux options deux points A ou B.", lang: "fr"), "Deux options : A ou B.")
check("point final seul (mode étendu)", ext.clean("Vérifie Vercel point", lang: "fr"), "Vérifie Vercel.")

print("== Quoi final")
check("quoi en fin de phrase", clean("C'est trop long quoi."), "C'est trop long.")
check("c'est quoi ? intact", clean("C'est quoi ?"), "C'est quoi ?")

print("== Listes")
check("premièrement / deuxièmement", clean("Il faut faire trois choses premièrement vérifier Vercel, deuxièmement envoyer le mail Brevo, troisièmement relancer Théo."),
      "Il faut faire trois choses :\n1. Vérifier Vercel\n2. Envoyer le mail Brevo\n3. Relancer Théo.")
check("liste sans intro", clean("Premièrement, Vercel. Deuxièmement, Brevo."), "1. Vercel.\n2. Brevo.")
check("tirets", clean("Les points tiret Stripe tiret Supabase tiret PostHog."), "Les points :\n- Stripe\n- Supabase\n- PostHog.")
check("un seul premièrement = pas une liste", clean("Premièrement on verra."), "Premièrement on verra.")
check("firstly / secondly (EN)", clean("Two things firstly check Vercel secondly send the email.", "en"), "Two things:\n1. Check Vercel\n2. Send the email.")

print("== Typographie")
check("espace avant ? en FR", clean("Tu viens?"), "Tu viens ?")
check("pas d'espace avant ? en EN", clean("Are you coming ?", "en"), "Are you coming?")
check("double ponctuation", clean("Bonjour,, ça va.."), "Bonjour, ça va.")
check("majuscule après point", clean("c'est fini. on y va."), "C'est fini. On y va.")
check("cal.com intact", clean("Mets le lien cal.com dans le mail."), "Mets le lien cal.com dans le mail.")
check("hallucination silence", clean("Sous-titres réalisés par la communauté d'Amara.org"), "")
check("bruit [Musique]", clean("[Musique]"), "")
check("vide", clean("   "), "")

print("== Dictionnaire")
var dict = PersonalDictionary(words: ["Howseen", "PostHog", "GEO", "Raphaël", "ChatGPT", "Supabase", "Claude Code"],
                              replacements: ["jipitou": "GPT", "chat GPT": "ChatGPT", "post hog": "PostHog", "how seen": "Howseen"])
check("casse imposée", dict.apply(to: "on a branché posthog et howseen."), "on a branché PostHog et Howseen.")
check("accents ignorés", dict.apply(to: "raphael a dit"), "Raphaël a dit")
check("remplacement simple", dict.apply(to: "demande à jipitou"), "demande à GPT")
check("remplacement multi-mots", dict.apply(to: "Chat gpt et Post Hog"), "ChatGPT et PostHog")
check("remplacement avec tiret", dict.apply(to: "post-hog marche"), "PostHog marche")
check("mot entier seulement", dict.apply(to: "le géo-marketing"), "le GEO-marketing")
check("prompt initial", dict.initialPrompt().hasPrefix("Howseen, PostHog, GEO, Raphaël"), dict.initialPrompt())
check("prompt borné", dict.initialPrompt(maxChars: 20), "Howseen, PostHog.")

print("== Snippets")
let snip = Snippets(["mon lien calendrier": "https://cal.com/x/y", "mon adresse email": "moi@example.com"])
check("snippet inline", snip.apply(to: "Voici mon lien calendrier pour demain."), "Voici https://cal.com/x/y pour demain.")
check("snippet seul = valeur brute", snip.apply(to: "Mon lien calendrier."), "https://cal.com/x/y")
check("snippet insensible casse/accents", snip.apply(to: "mon adresse EMAIL"), "moi@example.com")

print("== Style par app")
let term = AppStyle(capitalizeFirst: false, trailingPunctuation: false)
check("terminal : pas de majuscule ni point", Styler.apply("Lance les tests.", style: term), "lance les tests")
check("terminal : nom propre protégé", Styler.apply("Howseen est prêt.", style: term, protectedKeys: dict.knownKeys), "Howseen est prêt")
check("défaut : majuscule + point", Styler.apply("bonjour", style: AppStyle()), "Bonjour.")
check("espace final", Styler.apply("ok", style: AppStyle(trailingSpace: true)), "Ok. ")
var cfg = Config(); cfg.appStyles = ["com.apple.Terminal": term, "default": AppStyle(trailingSpace: true)]
check("config: style fusionné", cfg.style(for: "com.apple.Terminal") == AppStyle(capitalizeFirst: false, trailingPunctuation: false, trailingSpace: true, pasteMethod: "paste"))
check("config: style inconnu = défaut", cfg.style(for: "md.obsidian") == AppStyle(capitalizeFirst: true, trailingPunctuation: true, trailingSpace: true, pasteMethod: "paste"))

print("== Apprentissage")
func corr(_ pasted: String, _ observed: String) -> String {
    Learner.corrections(pasted: pasted, observed: observed, dictionary: dict).map { "\($0.original)→\($0.corrected)" }.joined(separator: " | ")
}
check("mot corrigé", corr("Demande à jipiti de relire.", "Demande à GPT de relire."), "jipiti→GPT")
check("casse corrigée", corr("On utilise brevo pour les mails.", "On utilise Brevo pour les mails."), "brevo→Brevo")
check("deux mots en un", corr("Regarde dans super base ce soir.", "Regarde dans Supabase ce soir."), "super base→Supabase")
check("texte identique = rien", corr("Tout va bien.", "Tout va bien."), "")
check("champ différent = rien", corr("Tout va bien ce matin.", "Bonjour Baptiste, voici la facture."), "")
check("reformulation ignorée", corr("C'est très bien comme ça.", "C'est parfait comme ça."), "")
check("majuscule de début de phrase ignorée", corr("vercel est en prod.", "Vercel est en prod."), "")
check("texte collé dans un long document", corr("Envoie le lien hausine à Baptiste.",
      "Compte rendu du jour. Beaucoup de choses. " + String(repeating: "bla ", count: 200) + "Envoie le lien Howseen à Baptiste. Merci. Autre note."), "hausine→Howseen")
check("règle déjà connue ignorée", corr("Ask jipitou.", "Ask GPT."), "")

var store = LearnedStore()
let c1 = Learner.corrections(pasted: "Demande à jipiti.", observed: "Demande à GPT.", dictionary: dict)
var promoted = Learner.learn(c1, store: &store, dictionary: &dict, threshold: 2)
check("seuil : 1ère fois = candidat", promoted.isEmpty && store.candidates.count == 1)
promoted = Learner.learn(c1, store: &store, dictionary: &dict, threshold: 2)
check("seuil : 2e fois = appris", promoted.count == 1 && dict.learned["jipiti"] == "GPT" && store.candidates.isEmpty)
check("règle apprise appliquée", dict.apply(to: "dis à jipiti"), "dis à GPT")
let c2 = Learner.corrections(pasted: "Branche brevo.", observed: "Branche Brevo.", dictionary: dict)
promoted = Learner.learn(c2, store: &store, dictionary: &dict, threshold: 1)
check("casse apprise → words", promoted.count == 1 && dict.words.contains("Brevo"))

print("== Fichiers de config (DICTEE_HOME temporaire)")
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("dictee-tests-\(UUID().uuidString)")
setenv("DICTEE_HOME", tmp.path, 1)
Paths.ensureDirs()
check("dossiers créés", FileManager.default.fileExists(atPath: Paths.configDir.path))
try! dict.save(); let reloaded = PersonalDictionary.load()
check("dictionnaire aller-retour", reloaded == dict)
try! "{\"language\": \"fr\", \"app_styles\": {\"com.apple.Terminal\": {\"capitalize_first\": false}}}".write(to: Paths.configFile, atomically: true, encoding: .utf8)
let loaded = Config.load()
check("config partielle + défauts", loaded.language == "fr" && loaded.model == "ggml-large-v3-turbo-q5_0.bin" && loaded.style(for: "com.apple.Terminal").capitalizeFirst == false && loaded.llm.enabled == false)
try! "pas du json".write(to: Paths.configFile, atomically: true, encoding: .utf8)
check("config invalide = défauts", Config.load() == Config())
try? FileManager.default.removeItem(at: tmp)

print("\n\(passes) ok, \(failures) échec(s)")
exit(failures == 0 ? 0 : 1)
