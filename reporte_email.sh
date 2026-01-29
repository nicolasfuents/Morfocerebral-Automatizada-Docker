#!/usr/bin/env bash
# Ejecuta solo FSL y envía el correo. 
# Usage: reporte_email.sh -p CARPETA_PACIENTE

set -euo pipefail

# -------------------------
# 1. Configuración
# -------------------------
# Directorio donde está este script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUTS_ROOT="/home/nz8/volu_morfo/data/outputs"
# Usamos rutas absolutas basadas en la ubicación del script
MENSAJE_PATH="$SCRIPT_DIR/mensaje.txt"
DESTINATARIOS_PATH="$SCRIPT_DIR/destinatarios.txt"
# Ruta al script smart (Debe estar en la misma carpeta)
PATH_XVFB_SMART="$SCRIPT_DIR/start_xvfb_smart.sh"

IMG="morfocerebral:ic95"

usage(){ echo "Uso: $(basename "$0") -p CARPETA_PACIENTE"; }

PACIENTE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--paciente) PACIENTE="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Flag desconocido: $1"; usage; exit 1;;
  esac
done

[[ -n "$PACIENTE" ]] || { echo "Falta -p/--paciente"; usage; exit 1; }
[[ -f "$MENSAJE_PATH" ]] || { echo "No existe MENSAJE: $MENSAJE_PATH"; exit 1; }
[[ -f "$DESTINATARIOS_PATH" ]] || { echo "No existe DESTINATARIOS: $DESTINATARIOS_PATH"; exit 1; }
[[ -f "$PATH_XVFB_SMART" ]] || { echo "No existe Script Xvfb: $PATH_XVFB_SMART"; exit 1; }

PACIENTE_DIR="$OUTPUTS_ROOT/$PACIENTE"
DICOM_TOP="$PACIENTE_DIR/dicom"
[[ -d "$DICOM_TOP" ]] || { echo "No existe DICOM_DIR: $DICOM_TOP"; exit 1; }

# 1. Buscar el directorio FastSurfer más reciente
FS_DIR="$(find "$DICOM_TOP" -type d -name FastSurfer -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2- || true)"
[[ -n "$FS_DIR" ]] || { echo "No se encontró carpeta FastSurfer dentro de $DICOM_TOP"; exit 2; }

# Validaciones clave
[[ -r "$FS_DIR/mri/aparc+aseg.mgz" ]] || { echo "Falta $FS_DIR/mri/aparc+aseg.mgz"; exit 3; }
[[ -d "$FS_DIR/stats" ]] || { echo "Falta carpeta stats en $FS_DIR"; exit 3; }

# Raíz DICOM real es el padre de FastSurfer
DICOM_ROOT="$(cd "$FS_DIR/.." >/dev/null && pwd)"
EMAIL_LOG="$PACIENTE_DIR/email_log_manual.txt"

echo "Paciente (Carpeta): $PACIENTE"
echo "FastSurfer encontrado en: $FS_DIR"

# Construir ruta relativa para el contenedor
REL_PATH_FROM_ROOT="${DICOM_ROOT#$PACIENTE_DIR/}"
DICOM_ROOT_CONT="/data/paciente/$REL_PATH_FROM_ROOT"

# 2. Extraer Edad
EDAD=$(docker run --rm --privileged --net=host \
            -v "$DICOM_ROOT":/data/dicom:ro \
            "$IMG" bash -c '
                set -euo pipefail
                source /home/usuario/miniconda3/etc/profile.d/conda.sh &&
                conda activate morfometria_env >/dev/null 2>&1 &&
                python /home/usuario/Bibliografia/pipeline_v2/extract_patient_age.py /data/dicom')
echo "Edad del paciente: $EDAD"

# 3. Ejecutar FSL + Reportes (saltando FS)
# USANDO ESTRATEGIA "SMART INJECTION" (Igual que el script principal)
docker run --rm --privileged --net=host \
  -v "$PACIENTE_DIR":/data/paciente:rw \
  -v "$PATH_XVFB_SMART":/tmp/start_xvfb_smart.sh:ro \
  "$IMG" bash -lc '
    set -e
    
    # --- CONFIGURACIÓN GRÁFICA ROBUSTA ---
    export XDG_RUNTIME_DIR="/tmp/runtime-$$"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"

    # Activamos Xvfb usando el script inyectado
    echo "Iniciando Xvfb Smart..."
    source /tmp/start_xvfb_smart.sh

    source /home/usuario/miniconda3/etc/profile.d/conda.sh
    conda activate morfometria_env
    
    echo "Usando --dicom_dir: '"$DICOM_ROOT_CONT"'"
    
    # Ejecutamos el pipeline (Reportes)
    # --skip_fs hace que solo corra la parte de FSL y generación de PDFs
    python3 /home/usuario/Bibliografia/pipeline_v2/main_local.py --skip_fs --dicom_dir '"$DICOM_ROOT_CONT"'
    '

# 4. Definir Rutas de PDF
PDF_REPORTE_COMPLETO="$FS_DIR/stats/Reporte_completo_comprimido.pdf"
PDF_REPORTE_EPILEPSIA="$FS_DIR/stats/Reporte_epilepsia_comprimido.pdf"
PDF_REPORTE_MORF_ESP="$FS_DIR/stats/Reporte_morf_esp_comprimido.pdf"
PDF_REPORTE_PEDIATRICO="$FS_DIR/stats/Reporte_pediatrico_comprimido.pdf"

EDAD_NUM=${EDAD%% *}

# Determinar los archivos a enviar
if [[ "$EDAD_NUM" -lt 15 ]]; then
    ARCHIVOS_PDF=("$PDF_REPORTE_PEDIATRICO" "$PDF_REPORTE_COMPLETO")
else
    ARCHIVOS_PDF=("$PDF_REPORTE_COMPLETO" "$PDF_REPORTE_EPILEPSIA" "$PDF_REPORTE_MORF_ESP")
fi

ADJUNTOS=()
FS_RELATIVE="${FS_DIR#$PACIENTE_DIR/}"

for pdf in "${ARCHIVOS_PDF[@]}"; do
    if [[ -f "$pdf" ]]; then
        ADJUNTOS+=("/data/paciente/$FS_RELATIVE/stats/$(basename "$pdf")")
    else
        echo "No existe $pdf, se omite"
    fi
done

if [[ ${#ADJUNTOS[@]} -eq 0 ]]; then
    echo "Sin PDFs válidos para enviar" | tee -a "$EMAIL_LOG"
    exit 0
fi

# 5. Enviar Mail
EMAIL_CMD=(
    python /home/usuario/Bibliografia/pipeline_v2/send_email.py
    "$PACIENTE"
    "/data/email/mensaje.txt"
    "/data/email/destinatarios.txt"
)
EMAIL_CMD+=("${ADJUNTOS[@]}")

docker run --rm --privileged --net=host \
    -v "$PACIENTE_DIR":/data/paciente:ro \
    -v "$MENSAJE_PATH":/data/email/mensaje.txt:ro \
    -v "$DESTINATARIOS_PATH":/data/email/destinatarios.txt:ro \
    "$IMG" \
    bash -lc "set -e
        source /home/usuario/miniconda3/etc/profile.d/conda.sh
        conda activate morfometria_env
        $(printf '%q ' "${EMAIL_CMD[@]}")
    " >> "$EMAIL_LOG" 2>&1

echo "Proceso finalizado. Log en: $EMAIL_LOG"