#!/usr/bin/env bash
# Procesamiento morfométrico con una sola imagen Docker (morfocerebral:ic95)
# Script: morfofast_1email.sh

set -euo pipefail

# Matar ejecuciones previas de parallel (si quedaban colgadas)
pkill -f "parallel -j 2 --line-buffer procesar_paciente" || true

# -------------------------
# Configuración
# -------------------------
IMAGE_NAME="${IMAGE_NAME:-morfocerebral:ic95}"

WATCH_DIR="${WATCH_DIR:-/home/nz8/volu_morfo/data/inputs}"
OUTPUT_ROOT="${OUTPUT_ROOT:-/home/nz8/volu_morfo/data/outputs}"
QUEUE_FILE="${QUEUE_FILE:-/tmp/job_queue/files_to_process_fast.txt}"

mkdir -p "$(dirname "$QUEUE_FILE")" "$OUTPUT_ROOT" 
: > "$QUEUE_FILE"

# -------------------------
# Detección de rutas locales
# -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_SCRIPT_DATE="$SCRIPT_DIR/extract_study_date.py"

wait_until_complete() {
  local file="$1"
  echo "Esperando a que $file finalice escritura..."
  local prev_size=0 size=0
  while true; do
    sleep 5
    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if [[ "$size" -eq "$prev_size" ]]; then
      break
    fi
    prev_size=$size
  done
  echo "Archivo estable: $file"
}

procesar_paciente() {
    local FILE="$1"
    echo "Procesando archivo: $FILE"
    local DICOM_SOURCE=""
    local ES_ZIP=0
    local TMP_UNZIP_DIR=""

    # 1. PREPARACIÓN
    if [[ -f "$FILE" && "$FILE" == *.zip ]]; then
        wait_until_complete "$FILE"
        echo "Archivo ZIP detectado."
        ES_ZIP=1
        TMP_UNZIP_DIR="${FILE%.zip}_temp"
        rm -rf "$TMP_UNZIP_DIR"
        unzip -o -q "$FILE" -d "$TMP_UNZIP_DIR"
        DICOM_SOURCE=$(find "$TMP_UNZIP_DIR" -type f -name "*.dcm" -exec dirname {} \; | head -n 1)
    elif [[ -d "$FILE" ]]; then
        echo "Directorio DICOM detectado."
        DICOM_SOURCE="$FILE"
        if find "$DICOM_SOURCE" -type d -name "FastSurfer" | grep -q .; then
            echo "Ya contiene resultados de FastSurfer. Ignorando."
            return
        fi
    else
        echo "Formato no reconocido. Ignorando."
        return
    fi

    if [[ -z "$DICOM_SOURCE" ]]; then
        echo "Error: No se encontraron archivos .dcm válidos."
        [[ "$ES_ZIP" -eq 1 ]] && rm -rf "$TMP_UNZIP_DIR"
        return
    fi

    echo "Fuente de datos: $DICOM_SOURCE"

    # 2. EXTRACCIÓN DE METADATOS
    METADATA=$(docker run --rm \
        -v "$DICOM_SOURCE":/data/dicom:ro \
        -v "$LOCAL_SCRIPT_DATE":/tmp/extract_study_date.py:ro \
        morfocerebral:ic95 bash -c '
            set -euo pipefail
            source /home/usuario/miniconda3/etc/profile.d/conda.sh &&
            conda activate morfometria_env >/dev/null 2>&1 &&
            NAME=$(python /home/usuario/Bibliografia/pipeline_v2/extract_patient_name.py /data/dicom) &&
            AGE=$(python /home/usuario/Bibliografia/pipeline_v2/extract_patient_age.py /data/dicom) &&
            DATE=$(python /tmp/extract_study_date.py /data/dicom) &&
            echo "$NAME|$AGE|$DATE"
        ')

    IFS='|' read -r NOMBRE_PACIENTE EDAD FECHA_ESTUDIO <<< "$METADATA"
    echo "Datos extraídos -> Paciente: $NOMBRE_PACIENTE | Edad: $EDAD | Fecha: $FECHA_ESTUDIO"

    # 3. DEFINICIÓN DE CARPETA FINAL Y COPIA
    PACIENTE_DIR="$OUTPUT_ROOT/${NOMBRE_PACIENTE}_${FECHA_ESTUDIO}"
    mkdir -p "$PACIENTE_DIR/dicom"
    echo "Copiando archivos a: $PACIENTE_DIR/dicom"
    cp -r "$DICOM_SOURCE"/. "$PACIENTE_DIR/dicom/"

    if [[ "$ES_ZIP" -eq 1 ]]; then
        rm -rf "$TMP_UNZIP_DIR"
        rm -f "$FILE"
    fi

    # 4. PROCESAMIENTO
    echo "Esperando 5 segundos..."
    sleep 5

    CONTAINER_NAME="fs_${NOMBRE_PACIENTE//[^a-zA-Z0-9]/_}_${FECHA_ESTUDIO}_$(date +%s%N)"
    LOG_PATH="$PACIENTE_DIR/freesurfer_log.txt"

    echo "Iniciando procesamiento en contenedor: $CONTAINER_NAME"
    
    # ---------------------------------------------------------
    # MODIFICACIÓN CLAVE PARA EVITAR ERRORES DE GUI Y PARALLEL
    # ---------------------------------------------------------
    docker run -d --name "$CONTAINER_NAME" \
    -v "$PACIENTE_DIR":/data/paciente:rw \
    "$IMAGE_NAME" \
    bash -lc '
      set -euo pipefail
      
      # 1. Definir un directorio runtime único para este proceso (evita error QStandardPaths)
      export XDG_RUNTIME_DIR="/tmp/runtime-$$"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"

      # 2. Limpieza preventiva de locks de X11 (por si quedó basura)
      rm -f /tmp/.X99-lock
      rm -f /tmp/.X11-unix/X99

      source /home/usuario/miniconda3/etc/profile.d/conda.sh
      conda activate morfometria_env
      
      # 3. Intentar iniciar Xvfb con manejo de errores o usar xvfb-run si existe
      # Nota: Usamos "|| true" para que si falla el start script no muera todo inmediatamente,
      # aunque fsleyes podría fallar después.
      /usr/local/bin/start_xvfb.sh || echo "Advertencia: start_xvfb.sh reportó error, intentando continuar..."

      # 4. Ejecutar pipeline
      python /home/usuario/Bibliografia/pipeline_v2/main_local.py "/data/paciente/dicom"
    '

    echo "Esperando a que finalice el contenedor $CONTAINER_NAME..."
    docker wait "$CONTAINER_NAME" >/dev/null
    docker logs "$CONTAINER_NAME" >> "$LOG_PATH" 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null || true

    echo "Pipeline completado para $NOMBRE_PACIENTE ($FECHA_ESTUDIO)"

    # 5. ENVÍO DE MAIL
    FS_REAL_PATH=$(find "$PACIENTE_DIR/dicom" -type d -name "FastSurfer" -print -quit)
    EMAIL_LOG="$PACIENTE_DIR/email_log.txt"

    if [[ -z "$FS_REAL_PATH" ]]; then
        echo "No se encontró carpeta FastSurfer. Abortando email." >> "$EMAIL_LOG"
        return
    fi

    PDF_REPORTE_COMPLETO="$FS_REAL_PATH/stats/Reporte_completo_comprimido.pdf"
    PDF_REPORTE_EPILEPSIA="$FS_REAL_PATH/stats/Reporte_epilepsia_comprimido.pdf"
    PDF_REPORTE_MORF_ESP="$FS_REAL_PATH/stats/Reporte_morf_esp_comprimido.pdf"
    PDF_REPORTE_PEDIATRICO="$FS_REAL_PATH/stats/Reporte_pediatrico_comprimido.pdf"

    EDAD_NUM=${EDAD%% *}
    if [[ "$EDAD_NUM" -lt 15 ]]; then
        ARCHIVOS_PDF=("$PDF_REPORTE_PEDIATRICO" "$PDF_REPORTE_COMPLETO")
    else
        ARCHIVOS_PDF=("$PDF_REPORTE_COMPLETO" "$PDF_REPORTE_EPILEPSIA" "$PDF_REPORTE_MORF_ESP")
    fi

    DESTINATARIOS_PATH="/mnt/data/Migue/destinatarios.txt"
    MENSAJE_PATH="/mnt/data/Migue/mensaje.txt"
    
    ADJUNTOS=()
    FS_RELATIVE=${FS_REAL_PATH#"$PACIENTE_DIR/dicom/"}

    for pdf in "${ARCHIVOS_PDF[@]}"; do
        if [[ -f "$pdf" ]]; then
             ADJUNTOS+=("/data/paciente/dicom/$FS_RELATIVE/stats/$(basename "$pdf")")
        else
             echo "Falta PDF: $pdf" >> "$EMAIL_LOG"
        fi
    done

    if [[ ${#ADJUNTOS[@]} -eq 0 ]]; then
        echo "Sin adjuntos válidos." >> "$EMAIL_LOG"
        return
    fi

    EMAIL_CMD=(
        python /home/usuario/Bibliografia/pipeline_v2/send_email.py
        "$NOMBRE_PACIENTE"
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
}

export -f wait_until_complete procesar_paciente
export IMAGE_NAME OUTPUT_ROOT LOCAL_SCRIPT_DATE

# Lector de cola -> parallel
tail -n +1 -f "$QUEUE_FILE" | parallel -j 2 --line-buffer procesar_paciente {} &

# Watcher
inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH_DIR" | while read -r NEWFILE; do
  BASENAME=$(basename "$NEWFILE")
  if [[ "$BASENAME" == *_temp || "$BASENAME" == .* || "$BASENAME" == *~ ]]; then
    echo "Ignorado: $NEWFILE"
    continue
  fi
  echo "Detectado: $NEWFILE"
  grep -Fxq "$NEWFILE" "$QUEUE_FILE" || echo "$NEWFILE" >> "$QUEUE_FILE"
done