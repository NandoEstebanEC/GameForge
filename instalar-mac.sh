#!/usr/bin/env bash
#
# Instalador de Galactic Forge para macOS (Apple Silicon).
#
#   curl -fsSL https://raw.githubusercontent.com/NandoEstebanEC/GameForge/main/instalar-mac.sh | bash
#
# Por que existe: el .app no esta notarizado (eso pide una cuenta Apple Developer de pago), asi
# que si el jugador baja el DMG con el navegador, macOS lo marca con com.apple.quarantine y
# Gatekeeper lo bloquea con un cartel que dice "Apple could not verify ... is free of malware".
# Desde macOS 15 el viejo atajo de clic derecho -> Abrir ya no sirve; hay que ir a Ajustes del
# Sistema. Este script evita todo eso porque la cuarentena la ponen los NAVEGADORES, no curl.
#
# Ojo con lo que eso implica: al no pasar por Gatekeeper, se pierde su verificacion. Por eso el
# script no se salta el control sino que lo reemplaza por uno propio: baja el sha256 publicado en
# el manifest, lo compara contra el ZIP descargado y aborta si no coincide. Sin esa comprobacion
# esto seria un "curl | bash" que instala lo que sea que devuelva la red.
#
# No pide sudo. Si /Applications no es escribible (usuario no admin), instala en ~/Applications.

set -euo pipefail

MANIFEST="https://raw.githubusercontent.com/NandoEstebanEC/GameForge/main/manifest.json"
APP_NAME="GalacticForge.app"

rojo()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info()  { printf '==> %s\n' "$*"; }

trap 'rojo "La instalacion fallo. No se toco la version que ya tuvieras instalada."' ERR

# --- 1) Comprobar que la maquina sirve ----------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || { rojo "Esto es solo para macOS."; exit 1; }
if [[ "$(uname -m)" != "arm64" ]]; then
  rojo "Galactic Forge solo tiene build para Apple Silicon (M1 o posterior)."
  rojo "Esta Mac es Intel: no hay version compatible."
  exit 1
fi

for herramienta in curl ditto shasum codesign; do
  command -v "$herramienta" >/dev/null 2>&1 || { rojo "Falta '$herramienta'."; exit 1; }
done

# --- 2) Leer el manifest ------------------------------------------------------------------------
info "Consultando la version publicada"
JSON="$(curl -fsSL "$MANIFEST")" || { rojo "No se pudo leer el manifest. Revisa tu conexion."; exit 1; }

# Se parsea con sed y no con jq porque jq no viene en todas las versiones de macOS y este script
# tiene que correr en la Mac del jugador sin instalarle nada. El manifest es plano y lo generamos
# nosotros, asi que la forma es estable.
leer_campo() { sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<< "$JSON" | head -1; }

URL="$(leer_campo launcherMacUrl)"
SHA_ESPERADO="$(leer_campo launcherMacSha256)"
BUILD_ID="$(leer_campo launcherMacBuildId)"

if [[ -z "$URL" || -z "$SHA_ESPERADO" ]]; then
  rojo "El manifest no publica una version para macOS todavia."
  exit 1
fi
info "Version: ${BUILD_ID:-desconocida}"

# --- 3) Descargar y verificar -------------------------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; rojo "La instalacion fallo. No se toco la version que ya tuvieras instalada."' ERR
trap 'rm -rf "$TMP"' EXIT

info "Descargando el launcher"
curl -fL --progress-bar -o "$TMP/gf.zip" "$URL"

info "Verificando la descarga"
SHA_REAL="$(shasum -a 256 "$TMP/gf.zip" | cut -d' ' -f1)"
if [[ "$SHA_REAL" != "$SHA_ESPERADO" ]]; then
  rojo "El archivo descargado NO coincide con el publicado."
  rojo "  esperado: $SHA_ESPERADO"
  rojo "  recibido: $SHA_REAL"
  rojo "No se instala nada. Volve a intentar; si sigue fallando, avisanos."
  exit 1
fi

# ditto y no unzip: las firmas de los ensamblados viven en xattrs y unzip las descarta, lo que
# dejaria un .app que el kernel mata al abrir.
info "Extrayendo"
ditto -x -k "$TMP/gf.zip" "$TMP/out"
[[ -d "$TMP/out/$APP_NAME" ]] || { rojo "El paquete descargado no tiene la forma esperada."; exit 1; }

info "Comprobando la firma"
codesign --verify --deep --strict "$TMP/out/$APP_NAME" 2>/dev/null \
  || { rojo "La firma del launcher descargado no es valida. No se instala."; exit 1; }

# --- 4) Instalar --------------------------------------------------------------------------------
DESTINO_DIR="/Applications"
if [[ ! -w "$DESTINO_DIR" ]]; then
  DESTINO_DIR="$HOME/Applications"
  mkdir -p "$DESTINO_DIR"
  info "Sin permiso en /Applications; se instala en $DESTINO_DIR"
fi
DESTINO="$DESTINO_DIR/$APP_NAME"

# Se aparta el viejo con un rename antes de copiar, igual que hace el auto-update: fusionar encima
# dejaria vivos archivos que la version nueva ya no trae.
if [[ -d "$DESTINO" ]]; then
  info "Reemplazando la version instalada"
  rm -rf "$DESTINO.anterior"
  mv "$DESTINO" "$DESTINO.anterior"
fi

if ditto "$TMP/out/$APP_NAME" "$DESTINO"; then
  rm -rf "$DESTINO.anterior"
else
  [[ -d "$DESTINO.anterior" ]] && mv "$DESTINO.anterior" "$DESTINO"
  rojo "No se pudo copiar a $DESTINO_DIR."
  exit 1
fi

trap - ERR

echo ""
echo "Listo. Galactic Forge quedo en $DESTINO"
echo "Se abre desde Launchpad o con: open -a \"$DESTINO\""
echo ""
echo "No va a pedirte permisos raros: al bajarlo asi no queda en cuarentena."
echo "Las actualizaciones las hace el propio launcher, sin repetir este paso."
