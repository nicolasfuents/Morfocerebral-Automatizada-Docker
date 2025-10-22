#!/usr/bin/env bash
# Ejecuta solo FSL y envía el correo. Solo requiere -p PACIENTE.
set -euo pipefail

# Constantes
OUTPUTS_ROOT="/home/nz8/volu_morfo/data/outputs"
MENSAJE="/mnt/data/nz8/mensaje.txt"
DESTINATARIOS="/mnt/data/nz8/destinatarios.txt"
IMG_FSL="morfocerebral:fsl"

usage(){ echo "Uso: $(basename "$0") -p PACIENTE"; }

PACIENTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--paciente) PACIENTE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Flag desconocido: $1"; usage; exit 1;;
  esac
done
[[ -n "$PACIENTE" ]] || { echo "Falta -p/--paciente"; usage; exit 1; }
[[ -f "$MENSAJE" ]] || { echo "No existe MENSAJE: $MENSAJE"; exit 1; }
[[ -f "$DESTINATARIOS" ]] || { echo "No existe DESTINATARIOS: $DESTINATARIOS"; exit 1; }

PACIENTE_DIR="$OUTPUTS_ROOT/$PACIENTE"
DICOM_TOP="$PACIENTE_DIR/dicom"
[[ -d "$DICOM_TOP" ]] || { echo "No existe DICOM_DIR: $DICOM_TOP"; exit 1; }

# Buscar el directorio FreeSurfer más reciente bajo dicom/
# Soporta múltiples niveles: .../dicom/**/FreeSurfer/{mri,stats}
FS_DIR="$(find "$DICOM_TOP" -type d -name FreeSurfer -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2- || true)"
[[ -n "$FS_DIR" ]] || { echo "No se encontró carpeta FreeSurfer dentro de $DICOM_TOP"; exit 2; }

# Validaciones clave
[[ -r "$FS_DIR/mri/aparc+aseg.mgz" ]] || { echo "Falta $FS_DIR/mri/aparc+aseg.mgz"; exit 3; }
[[ -d "$FS_DIR/stats" ]] || { echo "Falta carpeta stats en $FS_DIR"; exit 3; }

# Raíz DICOM real para FSL es el padre de FreeSurfer
DICOM_ROOT="$(
  cd "$FS_DIR/.." >/dev/null
  pwd
)"
PDF="$FS_DIR/stats/Reporte_morf.pdf"
EMAIL_LOG="$PACIENTE_DIR/email_log.txt"

echo "Paciente: $PACIENTE"
echo "FreeSurfer: $FS_DIR"
echo "DICOM_ROOT: $DICOM_ROOT"

# Construir ruta equivalente dentro del contenedor
# /data/paciente + (ruta relativa desde PACIENTE_DIR)
REL_CONT="${DICOM_ROOT#$PACIENTE_DIR}"
DICOM_ROOT_CONT="/data/paciente${REL_CONT}"

# Ejecutar FSL con la raíz correcta y saltando FS
docker run --rm \
  -v "$PACIENTE_DIR":/data/paciente:rw \
  "$IMG_FSL" bash -lc '
    set -e
    source /opt/conda/etc/profile.d/conda.sh && conda activate fsl_env
    echo "Usando --dicom_dir: '"$DICOM_ROOT_CONT"'"
    python3 /app/main_fsl.py --skip_fs --dicom_dir '"$DICOM_ROOT_CONT"''

# Envío de email si existe el PDF
if [[ -f "$PDF" ]]; then
  echo "PDF listo: $PDF"
  docker run --rm \
    -v "$PACIENTE_DIR":/data/paciente:ro \
    -v "$MENSAJE":/data/email/mensaje.txt:ro \
    -v "$DESTINATARIOS":/data/email/destinatarios.txt:ro \
    "$IMG_FSL" bash -lc 'set -e
      source /opt/conda/etc/profile.d/conda.sh && conda activate fsl_env
      python /app/send_email.py "'"$PACIENTE"'" \
        "'"${PDF/$PACIENTE_DIR/\/data\/paciente}"'" \
        /data/email/mensaje.txt /data/email/destinatarios.txt' >> "$EMAIL_LOG" 2>&1
  echo "Email enviado. Log: $EMAIL_LOG"
else
  echo "No se encontró el PDF: $PDF"
  exit 4
fi
