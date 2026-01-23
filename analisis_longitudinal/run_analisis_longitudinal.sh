#!/usr/bin/env bash
# run_analisis_longitudinal.sh
# Versión: Docker + Análisis Híbrido + Reportes OLD y NEW Adjuntos
set -euo pipefail

# --- CONFIGURACIÓN ---
OLD_DIR="${1:-/home/nz8/volu_morfo/data/outputs/BRIZUELA_MARIA_FERNANDA_20240513}"
NEW_DIR="${2:-/home/nz8/volu_morfo/data/outputs/BRIZUELA_MARIA_FERNANDA_20260121}"
OUTROOT="/home/nz8/volu_morfo/data/outputs/analisis_longitudinales"
IMG="morfocerebral:ic95"

# --- RUTAS ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY_ANALISIS="${SCRIPT_DIR}/analisis_longitudinal.py"
PY_EMAIL="${SCRIPT_DIR}/send_email_longitudinal.py"
MENSAJE="${SCRIPT_DIR}/mensaje_longitudinal.txt"

# Destinatarios (sube 2 niveles y entra a Migue)
DESTINATARIOS="$(cd "$SCRIPT_DIR/../.." && pwd)/Migue/destinatarios.txt"

# --- VALIDACIONES ---
[[ -f "$PY_ANALISIS" ]] || { echo "Falta ${PY_ANALISIS}"; exit 1; }
[[ -d "$OLD_DIR" ]] || { echo "No existe OLD_DIR: $OLD_DIR"; exit 1; }
[[ -d "$NEW_DIR" ]] || { echo "No existe NEW_DIR: $NEW_DIR"; exit 1; }
[[ -f "$DESTINATARIOS" ]] || { echo "Error: No se encuentra ${DESTINATARIOS}"; exit 1; }

mkdir -p "$OUTROOT"

echo "=== Análisis Longitudinal Completo (Docker) ==="
echo "OLD: $OLD_DIR"
echo "NEW: $NEW_DIR"

# Ejecución en Docker
docker run --rm \
    -v "/home/nz8:/home/nz8:rw" \
    -v "/mnt/data:/mnt/data:ro" \
    "$IMG" \
    bash -lc "
    set -e
    
    # 1. Cargar entorno y dependencias
    source /home/usuario/miniconda3/etc/profile.d/conda.sh
    conda activate morfometria_env
    pip install img2pdf openpyxl --quiet >/dev/null 2>&1 || true

    # 2. Helpers de búsqueda
    get_fs_parent() {
        find \"\$1\" -type d \( -name 'FastSurfer' -o -name 'FreeSurfer' \) -print -quit | xargs dirname 2>/dev/null || true
    }
    
    # Función para seleccionar reportes según la edad de ESE estudio específico
    recolectar_reportes() {
        local ROOT_STUDY=\$1
        local FS_PATH=\$(find \"\$ROOT_STUDY\" -type d \( -name 'FastSurfer' -o -name 'FreeSurfer' \) -print -quit 2>/dev/null || true)
        
        if [[ -z \"\$FS_PATH\" ]]; then return; fi
        
        # Detectar edad en este estudio
        local EDAD_RAW=\$(python /home/usuario/Bibliografia/pipeline_v2/extract_patient_age.py \"\$ROOT_STUDY\" || echo '0')
        local EDAD_NUM=\${EDAD_RAW%% *}
        local STATS_DIR=\"\$FS_PATH/stats\"
        
        local P_COMP=\"\$STATS_DIR/Reporte_completo_comprimido.pdf\"
        local P_EPI=\"\$STATS_DIR/Reporte_epilepsia_comprimido.pdf\"
        local P_MORF=\"\$STATS_DIR/Reporte_morf_esp_comprimido.pdf\"
        local P_PED=\"\$STATS_DIR/Reporte_pediatrico_comprimido.pdf\"

        # Seleccionar según edad
        if [[ \"\$EDAD_NUM\" -lt 15 ]]; then
            [[ -f \"\$P_PED\" ]] && echo \"\$P_PED\"
            [[ -f \"\$P_COMP\" ]] && echo \"\$P_COMP\"
        else
            [[ -f \"\$P_COMP\" ]] && echo \"\$P_COMP\"
            [[ -f \"\$P_EPI\" ]] && echo \"\$P_EPI\"
            [[ -f \"\$P_MORF\" ]] && echo \"\$P_MORF\"
        fi
    }

    OLD_ROOT=\$(get_fs_parent \"$OLD_DIR\")
    NEW_ROOT=\$(get_fs_parent \"$NEW_DIR\")

    if [[ -z \"\$OLD_ROOT\" ]]; then echo 'Error: No se encontró FastSurfer en OLD_DIR'; exit 1; fi
    if [[ -z \"\$NEW_ROOT\" ]]; then echo 'Error: No se encontró FastSurfer en NEW_DIR'; exit 1; fi
    
    # 3. Ejecutar Análisis Longitudinal
    echo \"Generando reporte comparativo...\"
    python3 \"$PY_ANALISIS\" --old \"\$OLD_ROOT\" --new \"\$NEW_ROOT\" --outroot \"$OUTROOT\"
    
    # 4. Recolectar todos los PDFs
    declare -a EXTRAS
    
    echo \"Recolectando reportes del estudio VIEJO...\"
    while IFS= read -r pdf; do EXTRAS+=(\"\$pdf\"); done < <(recolectar_reportes \"\$OLD_ROOT\")

    echo \"Recolectando reportes del estudio NUEVO...\"
    while IFS= read -r pdf; do EXTRAS+=(\"\$pdf\"); done < <(recolectar_reportes \"\$NEW_ROOT\")
    
    # 5. Enviar Email
    PDF_LONG=\$(find \"$OUTROOT\" -name 'reporte_longitudinal_*.pdf' -type f -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)
    
    if [[ -f \"\$PDF_LONG\" ]]; then
        PACIENTE=\$(basename \"\$PDF_LONG\" | sed 's/reporte_longitudinal_//;s/.pdf//')
        echo \"PDF Longitudinal: \$PDF_LONG\"
        echo \"Total adjuntos adicionales: \${#EXTRAS[@]}\"
        
        if [[ -f \"$PY_EMAIL\" ]]; then
            echo \"Enviando email...\"
            # Se envían: Paciente, PDF Longitudinal, Mensaje, Destinatarios + Todos los Extras
            python3 \"$PY_EMAIL\" \"\$PACIENTE\" \"\$PDF_LONG\" \"$MENSAJE\" \"$DESTINATARIOS\" \"\${EXTRAS[@]}\"
        else
            echo \"Error: Script de email no encontrado.\"
        fi
    else
        echo 'Error: No se encontró el PDF longitudinal.'
        exit 1
    fi
    "

echo "[OK] Finalizado."