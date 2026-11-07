#!/bin/zsh
# Pubblica una versione, come Nod:
#   1. ./build.sh --dmg
#   2. release GitHub v<versione> con il DMG e le note prese da CHANGELOG.md (serve `gh auth login`)
#   3. aggiorna version e sha256 del cask, qui e nel clone del tap, e lo pubblica
# Prima: aumenta VERSION e aggiungi in cima a CHANGELOG.md la sezione "## <versione> · <data>".
# Repo (cambiabili): KNOCK_APP_REPO=GGuidotz/knock  KNOCK_TAP_DIR=~/Developer/homebrew-tap
set -euo pipefail
cd "${0:A:h}"
die() { echo "$*" >&2; exit 1; }

APP_REPO=${KNOCK_APP_REPO:-GGuidotz/knock}
TAP_DIR=${KNOCK_TAP_DIR:-$HOME/Developer/homebrew-tap}
VERSION=$(tr -d '[:space:]' < VERSION)
CASK=packaging/homebrew/Casks/knock.rb

command -v gh >/dev/null || die "Serve GitHub CLI: brew install gh && gh auth login"
[ -z "$(git status --porcelain -- .)" ] || die "Ci sono modifiche non salvate in git: fai prima il commit."
gh release view "v$VERSION" --repo "$APP_REPO" >/dev/null 2>&1 && die "La release v$VERSION esiste già: aumenta VERSION."

./build.sh --dmg
DMG="dist/Knock-$VERSION.dmg"
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
section() { awk -v v="$VERSION" '$0 ~ "^## "v" " {f=1; next} /^## / {f=0} f' "$1"; }
# Note della release: in inglese se c'è la versione inglese, poi l'italiano; i gruppi con i nomi delle note di rilascio.
NOTES_IT=$(section CHANGELOG.md | sed -e 's/^### Novità/### New features/' -e 's/^### Miglioramenti/### Improvements/' \
  -e 's/^### Correzioni/### Bug fixes/' -e 's/^### Sicurezza/### Security/' -e 's/^### Problemi noti/### Known issues/')
NOTES_EN=$([ -f CHANGELOG.en.md ] && section CHANGELOG.en.md || true)
if [ -n "$NOTES_EN" ]; then
  NOTES="$NOTES_EN"$'\n\n---\n\n## Italiano\n'"$NOTES_IT"
else
  NOTES="$NOTES_IT"
fi

gh release create "v$VERSION" "$DMG" --repo "$APP_REPO" --title "Knock $VERSION" --notes "$NOTES"

sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
git add "$CASK" && git commit -m "Cask knock $VERSION" -- "$CASK" >/dev/null || true
git push || true

if [ -d "$TAP_DIR/.git" ]; then
  git -C "$TAP_DIR" pull --ff-only
  mkdir -p "$TAP_DIR/Casks"
  cp "$CASK" "$TAP_DIR/Casks/knock.rb"
  git -C "$TAP_DIR" add Casks/knock.rb
  git -C "$TAP_DIR" commit -m "knock $VERSION" >/dev/null
  git -C "$TAP_DIR" push
  echo "Tap aggiornato."
else
  echo "Tap non trovato in $TAP_DIR: copia a mano $CASK in Casks/ del repo homebrew-tap."
fi
echo "Pubblicato Knock $VERSION. Installazione: brew install --cask gguidotz/tap/knock"
