#!/bin/bash
# ========================================================
# Auto-setup TPgentoo
# ========================================================

set -euo pipefail

REPO_URL="https://github.com/TonyOwen7/TP1gentoo.git"
DIR="TP1gentoo"

# Vérification argument
if [ $# -eq 0 ]; then
  echo "❌ Usage: $0 <TP_number|all>"
  exit 1
fi

ARG=$1

echo "==== 🔄 Nettoyage éventuel ===="
if [ -d "$DIR" ]; then
  echo "📂 Dossier $DIR existe déjà, suppression..."
  rm -rf "$DIR"
else
  echo "✅ Aucun dossier $DIR à supprimer."
fi

echo "==== 📥 Clonage du dépôt ===="
git clone "$REPO_URL"

cd "$DIR"

echo "==== ⚙️ Préparation des scripts ===="
chmod +x script_TP*.sh

if [ "$ARG" = "all" ]; then
  echo "==== 🚀 Exécution de tous les TP dans l'ordre ===="
  # On trie par numéro croissant
  for script in $(ls script_TP*.sh | sort -V); do
    echo "➡️ Lancement de $script"
    "./$script"
  done
else
  SCRIPT="script_TP${ARG}.sh"
  if [ -f "$SCRIPT" ]; then
    echo "==== 🚀 Exécution de $SCRIPT ===="
    "./$SCRIPT"
  else
    echo "❌ Script $SCRIPT introuvable."
    exit 1
  fi
fi
