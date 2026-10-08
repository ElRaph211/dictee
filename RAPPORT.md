# Dictee — mesures et état (08/10/2026, Mac M5 16 Go, macOS 26.6.2)

## Choix moteur (mesuré, même clip FR 10-14 s, large-v3-turbo)
| Moteur | Latence (modèle chargé) | Distribution |
|---|---|---|
| mlx-whisper (Python, fp16) | 3,8-4,4 s | venv 760 Mo |
| whisper.cpp Metal, fp16, beam 5 | ~2,2 s | lib statique dans l'app |
| **whisper.cpp q5_0 + flash attn + audio_ctx dynamique + patch réutilisation encodeur (retenu)** | **0,45-0,9 s** | app 1,9 Mo + modèle 574 Mo |

Patch local (`patches/`) : l'encodeur calculé pour la détection de langue est réutilisé pour la
transcription → le mode `auto` coûte comme une langue fixée.

## Vérifié sur cette machine
- 73 tests unitaires OK (`./build/dictee-tests`) : nettoyage, auto-corrections, ponctuation dictée,
  listes, dictionnaire, snippets, styles par app, apprentissage (diff + seuil), config.
- Transcription fichiers FR/EN (voix `say`) : latence ci-dessus, langue auto correcte (fr p=0,995 ;
  en p=0,999), noms propres corrects avec le prompt dictionnaire (ChatGPT, Supabase, Brevo, Vercel...).
- Build `./build.sh` sans erreur ; app signée ad hoc, `codesign --verify --strict` OK.
- `./install.sh` : app dans ~/Applications, LaunchAgent `local.dictee` démarré (state=running,
  jamais sorti en erreur), logs lus dans ~/Library/Logs/Dictee, modèle préchauffé en 0,6-9 s.
- `./package.sh` : zip 1,9 Mo, sans dictionnaire perso ni clé API.
- Passe LLM optionnelle : 1 requête réelle claude-haiku-5-5 OK (clé howseen), désactivée par défaut.

## Non testé (exige les autorisations ou une vraie voix)
- Touche fn (maintien / double-tap / Échap), collage réel, lecture AX du champ, pastille :
  codé et conforme à la doc, mais à valider à la main après les 3 autorisations.
- Apprentissage de bout en bout dans une vraie app (la logique texte est testée unitairement).
- Qualité sur voix réelle (les clips `say` sont synthétiques).
