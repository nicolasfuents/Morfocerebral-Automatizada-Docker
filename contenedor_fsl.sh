#!/bin/bash
# Este script sirve para ejecutar FSL sobre un paciente ya procesado por FreeSurfer

pkill -f "parallel -j 2 --lb procesar_paciente"
pkill -f "recon-all"
echo "Limpiando procesos de parallel y recon-all..."
set -e

INPUT="$1"
if [[ -z "$INPUT" ]]; then
    echo "Uso: $0 <directorio_con_dicoms_o_directorio_del_paciente>"
    exit 1
fi

# Rutas
OUTPUT_ROOT="/home/nz8/volu_morfo/data/outputs"

# Caso 1: Si el input contiene DICOMs, extraer nombre desde los DICOM
if find "$INPUT" -type f -name "*.dcm" | grep -q .; then
    echo "DICOMs detectados en $INPUT"
    NOMBRE_PACIENTE=$(docker run --rm \
        -v "$INPUT":/data/dicom:ro \
        morfocerebral:freesurfer bash -c '
            source /opt/conda/etc/profile.d/conda.sh && \
            conda run -n freesurfer_env python /app/extract_patient_name.py /data/dicom')
    PACIENTE_DIR="$OUTPUT_ROOT/$NOMBRE_PACIENTE"

# Caso 2: Si el input ya es un directorio de paciente bajo /outputs
elif [[ "$INPUT" == "$OUTPUT_ROOT"/* ]]; then
    echo "Se detectó ruta completa de paciente en outputs"
    PACIENTE_DIR="$INPUT"
    NOMBRE_PACIENTE=$(basename "$PACIENTE_DIR")

else
    echo "Entrada no válida: debe ser carpeta con DICOMs o carpeta de outputs"
    exit 1
fi

echo "Directorio del paciente: $PACIENTE_DIR"

if [[ ! -d "$PACIENTE_DIR/dicom/FreeSurfer" ]]; then
    echo "No se encontró la carpeta FreeSurfer esperada en $PACIENTE_DIR/dicom"
    echo "Asegurate de que el procesamiento de FreeSurfer ya fue completado."
    exit 1
fi


echo "Resultados de FreeSurfer encontrados. Ejecutando FSL..."

LOG_FSL="$PACIENTE_DIR/fsl_log.txt"

docker run --rm \
    -v "$PACIENTE_DIR":/data/paciente:rw \
    morfocerebral:fsl bash -c '
        source /opt/conda/etc/profile.d/conda.sh && conda activate fsl_env && \
        python3 /app/main_fsl.py --skip_fs --dicom_dir /data/paciente/dicom' \
    2>&1 | tee "$LOG_FSL"


echo "FSL completado exitosamente para $NOMBRE_PACIENTE"
