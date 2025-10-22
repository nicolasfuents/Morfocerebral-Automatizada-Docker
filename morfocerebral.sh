#!/bin/bash
# Script para procesar imágenes T1 y obtener métricas morfovolumétricas de manera autiomatizada

pkill -f "parallel -j 2 --lb procesar_paciente"
pkill -f "recon-all"

WATCH_DIR="/home/nz8/volu_morfo/data/inputs"  # Directorio donde se monitorean los archivos nuevos
OUTPUT_ROOT="/home/nz8/volu_morfo/data/outputs" # Directorio donde se guardan los resultados procesados
QUEUE_FILE="/tmp/job_queue/files_to_process.txt" # Archivo de cola para los archivos a procesar

mkdir -p "$(dirname "$QUEUE_FILE")"
touch "$QUEUE_FILE"
> "$QUEUE_FILE"

wait_until_complete() {
    local file="$1"
    echo "Esperando a que $file finalice escritura..."
    local prev_size=0
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

    if [[ -f "$FILE" && "$FILE" == *.zip ]]; then
        wait_until_complete "$FILE"
        echo "Archivo ZIP detectado."

        TMP_UNZIP_DIR="${FILE%.zip}_temp"
        unzip -o "$FILE" -d "$TMP_UNZIP_DIR"
        DICOM_DIR=$(find "$TMP_UNZIP_DIR" -type f -name "*.dcm" -exec dirname {} \; | head -n 1)

        NOMBRE_PACIENTE=$(docker run --rm \
            -v "$DICOM_DIR":/data/dicom:ro \
            morfocerebral:freesurfer bash -c '
                source /opt/conda/etc/profile.d/conda.sh && \
                conda run -n freesurfer_env python /app/extract_patient_name.py /data/dicom')

        PACIENTE_DIR="$OUTPUT_ROOT/$NOMBRE_PACIENTE"
        mkdir -p "$PACIENTE_DIR/dicom"
        cp -r "$TMP_UNZIP_DIR"/* "$PACIENTE_DIR/dicom/"
        rm -rf "$TMP_UNZIP_DIR"

    elif [[ -d "$FILE" ]]; then
        echo "Directorio DICOM detectado."
        DICOM_DIR="$FILE"
        if find "$DICOM_DIR" -type d -name "FreeSurfer" | grep -q .; then
            echo "Ya contiene resultados de FreeSurfer. Ignorando."
            return
        fi

        NOMBRE_PACIENTE=$(docker run --rm \
            -v "$DICOM_DIR":/data/dicom:ro \
            morfocerebral:freesurfer bash -c '
                source /opt/conda/etc/profile.d/conda.sh && \
                conda run -n freesurfer_env python /app/extract_patient_name.py /data/dicom')

        PACIENTE_DIR="$OUTPUT_ROOT/$NOMBRE_PACIENTE"
        mkdir -p "$PACIENTE_DIR/dicom"
        cp -r "$DICOM_DIR"/* "$PACIENTE_DIR/dicom/"
    else
        echo "Formato no reconocido. Ignorando."
        return
    fi

    echo "Esperando 10 segundos antes de iniciar el procesamiento..."
    sleep 10

    CONTAINER_NAME="fs_paciente_${NOMBRE_PACIENTE//[^a-zA-Z0-9]/_}_$(date +%s%N)"
    LOG_PATH="$PACIENTE_DIR/freesurfer_log.txt"

    echo "Iniciando procesamiento con FreeSurfer... (contenedor: $CONTAINER_NAME)"
    docker run -d --name "$CONTAINER_NAME" \
        -v "$PACIENTE_DIR":/data/paciente:rw \
        morfocerebral:freesurfer \
        bash -c '
            source /usr/local/freesurfer/SetUpFreeSurfer.sh && \
            source /opt/conda/etc/profile.d/conda.sh && \
            conda activate freesurfer_env && \
            export PYTHONUNBUFFERED=1 && \
            python /app/main_freesurfer.py "/data/paciente/dicom"
        '

    echo "Esperando a que finalice el contenedor $CONTAINER_NAME..."
    docker wait "$CONTAINER_NAME"

    docker logs "$CONTAINER_NAME" >> "$LOG_PATH" 2>&1
    docker rm "$CONTAINER_NAME"

    echo "FreeSurfer completado."
    SUBJECTS_DIR=$(grep "SUBJECTS_DIR configurado en:" "$PACIENTE_DIR/dicom/logs_FS_recon_all/log.txt" | awk '{print $4}')
    echo "SUBJECTS_DIR obtenido: $SUBJECTS_DIR"

    #######################################################################
    # NUEVO: localizar FreeSurfer en profundidad y derivar rutas dinámicas
    #######################################################################
    # FS_DIR: carpeta FreeSurfer más reciente bajo $PACIENTE_DIR/dicom
    FS_DIR="$(find "$PACIENTE_DIR/dicom" -type d -name FreeSurfer -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)"
    if [[ -z "$FS_DIR" ]]; then
        echo "No se encontró carpeta FreeSurfer dentro de $PACIENTE_DIR/dicom"
        return
    fi
    # DICOM_ROOT: padre inmediato de FreeSurfer (lo que espera FSL como --dicom_dir)
    DICOM_ROOT="$(cd "$FS_DIR/.." >/dev/null && pwd)"
    # Rutas equivalentes dentro del contenedor
    REL_PATH="${DICOM_ROOT#$PACIENTE_DIR}"
    DICOM_ROOT_CONT="/data/paciente${REL_PATH}"
    PDF_REPORTE_HOST="$FS_DIR/stats/Reporte_morf.pdf"
    PDF_REPORTE_CONT="${PDF_REPORTE_HOST/$PACIENTE_DIR/\/data\/paciente}"

    echo "FreeSurfer detectado: $FS_DIR"
    echo "DICOM_ROOT para FSL:  $DICOM_ROOT"
    #######################################################################

    echo "Iniciando procesamiento con FSL..."
    LOG_FSL="$PACIENTE_DIR/fsl_log.txt"

    docker run --rm \
        -v "$PACIENTE_DIR":/data/paciente:rw \
        morfocerebral:fsl bash -c '
            source /opt/conda/etc/profile.d/conda.sh && conda activate fsl_env && \
            python3 /app/main_fsl.py --skip_fs --dicom_dir '"$DICOM_ROOT_CONT" \
        2>&1 | tee "$LOG_FSL"

    echo "Verificando si se generó el reporte PDF..."
    if [[ -f "$PDF_REPORTE_HOST" ]]; then
        echo "Reporte generado correctamente para $NOMBRE_PACIENTE"
    else
        echo "Reporte NO generado para $NOMBRE_PACIENTE"
    fi

    if [[ -f "$FILE" && "$FILE" == *.zip ]]; then
        echo "Eliminando archivo ZIP original: $FILE"
        rm -f "$FILE"
    fi

    echo "Procesamiento completo para $NOMBRE_PACIENTE"

    PDF_REPORTE="$PDF_REPORTE_HOST"
    EMAIL_LOG="$PACIENTE_DIR/email_log.txt"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    MENSAJE_PATH="$SCRIPT_DIR/mensaje.txt"
    DESTINATARIOS_PATH="$SCRIPT_DIR/destinatarios.txt"

    if [[ -f "$PDF_REPORTE" ]]; then
        echo "Enviando reporte por email..."
        eval docker run --rm \
        -v "$PACIENTE_DIR":/data/paciente:ro \
        -v "$MENSAJE_PATH":/data/email/mensaje.txt:ro \
        -v "$DESTINATARIOS_PATH":/data/email/destinatarios.txt:ro \
        morfocerebral:fsl \
        bash -c "'source /opt/conda/etc/profile.d/conda.sh && \
                  conda activate fsl_env && \
                  python /app/send_email.py \"$NOMBRE_PACIENTE\" \
                  \"$PDF_REPORTE_CONT\" \
                  \"/data/email/mensaje.txt\" \
                  \"/data/email/destinatarios.txt\"'" \
        >> "$EMAIL_LOG" 2>&1

        echo "Resultado del envío registrado en $EMAIL_LOG"
    else
        echo "No se encontró el PDF del reporte."
    fi
}

export -f procesar_paciente
export -f wait_until_complete
export OUTPUT_ROOT

tail -n +1 -f "$QUEUE_FILE" | parallel -j 2 --line-buffer procesar_paciente {} &

inotifywait -m -e close_write,moved_to --format '%w%f' "$WATCH_DIR" | while read NEWFILE; do
    BASENAME=$(basename "$NEWFILE")
    if [[ "$BASENAME" == *_temp || "$BASENAME" == .* || "$BASENAME" == *~ ]]; then
        echo "Ignorado archivo temporal o incompleto: $NEWFILE"
        continue
    fi

    echo "Detectado nuevo archivo finalizado: $NEWFILE"
    if ! grep -Fxq "$NEWFILE" "$QUEUE_FILE"; then
        echo "$NEWFILE" >> "$QUEUE_FILE"
    else
        echo "Archivo ya en cola: $NEWFILE"
    fi
done
