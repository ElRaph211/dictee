# Dictee

Dictée vocale pour macOS, 100 % locale, gratuite et sans limite. Équivalent perso de Wispr Flow : tu maintiens **fn**, tu parles, tu relâches, le texte propre est collé au curseur dans n'importe quelle app (Slack, navigateur, Terminal, Notes…).

- Transcription : **Whisper large-v3-turbo** (whisper.cpp + Metal), modèle gardé en mémoire. ~0,5 s de latence pour 10 s de parole sur M5. Détection auto FR/EN.
- Nettoyage **local et déterministe** : « euh/hum/bah », auto-corrections (« non pardon », « je veux dire »), ponctuation dictée (« point d'interrogation », « nouvelle ligne »), listes (« premièrement… »), typographie FR/EN.
- **Dictionnaire personnel qui apprend** : si tu corriges un mot après un collage, la correction est détectée (Accessibilité) et ajoutée au dictionnaire après 2 observations.
- Snippets vocaux, style par app (ex. Terminal sans majuscule), historique 50 dictées, icône barre de menus, pastille de niveau audio, démarrage automatique, presse-papiers préservé.
- Rien ne sort du Mac. Option (désactivée par défaut) : passe de polish via l'API Anthropic.

## Installation (5 étapes)

1. **Builder** (une fois, ~5 min la première fois) :
   ```bash
   cd ~/Desktop/Dictee && ./build.sh
   ```
2. **Installer** (copie dans `~/Applications`, télécharge le modèle ~574 Mo si absent, crée la config, LaunchAgent) :
   ```bash
   ./install.sh
   ```
3. **Autorisations** — Réglages Système > **Confidentialité et sécurité**, active « Dictee » dans :
   - **Microphone**
   - **Accessibilité**
   - **Surveillance de l'entrée** (Input Monitoring)

   (Si « Dictee » n'apparaît pas dans une liste : bouton « + » puis choisir `~/Applications/Dictee.app`.)
4. **Clavier** — Réglages Système > **Clavier** > « Appuyer sur la touche 🌐 pour » → **« Ne rien faire »**. Et **quitter Wispr Flow** (il écoute aussi fn).
5. Barre de menus > icône micro > **Relancer**. C'est prêt.

> Après chaque mise à jour (`./build.sh && ./install.sh`), macOS peut redemander les autorisations : la signature ad hoc change à chaque build. Re-coche les 3 cases si l'icône affiche une erreur.

## Utilisation

| Geste | Effet |
|---|---|
| Maintenir **fn** | Enregistre tant que c'est tenu ; relâcher = transcrire + coller |
| **Double-tap fn** | Mode mains libres ; re-tap fn pour arrêter |
| **Échap** | Annule la dictée en cours |
| « point d'interrogation », « nouvelle ligne », « nouveau paragraphe » | Ponctuation dictée |
| « premièrement… deuxièmement… » ou « tiret… tiret… » | Liste formatée |
| « mardi, non pardon, mercredi » | Garde « mercredi » |

Pastille en bas de l'écran : vert = écoute, orange = mains libres, bleu = transcription.

## Ajouter un mot ou une règle

Barre de menus > **Ouvrir le dictionnaire** (fichier `~/.config/dictee/dictionary.json`) :

```json
{
  "words": ["Howseen", "PostHog", "Raphaël"],
  "replacements": { "jipitou": "GPT" },
  "learned": {}
}
```

- `words` : casse imposée partout + injectés dans le prompt Whisper (meilleure reconnaissance).
- `replacements` : ce qui est entendu → ce qui est écrit (insensible casse/accents, mots entiers).
- `learned` : rempli automatiquement par l'apprentissage.

```json
```

La sauvegarde du fichier recharge l'app automatiquement. L'apprentissage auto : après un collage, le champ est relu ~8 s plus tard ; une correction vue **2 fois** entre au dictionnaire (notification). Réglable dans `config.json` (`learning.threshold`, `learning.delay_seconds`).

## Fichiers de config (`~/.config/dictee/`)

| Fichier | Rôle |
|---|---|
| `config.json` | Modèle, langue (`"auto"`/`"fr"`/`"en"`), sons, micro, styles par app, apprentissage, nettoyage, LLM |
| `dictionary.json` | Mots, remplacements, règles apprises |
| `snippets.json` | `{"mon lien calendrier": "https://cal.com/..."}` — dire la phrase insère le texte |
| `history.json` | 50 dernières dictées (aussi dans le menu, clic = copier) |

Style par app (clé = bundle id, visible dans les logs à chaque dictée) :

```json
"app_styles": {
  "default": {},
  "com.apple.Terminal": { "capitalize_first": false, "trailing_punctuation": false }
}
```

Ponctuation dictée étendue (« virgule », « point », « deux points ») : `"cleaning": { "spoken_punctuation_extended": true }`.

### Passe LLM optionnelle (désactivée par défaut, jamais requise)

Dans `config.json` : `"llm": { "enabled": true, "model": "claude-haiku-5-5", "env_file": "~/.config/howseen/anthropic.env" }`. Le fichier env contient `ANTHROPIC_API_KEY=...`. Aucune clé n'est embarquée dans l'app ni dans le paquet.

## Installer sur un autre Mac (Apple Silicon, sans environnement dev)

1. Ici : `./package.sh` → `build/Dictee-1.0.0.zip` (app + installeur + config générique vide ; **ton** dictionnaire perso reste chez toi, aucune clé API).
2. Envoyer le zip. Sur l'autre Mac : dézipper, puis dans le Terminal :
   ```bash
   cd ~/Downloads/Dictee-1.0.0 && ./install.sh
   ```
   (`install.sh` télécharge le modèle ~574 Mo au premier lancement.)
3. L'app est signée **ad hoc** (pas notariée) : si macOS affiche « Dictee ne peut pas être ouvert », faire **clic droit > Ouvrir** sur `~/Applications/Dictee.app`, ou :
   ```bash
   xattr -dr com.apple.quarantine ~/Applications/Dictee.app
   ```
4. Donner les 3 autorisations + réglage clavier 🌐 (étapes 3–4 ci-dessus). Détail dans le `LISEZMOI.txt` du zip.

## Scripts

| Script | Rôle |
|---|---|
| `./build.sh [test\|cli\|app\|all]` | Compile whisper.cpp (Metal) + tests + CLI + app signée ad hoc |
| `./install.sh` | Installe dans `~/Applications`, modèle, config, LaunchAgent (`local.dictee`, relance auto si crash) |
| `./uninstall.sh` | Retire tout (demande avant d'effacer config/modèles/logs) |
| `./package.sh` | Zip installable pour un autre Mac |
| `./build/dictee-cli fichier.wav [--lang auto] [--raw] [--app bundle.id]` | Transcrit un fichier (debug/benchmark) |
| `./build/dictee-tests` | 73 tests unitaires (nettoyage, dictionnaire, apprentissage, config) |

## Dépannage

- **Rien ne se passe sur fn** : vérifier les 3 autorisations (menu > « Vérifier les autorisations… »), le réglage 🌐, et que Wispr Flow est quitté. Puis menu > Relancer.
- **Logs** : `~/Library/Logs/Dictee/` (`dictee.log` + sorties launchd). Chaque dictée y est tracée avec sa latence.
- **Modèle** : `~/Library/Application Support/Dictee/models/`. Pour la version non quantifiée (un peu plus précise, ~1,6 Go) : `./scripts/download-model.sh ggml-large-v3-turbo.bin` puis `"model": "ggml-large-v3-turbo.bin"` dans config.json.
- L'app relit le dossier `~/.config/dictee` à chaque modification : pas besoin de relancer après un changement de config.

## Architecture (pour le dev)

- `Sources/Core` : pur Swift testable — config, dictionnaire (`PhraseMatcher` insensible casse/accents), nettoyage (`Cleaner`), apprentissage (`Learner`, diff LCS ancré + seuil), pipeline, moteur whisper.cpp (`WhisperEngine`).
- `Sources/App` : barre de menus, CGEventTap fn (`HotkeyMonitor`), micro (`Recorder`), collage + lecture AX (`Paster`), pastille (`Overlay`).
- `vendor/whisper.cpp` : cloné par `build.sh` depuis le GitHub officiel, compilé en statique avec Metal. `patches/` contient un patch local : l'encodeur calculé pour la détection de langue est réutilisé pour la transcription (≈ 2× plus rapide en mode auto).
- Choix moteur : whisper.cpp (lib C statique dans l'app, ~0,45–0,7 s pour 10–14 s d'audio, flash attention, `audio_ctx` dynamique) plutôt que mlx-whisper (~3,8 s pour 10 s + venv Python de 760 Mo à distribuer). Mesures dans `RAPPORT.md`.
