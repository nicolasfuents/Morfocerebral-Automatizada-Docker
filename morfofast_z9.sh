#!/usr/bin/env bash
# Script: morfofast_secuencial.sh
# ESTRATEGIA: Paralelismo nativo + Smart Lock + Inyección de Xvfb Smart

set -eumo pipefail

# -------------------------
# 1. Configuración
# -------------------------
export IMAGE_NAME="${IMAGE_NAME:-morfocerebral:ic95}"
export WATCH_DIR="${WATCH_DIR:-/home/nz8/volu_morfo/data/inputs}"
export OUTPUT_ROOT="${OUTPUT_ROOT:-/home/nz8/volu_morfo/data/outputs}"
export QUEUE_FILE="${QUEUE_FILE:-/tmp/job_queue/files_to_process_secuencial.txt}"
export MAX_JOBS=4 

# Directorio de locks
LOCK_DIR="/tmp/morfofast_locks"
mkdir -p "$LOCK_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOCAL_SCRIPT_DATE="$SCRIPT_DIR/extract_study_date.py"
# [CRÍTICO] Ruta al script smart que acabamos de crear
export PATH_XVFB_SMART="$SCRIPT_DIR/start_xvfb_smart.sh"

# Rutas de Email
DESTINATARIOS_PATH="$SCRIPT_DIR/destinatarios.txt"
MENSAJE_PATH="$SCRIPT_DIR/mensaje.txt"

# -------------------------
# 2. Funciones
# -------------------------

wait_until_complete() {
  local file="$1"
  echo "[INFO] Esperando escritura: $file"
  local prev_size=0 size=0
  while true; do
    sleep 5
    size=$(stat -c%s "$file" 2>/dev/null || echo 0)
    if [[ "$size" -eq "$prev_size" ]]; then break; fi
    prev_size=$size
  done
  echo "[INFO] Archivo estable."
}

controlar_limite_jobs() {
    while [[ $(jobs -r | wc -l) -ge "$MAX_JOBS" ]]; do
        wait -n 2>/dev/null || sleep 1
    done
}

procesar_paciente() {
    local FILE="$1"
    local LOCK_FILE="$2"
    
    echo "====================================================================================================================="
    echo ">>> PROCESANDO: $FILE"
    echo "====================================================================================================================="
    local START_TOTAL=$(date +%s)
    
    local DICOM_SOURCE=""
    local ES_ZIP=0
    local TMP_UNZIP_DIR=""

    # 1. PREPARACIÓN
    if [[ -f "$FILE" && "$FILE" == *.zip ]]; then
        wait_until_complete "$FILE"
        echo "[STEP 1] ZIP detectado. Descomprimiendo..."
        ES_ZIP=1
        TMP_UNZIP_DIR="${FILE%.zip}_temp"
        rm -rf "$TMP_UNZIP_DIR"
        
        unzip -o -q "$FILE" -d "$TMP_UNZIP_DIR"
        FIRST_DCM=$(find "$TMP_UNZIP_DIR" -type f -name "*.dcm" -print -quit)
        
        if [[ -n "$FIRST_DCM" ]]; then
            DICOM_SOURCE=$(dirname "$FIRST_DCM")
        else
            DICOM_SOURCE=""
        fi

    elif [[ -d "$FILE" ]]; then
        echo "[STEP 1] Directorio detectado."
        DICOM_SOURCE="$FILE"
        if find "$DICOM_SOURCE" -type d -name "FastSurfer" | grep -q .; then
            echo "[SKIP] Ya contiene resultados."
            rmdir "$LOCK_FILE" 2>/dev/null
            return
        fi
    else
        echo "[ERROR] Formato no reconocido: $FILE"
        rmdir "$LOCK_FILE" 2>/dev/null
        return
    fi

    if [[ -z "$DICOM_SOURCE" ]]; then
        echo "[ERROR] No se encontraron archivos .dcm válidos."
        [[ "$ES_ZIP" -eq 1 ]] && rm -rf "$TMP_UNZIP_DIR"
        rmdir "$LOCK_FILE" 2>/dev/null
        return
    fi

    # 2. METADATOS
    echo "[STEP 2] Extrayendo metadatos..."
    # Usamos --net=host por seguridad del server, sin tocar entrypoint
    METADATA=$(docker run --rm --privileged --net=host \
        -v "$DICOM_SOURCE":/data/dicom:ro \
        -v "$LOCAL_SCRIPT_DATE":/tmp/extract_study_date.py:ro \
        "$IMAGE_NAME" bash -c '
            set -euo pipefail
            source /home/usuario/miniconda3/etc/profile.d/conda.sh &&
            conda activate morfometria_env >/dev/null 2>&1 &&
            NAME=$(python /home/usuario/Bibliografia/pipeline_v2/extract_patient_name.py /data/dicom) &&
            AGE=$(python /home/usuario/Bibliografia/pipeline_v2/extract_patient_age.py /data/dicom) &&
            DATE=$(python /tmp/extract_study_date.py /data/dicom) &&
            echo "$NAME|$AGE|$DATE"
        ')

    IFS='|' read -r NOMBRE_PACIENTE EDAD FECHA_ESTUDIO <<< "$METADATA"
    echo "   -> Paciente: $NOMBRE_PACIENTE | Edad: $EDAD"

    # 3. DIRECTORIOS Y LIMPIEZA
    PACIENTE_DIR="$OUTPUT_ROOT/${NOMBRE_PACIENTE}_${FECHA_ESTUDIO}"
    mkdir -p "$PACIENTE_DIR/dicom"
    cp -r "$DICOM_SOURCE"/. "$PACIENTE_DIR/dicom/"

    if [[ "$ES_ZIP" -eq 1 ]]; then
        rm -rf "$TMP_UNZIP_DIR"
        rm -f "$FILE"
        # Limpieza Listener
        LISTENER_FOLDER="${FILE%.zip}"
        if [[ -d "$LISTENER_FOLDER" ]]; then
            echo "[CLEANUP] Borrando carpeta residual del listener: $LISTENER_FOLDER"
            rm -rf "$LISTENER_FOLDER"
        fi
    fi

    # 4. PROCESAMIENTO
    sleep 5
    CONTAINER_NAME="fs_${NOMBRE_PACIENTE//[^a-zA-Z0-9]/_}_${FECHA_ESTUDIO}_$(date +%s%N)"
    LOG_PATH="$PACIENTE_DIR/freesurfer_log.txt"
    echo "[STEP 3] Lanzando Docker: $CONTAINER_NAME"
    local START_NET=$(date +%s)
    
    # [CRÍTICO] Montamos el script smart externo en /tmp/start_xvfb_smart.sh (ro)
    docker run -d --name "$CONTAINER_NAME" --privileged --net=host \
    -e OMP_NUM_THREADS=8 \
    -e MKL_NUM_THREADS=8 \
    -v "$PACIENTE_DIR":/data/paciente:rw \
    -v "$PATH_XVFB_SMART":/tmp/start_xvfb_smart.sh:ro \
    "$IMAGE_NAME" \
    bash -lc '
      set -euo pipefail
      export XDG_RUNTIME_DIR="/tmp/runtime-$$"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 700 "$XDG_RUNTIME_DIR"
      
      source /home/usuario/miniconda3/etc/profile.d/conda.sh
      conda activate morfometria_env
      
      # [CRÍTICO] Ejecutamos el script inyectado con source
      echo "Iniciando Xvfb Smart..."
      source /tmp/start_xvfb_smart.sh
      
      echo "Usando Display: $DISPLAY"
      
      python /home/usuario/Bibliografia/pipeline_v2/main_local.py "/data/paciente/dicom"
    '

    docker wait "$CONTAINER_NAME" >/dev/null
    docker logs "$CONTAINER_NAME" >> "$LOG_PATH" 2>&1 || true
    docker rm "$CONTAINER_NAME" >/dev/null || true
    echo "[STEP 3] Pipeline finalizado."
    
    local END_TIME=$(date +%s)
    local DIFF_TOTAL=$((END_TIME - START_TOTAL))
    local DIFF_NET=$((END_TIME - START_NET))
    echo "Tiempo total: $((DIFF_TOTAL / 60))m $((DIFF_TOTAL % 60))s"
    echo "Tiempo neto: $((DIFF_NET / 60))m $((DIFF_NET % 60))s"

    # 5. MAIL
    FS_REAL_PATH=$(find "$PACIENTE_DIR/dicom" -type d -name "FastSurfer" -print -quit)
    EMAIL_LOG="$PACIENTE_DIR/email_log.txt"

    if [[ -z "$FS_REAL_PATH" ]]; then
        echo "[ERROR] No hay carpeta FastSurfer." >> "$EMAIL_LOG"
        rmdir "$LOCK_FILE" 2>/dev/null
        return
    fi
    
    # PDFs
    PDF_FULL="$FS_REAL_PATH/stats/Reporte_completo_comprimido.pdf"
    PDF_EPI="$FS_REAL_PATH/stats/Reporte_epilepsia_comprimido.pdf"
    PDF_MORF="$FS_REAL_PATH/stats/Reporte_morf_esp_comprimido.pdf"
    PDF_PED="$FS_REAL_PATH/stats/Reporte_pediatrico_comprimido.pdf"

    EDAD_NUM=${EDAD%% *}
    if [[ "$EDAD_NUM" -lt 15 ]]; then
        ARCHIVOS_PDF=("$PDF_PED" "$PDF_FULL")
    else
        ARCHIVOS_PDF=("$PDF_FULL" "$PDF_EPI" "$PDF_MORF")
    fi

    ADJUNTOS=()
    FS_RELATIVE=${FS_REAL_PATH#"$PACIENTE_DIR/dicom/"}
    for pdf in "${ARCHIVOS_PDF[@]}"; do
        if [[ -f "$pdf" ]]; then
             ADJUNTOS+=("/data/paciente/dicom/$FS_RELATIVE/stats/$(basename "$pdf")")
        fi
    done

    if [[ ${#ADJUNTOS[@]} -gt 0 ]]; then
        EMAIL_CMD=(python /home/usuario/Bibliografia/pipeline_v2/send_email.py "$NOMBRE_PACIENTE" "/data/email/mensaje.txt" "/data/email/destinatarios.txt")
        EMAIL_CMD+=("${ADJUNTOS[@]}")

        docker run --rm --privileged --net=host \
            -v "$PACIENTE_DIR":/data/paciente:ro \
            -v "$MENSAJE_PATH":/data/email/mensaje.txt:ro \
            -v "$DESTINATARIOS_PATH":/data/email/destinatarios.txt:ro \
            "$IMAGE_NAME" \
            bash -lc "set -e; source /home/usuario/miniconda3/etc/profile.d/conda.sh; conda activate morfometria_env; $(printf '%q ' "${EMAIL_CMD[@]}")" >> "$EMAIL_LOG" 2>&1
    fi

    rmdir "$LOCK_FILE" 2>/dev/null
    echo "[FIN] Proceso completado."
}

# Wrapper Lock
lanzar_con_lock() {
    local FILE="$1"
    local BASENAME=$(basename "$FILE")
    local LOCK_FILE="$LOCK_DIR/$BASENAME.lock"

    if mkdir "$LOCK_FILE" 2>/dev/null; then
        controlar_limite_jobs
        procesar_paciente "$FILE" "$LOCK_FILE" &
    fi
}

# -------------------------
# 3. BUCLE PRINCIPAL
# -------------------------

mkdir -p "$(dirname "$QUEUE_FILE")" "$OUTPUT_ROOT"
touch "$QUEUE_FILE"

echo ">>> Monitor PARALELO (Max: $MAX_JOBS) iniciado en: $WATCH_DIR"

while read -r EXISTING_FILE; do
    if [[ -f "$EXISTING_FILE" ]]; then
        lanzar_con_lock "$EXISTING_FILE"
    fi
done < "$QUEUE_FILE"
: > "$QUEUE_FILE"

inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH_DIR" | while read -r NEWFILE; do
  BASENAME=$(basename "$NEWFILE")
  if [[ "$BASENAME" == *_temp || "$BASENAME" == .* || "$BASENAME" == *~ ]]; then continue; fi
  if [[ "$BASENAME" == *.zip ]] || [[ -d "$NEWFILE" ]]; then
      lanzar_con_lock "$NEWFILE"
  fi
done