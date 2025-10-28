#!/usr/bin/env bash
set -euo pipefail

# --- ARGUMENTOS ---
OLD_DIR="${1:-/home/nz8/volu_morfo/data/outputs/CIMA_MARTHA_ESTHER_20230424143144}"
NEW_DIR="${2:-/home/nz8/volu_morfo/data/outputs/CIMA_MARTHA_ESTHER_20251024154356}"
OUTROOT="/home/nz8/volu_morfo/data/outputs/analisis_longitudinales"

# --- RUTAS LOCALES ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ANALISIS="${SCRIPT_DIR}/analisis_longitudinal.py"
PY_EMAIL="${SCRIPT_DIR}/send_email_longitudinal.py"
MENSAJE="${SCRIPT_DIR}/mensaje_longitudinal.txt"
DESTINATARIOS="$(cd "$SCRIPT_DIR/.." && pwd)/destinatarios.txt"

[[ -f "$PY_ANALISIS" ]] || { echo "Falta ${PY_ANALISIS}"; exit 1; }
[[ -f "$PY_EMAIL" ]] ||   { echo "Falta ${PY_EMAIL}"; exit 1; }
[[ -f "$MENSAJE" ]] ||    { echo "Falta ${MENSAJE}"; exit 1; }
[[ -f "$DESTINATARIOS" ]] || { echo "Falta ${DESTINATARIOS}"; exit 1; }
[[ -d "$OLD_DIR" ]] || { echo "No existe OLD_DIR: $OLD_DIR"; exit 1; }
[[ -d "$NEW_DIR" ]] || { echo "No existe NEW_DIR: $NEW_DIR"; exit 1; }

mkdir -p "$OUTROOT"

# --- VENV TEMPORAL ---
TMP_ENV="$(mktemp -d)"
python3 -m venv "$TMP_ENV"
source "$TMP_ENV/bin/activate"
pip install --upgrade pip --quiet
pip install --quiet pydicom pandas numpy matplotlib seaborn openpyxl pillow img2pdf

# --- OBTENER PACIENTE DESDE NEW_DIR ---
DICOM_NEW="$(find "$NEW_DIR" -type f -iname '*.dcm' -readable -print -quit 2>/dev/null || true)"
if [[ -z "$DICOM_NEW" ]]; then
  echo "No se encontró ningún DICOM en NEW_DIR"
  deactivate; rm -rf "$TMP_ENV"; exit 2
fi

PACIENTE="$("$TMP_ENV/bin/python" -c "import sys,pydicom,pathlib; p=pathlib.Path(sys.argv[1]); ds=pydicom.dcmread(str(p), stop_before_pixels=True, force=True); name=str(getattr(ds,'PatientName','PACIENTE')).strip(); safe=''.join(c if (c.isalnum() or c in '._-') else '_' for c in name) or 'PACIENTE'; print(safe)" "$DICOM_NEW")"

[[ -n "$DICOM_NEW" ]] || { echo "No se encontró ningún DICOM legible en NEW_DIR"; deactivate; rm -rf "$TMP_ENV"; exit 2; }
[[ -r "$DICOM_NEW" ]] || { echo "Sin permisos de lectura para: $DICOM_NEW"; deactivate; rm -rf "$TMP_ENV"; exit 2; }

OUT_DIR="${OUTROOT}/${PACIENTE}"
mkdir -p "$OUT_DIR"

# --- LOCALIZAR CARPETA FreeSurfer EN CADA ESTUDIO ---
find_fs_parent() {
  local base="$1"
  # encuentra la primera carpeta llamada FreeSurfer legible
  local fsdir
  fsdir="$(find "$base" -type d -name 'FreeSurfer' -readable -print -quit 2>/dev/null || true)"
  [[ -n "$fsdir" ]] || { echo "No se encontró carpeta 'FreeSurfer' bajo: $base"; return 1; }
  # valida que existan los stats clave
  [[ -r "$fsdir/stats/aseg_stats_etiv.txt" ]] || { echo "Falta stats/aseg_stats_etiv.txt en: $fsdir"; return 1; }
  dirname "$fsdir"
}

OLD_ROOT="$(find_fs_parent "$OLD_DIR")" || { deactivate; rm -rf "$TMP_ENV"; exit 4; }
NEW_ROOT="$(find_fs_parent "$NEW_DIR")" || { deactivate; rm -rf "$TMP_ENV"; exit 4; }

echo "OLD_ROOT: $OLD_ROOT"
echo "NEW_ROOT: $NEW_ROOT"

# --- ANÁLISIS ---
"$TMP_ENV/bin/python" "$PY_ANALISIS" --old "$OLD_ROOT" --new "$NEW_ROOT" --outroot "$OUTROOT"

PDF="${OUT_DIR}/reporte_longitudinal_${PACIENTE}.pdf"
[[ -f "$PDF" ]] || { echo "No se generó PDF: $PDF"; deactivate; rm -rf "$TMP_ENV"; exit 3; }

# --- ENVÍO EMAIL LOCAL ---
EMAIL_LOG="${OUT_DIR}/email_longitudinal_log.txt"
"$TMP_ENV/bin/python" "$PY_EMAIL" "$PACIENTE" "$PDF" "$MENSAJE" "$DESTINATARIOS" >> "$EMAIL_LOG" 2>&1

echo "PDF: $PDF"
echo "Email log: $EMAIL_LOG"

# --- LIMPIEZA ---
deactivate
rm -rf "$TMP_ENV"
echo "[OK] Listo."
