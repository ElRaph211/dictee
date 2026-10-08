#!/bin/bash
# Installe Dictee : copie l'app dans ~/Applications, télécharge le modèle si besoin,
# crée les fichiers de config (sans écraser l'existant) et le LaunchAgent (démarrage auto + relance si crash).
set -euo pipefail
cd "$(dirname "$0")"

APP_SRC="build/Dictee.app"
[ -d "$APP_SRC" ] || APP_SRC="Dictee.app"   # cas du zip installable (package.sh)
if [ ! -d "$APP_SRC" ]; then
  echo "Dictee.app introuvable. Lance d'abord ./build.sh (ou dézippe le paquet complet)."
  exit 1
fi

APP_DIR="$HOME/Applications"
APP="$APP_DIR/Dictee.app"
mkdir -p "$APP_DIR"

echo ">> 0/5 Identité de signature stable"
# Sans elle, chaque build change l'empreinte et macOS oublie Accessibilité / Surveillance de l'entrée.
./scripts/make-signing-cert.sh
SIGN_ID="Dictee Local Signing"

echo ">> 1/5 Copie de l'app dans $APP"
OLD_REQ=$(codesign -dr - "$APP" 2>&1 | grep designated || true)
# on arrête l'app si elle tourne
launchctl bootout "gui/$(id -u)/local.dictee" 2>/dev/null || true
pkill -x Dictee 2>/dev/null || true
rm -rf "$APP"
# ditto sans attributs étendus (évite le « detritus » iCloud/Finder), puis signature avec l'identité locale
ditto --noextattr --noqtn "$APP_SRC" "$APP"
xattr -cr "$APP"
codesign -s "$SIGN_ID" --force --deep "$APP" 2>&1 | grep -v "replacing existing signature" || true
codesign --verify --strict "$APP" && echo "   signature OK ($SIGN_ID)"
NEW_REQ=$(codesign -dr - "$APP" 2>&1 | grep designated || true)
PERMS_RESET=0
if [ -n "$OLD_REQ" ] && [ "$OLD_REQ" != "$NEW_REQ" ]; then
  PERMS_RESET=1
  echo "   ATTENTION : l'empreinte de signature a changé (ancienne app signée ad hoc)."
  echo "   macOS va oublier les autorisations : je les remets à zéro pour éviter des cases cochées mais inactives."
  for svc in Accessibility ListenEvent Microphone; do tccutil reset "$svc" local.dictee.app >/dev/null 2>&1 || true; done
  echo "   → à re-cocher une dernière fois (Microphone, Accessibilité, Surveillance de l'entrée)."
  echo "   Avec l'identité « $SIGN_ID », les prochaines mises à jour ne redemanderont plus rien."
fi

echo ">> 2/5 Modèle Whisper"
./scripts/download-model.sh

echo ">> 3/5 Fichiers de config (~/.config/dictee)"
CFG="$HOME/.config/dictee"
mkdir -p "$CFG"
for f in config.json dictionary.json snippets.json; do
  if [ ! -f "$CFG/$f" ]; then
    cp "defaults/$f" "$CFG/$f" 2>/dev/null || cp "$APP/Contents/Resources/defaults/$f" "$CFG/$f"
    echo "   créé : $CFG/$f"
  else
    echo "   conservé : $CFG/$f"
  fi
done
mkdir -p "$HOME/Library/Logs/Dictee"

echo ">> 4/5 LaunchAgent (démarrage auto + relance si crash)"
LA="$HOME/Library/LaunchAgents/local.dictee.plist"
mkdir -p "$HOME/Library/LaunchAgents"
sed -e "s|__APP_PATH__|$APP|g" -e "s|__HOME__|$HOME|g" scripts/local.dictee.plist > "$LA"
launchctl bootstrap "gui/$(id -u)" "$LA" 2>/dev/null || launchctl kickstart -k "gui/$(id -u)/local.dictee"

echo ">> 5/5 Vérification"
[ "$PERMS_RESET" = 1 ] && echo "   (autorisations remises à zéro : l'app va afficher la marche à suivre)"
sleep 2
if pgrep -x Dictee >/dev/null; then
  echo "   Dictee tourne (icône micro dans la barre de menus)."
else
  echo "   Dictee ne semble pas lancé : regarde ~/Library/Logs/Dictee/launchd.err.log"
fi

cat <<'EOF'

Dernière étape, à faire une fois À LA MAIN (macOS l'exige) :
  Réglages Système > Confidentialité et sécurité :
    • Microphone                → activer « Dictee »
    • Accessibilité             → activer « Dictee »
    • Surveillance de l'entrée  → activer « Dictee »
  Réglages Système > Clavier :
    • « Appuyer sur la touche 🌐 pour » → « Ne rien faire »
  Et quitter Wispr Flow (conflit sur la touche fn).

Puis : barre de menus > Dictee > Relancer. Maintiens fn et parle.
EOF
