#!/bin/bash
# ========================================================
# Auto-setup TP1gentoo
# ========================================================

set -euo pipefail

REPO_URL="https://github.com/TonyOwen7/TP1gentoo.git"
DIR="TP1gentoo"

echo "==== 🔄 Nettoyage éventuel ===="
if [ -d "$DIR" ]; then
  echo "📂 Dossier $DIR existe déjà, suppression..."
  rm -rf "$DIR"
else
  echo "✅ Aucun dossier $DIR à supprimer."
fi

echo "==== 📥 Clonage du dépôt ===="
git clone "$REPO_URL"

echo "==== ⚙️ Préparation du script ===="
chmod +x "./$DIR/script*.sh"

echo "==== 🚀 Exécution du script ===="
"./$DIR/script3.0.sh"
