#!/bin/bash
# Produit un zip installable pour un autre Mac Apple Silicon (sans environnement de dev) :
# l'app compilée + install.sh (qui télécharge le modèle au premier lancement) + config générique.
# Aucune donnée personnelle : dictionnaire/snippets de départ vides, aucune clé API.
set -euo pipefail
cd "$(dirname "$0")"

[ -d build/Dictee.app ] || { echo "build/Dictee.app absent : lance d'abord ./build.sh app"; exit 1; }

VERSION=$(plutil -extract CFBundleShortVersionString raw build/Dictee.app/Contents/Info.plist 2>/dev/null || echo "1.0.0")
# on prépare le paquet dans un dossier temporaire HORS iCloud/Desktop :
# le Bureau synchronisé ré-ajoute des attributs Finder qui cassent la signature.
STAGE=$(mktemp -d /tmp/dictee-pkg.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
OUT="$STAGE/Dictee-$VERSION"
rm -f "build/Dictee-$VERSION.zip"
mkdir -p "$OUT/scripts" "$OUT/defaults"

ditto --noextattr --noqtn build/Dictee.app "$OUT/Dictee.app"
xattr -cr "$OUT/Dictee.app"
codesign -s - --force --deep "$OUT/Dictee.app"
cp install.sh uninstall.sh "$OUT/"
cp scripts/download-model.sh scripts/local.dictee.plist "$OUT/scripts/"
cp defaults/config.json defaults/dictionary.json defaults/snippets.json "$OUT/defaults/"
# le paquet embarque les defaults génériques, jamais ~/.config/dictee (dictionnaire perso)

cat > "$OUT/LISEZMOI.txt" <<'EOF'
Dictee — dictée vocale 100 % locale pour Mac Apple Silicon
===========================================================
Installation (Terminal) :
  1. cd dans ce dossier
  2. ./install.sh        (copie l'app, télécharge le modèle ~574 Mo, crée la config)
  3. macOS bloque les apps non notariées : si un message « Dictee ne peut pas être
     ouvert » apparaît, fais clic droit > Ouvrir sur ~/Applications/Dictee.app,
     ou dans le Terminal :  xattr -dr com.apple.quarantine ~/Applications/Dictee.app
  4. Réglages Système > Confidentialité et sécurité : active « Dictee » dans
     Microphone, Accessibilité et Surveillance de l'entrée.
  5. Réglages Système > Clavier > « Appuyer sur la touche 🌐 pour » : « Ne rien faire ».

Utilisation : maintiens fn et parle, relâche pour coller le texte au curseur.
Double-tap fn = mains libres (re-tap pour arrêter). Échap = annuler.
Dictionnaire : icône micro dans la barre de menus > Ouvrir le dictionnaire.
Désinstallation : ./uninstall.sh
EOF

( cd "$STAGE" && ditto -c -k --noextattr --noqtn "Dictee-$VERSION" dictee.zip )
mv "$STAGE/dictee.zip" "build/Dictee-$VERSION.zip"
echo ">> OK : build/Dictee-$VERSION.zip"
du -h "build/Dictee-$VERSION.zip"
