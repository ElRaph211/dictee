#!/bin/bash
# Désinstalle Dictee : LaunchAgent, app, et (sur demande) config + modèles + logs.
set -uo pipefail

echo ">> Arrêt et suppression du LaunchAgent"
launchctl bootout "gui/$(id -u)/local.dictee" 2>/dev/null
rm -f "$HOME/Library/LaunchAgents/local.dictee.plist"
pkill -x Dictee 2>/dev/null

echo ">> Suppression de l'app"
rm -rf "$HOME/Applications/Dictee.app"

read -r -p "Supprimer aussi la config, le dictionnaire, l'historique (~/.config/dictee) ? [o/N] " a
if [[ "${a:-}" =~ ^[oOyY]$ ]]; then rm -rf "$HOME/.config/dictee"; echo "   supprimé"; fi
read -r -p "Supprimer les modèles Whisper (~/Library/Application Support/Dictee, ~0,6 Go) ? [o/N] " a
if [[ "${a:-}" =~ ^[oOyY]$ ]]; then rm -rf "$HOME/Library/Application Support/Dictee"; echo "   supprimé"; fi
read -r -p "Supprimer les logs (~/Library/Logs/Dictee) ? [o/N] " a
if [[ "${a:-}" =~ ^[oOyY]$ ]]; then rm -rf "$HOME/Library/Logs/Dictee"; echo "   supprimé"; fi

echo "Désinstallation terminée. (Tu peux retirer Dictee des listes d'autorisations dans Réglages Système si tu veux.)"
