#!/bin/bash
# Télécharge le modèle Whisper large-v3-turbo quantifié q5_0 (~574 Mo) depuis Hugging Face
# (dépôt officiel ggerganov/whisper.cpp) vers ~/Library/Application Support/Dictee/models.
set -euo pipefail
MODEL="${1:-ggml-large-v3-turbo-q5_0.bin}"
DIR="$HOME/Library/Application Support/Dictee/models"
URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL"
mkdir -p "$DIR"
if [ -s "$DIR/$MODEL" ]; then
  echo "Modèle déjà présent : $DIR/$MODEL"
  exit 0
fi
echo "Téléchargement de $MODEL (~574 Mo pour q5_0)…"
curl -L --fail --progress-bar -o "$DIR/$MODEL.part" "$URL"
mv "$DIR/$MODEL.part" "$DIR/$MODEL"
echo "OK : $DIR/$MODEL"
