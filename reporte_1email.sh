#!/usr/bin/env bash
# Ejecuta solo FSL y envía el correo. Solo requiere -p PACIENTE (carpeta ej: JuanPerez_20230101).
# Script: reporte_1email_v3_fix_qt.sh

set -euo pipefail

# Constantes
OUTPUTS_ROOT="/home/nz8/volu_morfo/data/outputs"
MENSAJE="/mnt/data/Migue/mensaje.txt"
DESTINATARIOS="/mnt/data/Migue/destinatarios.txt"
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
[[ -f "$MENSAJE" ]] || { echo "No existe MENSAJE: $MENSAJE"; exit 1; }
[[ -f "$DESTINATARIOS" ]] || { echo "No existe DESTINATARIOS: $DESTINATARIOS"; exit 1; }

PACIENTE_DIR="$OUTPUTS_ROOT/$PACIENTE"
DICOM_TOP="$PACIENTE_DIR/dicom"
[[ -d "$DICOM_TOP" ]] || { echo "No existe DICOM_DIR: $DICOM_TOP"; exit 1; }

# 1. Buscar el directorio FastSurfer más reciente bajo dicom/
FS_DIR="$(find "$DICOM_TOP" -type d -name FastSurfer -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2- || true)"
[[ -n "$FS_DIR" ]] || { echo "No se encontró carpeta FastSurfer dentro de $DICOM_TOP"; exit 2; }

# Validaciones clave
[[ -r "$FS_DIR/mri/aparc+aseg.mgz" ]] || { echo "Falta $FS_DIR/mri/aparc+aseg.mgz"; exit 3; }
[[ -d "$FS_DIR/stats" ]] || { echo "Falta carpeta stats en $FS_DIR"; exit 3; }

# Raíz DICOM real es el padre de FastSurfer
DICOM_ROOT="$(cd "$FS_DIR/.." >/dev/null && pwd)"

EMAIL_LOG="$PACIENTE_DIR/email_log.txt"

echo "Paciente (Carpeta): $PACIENTE"
echo "FastSurfer encontrado en: $FS_DIR"

# Construir ruta relativa para el contenedor
REL_PATH_FROM_ROOT="${DICOM_ROOT#$PACIENTE_DIR/}"
DICOM_ROOT_CONT="/data/paciente/$REL_PATH_FROM_ROOT"

# 2. Extraer Edad
EDAD=$(docker run --rm \
            -v "$DICOM_ROOT":/data/dicom:ro \
            "$IMG" bash -c '
                set -euo pipefail
                source /home/usuario/miniconda3/etc/profile.d/conda.sh &&
                conda activate morfometria_env >/dev/null 2>&1 &&
                python /home/usuario/Bibliografia/pipeline_v2/extract_patient_age.py /data/dicom')
echo "Edad del paciente: $EDAD"

# 3. Ejecutar FSL + Reportes (saltando FS)
# CORRECCIÓN DE PERMISOS QT Y DISPLAY ALEATORIO
docker run --rm \
  -v "$PACIENTE_DIR":/data/paciente:rw \
  "$IMG" bash -lc '
    set -e
    
    # --- CONFIGURACIÓN GRÁFICA ROBUSTA ---
    
    # 1. Generar ID de pantalla aleatorio (100-500) para evitar colisiones
    DISPLAY_ID=$((100 + RANDOM % 400))
    export DISPLAY=:${DISPLAY_ID}
    echo "Iniciando entorno gráfico en DISPLAY $DISPLAY..."

    # 2. HACKEO DE PERMISOS QT (EL FIX CLAVE)
    # Qt se queja si /tmp/runtime tiene permisos 0777.
    # Intentamos borrarla y crearla bien. Si falla (por permisos de otro usuario),
    # usamos una carpeta custom y forzamos la variable.
    
    rm -rf /tmp/runtime || true
    mkdir -p /tmp/runtime || true
    chmod 700 /tmp/runtime || true

    # Definimos nuestra propia carpeta runtime segura
    MY_RUNTIME="/tmp/runtime-$$"
    rm -rf "$MY_RUNTIME"
    mkdir -p "$MY_RUNTIME"
    chmod 700 "$MY_RUNTIME"
    
    # Exportamos la variable para obligar a Qt a usar ESTA carpeta
    export XDG_RUNTIME_DIR="$MY_RUNTIME"

    # 3. Limpieza de sockets viejos para este Display ID
    rm -f /tmp/.X${DISPLAY_ID}-lock
    rm -f /tmp/.X11-unix/X${DISPLAY_ID}

    # 4. Iniciar Xvfb
    Xvfb :${DISPLAY_ID} -screen 0 1280x1024x24 &
    PID_XVFB=$!
    
    # Esperamos 5 segundos para asegurar estabilidad
    sleep 5

    source /home/usuario/miniconda3/etc/profile.d/conda.sh
    conda activate morfometria_env
    
    echo "Usando --dicom_dir: '"$DICOM_ROOT_CONT"'"
    
    # Ejecutamos el pipeline atrapando errores
    set +e
    python3 /home/usuario/Bibliografia/pipeline_v2/main_local.py --skip_fs --dicom_dir '"$DICOM_ROOT_CONT"'
    EXIT_CODE=$?
    set -e

    # Matamos el Xvfb al salir
    kill $PID_XVFB || true
    
    # Limpiamos nuestra carpeta temporal
    rm -rf "$MY_RUNTIME"

    exit $EXIT_CODE
    '

# 4. Definir Rutas de PDF (Usando la variable FS_DIR real)
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

# 5. Preparar Adjuntos
DESTINATARIOS_PATH="/mnt/data/Migue/destinatarios.txt"
MENSAJE_PATH="/mnt/data/Migue/mensaje.txt"

ADJUNTOS=()
FS_RELATIVE="${FS_DIR#$PACIENTE_DIR/}"

for pdf in "${ARCHIVOS_PDF[@]}"; do
    if [[ -f "$pdf" ]]; then
        ADJUNTOS+=("/data/paciente/$FS_RELATIVE/stats/$(basename "$pdf")")
    else
        echo "No existe $pdf, se omite" | tee -a "$EMAIL_LOG"
    fi
done

if [[ ${#ADJUNTOS[@]} -eq 0 ]]; then
    echo "Sin PDFs válidos para enviar" | tee -a "$EMAIL_LOG"
    exit 0
fi

# 6. Enviar Mail
EMAIL_CMD=(
    python /home/usuario/Bibliografia/pipeline_v2/send_email.py
    "$PACIENTE"
    "/data/email/mensaje.txt"
    "/data/email/destinatarios.txt"
)
EMAIL_CMD+=("${ADJUNTOS[@]}")

docker run --rm \
    -v "$PACIENTE_DIR":/data/paciente:ro \
    -v "$MENSAJE_PATH":/data/email/mensaje.txt:ro \
    -v "$DESTINATARIOS_PATH":/data/email/destinatarios.txt:ro \
    morfocerebral:ic95 \
    bash -lc "set -e
        source /home/usuario/miniconda3/etc/profile.d/conda.sh
        conda activate morfometria_env
        $(printf '%q ' "${EMAIL_CMD[@]}")
    " >> "$EMAIL_LOG" 2>&1

echo "Proceso finalizado. Log en: $EMAIL_LOG"