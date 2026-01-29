# dicom_listener/listener.py

from pynetdicom import AE, evt, AllStoragePresentationContexts
from pydicom.dataset import Dataset
from pathlib import Path
import logging
import threading
import shutil  # <--- Agregado para borrar carpetas recursivamente
from .config import get_config
from .utils import zip_and_optionally_send

CONFIG = get_config()

# Setup logging
logger = logging.getLogger("OMNIQA-DICOM")
logging.basicConfig(level=logging.INFO)

RECEIVED_STUDIES = {}   # UID -> lista de archivos
STUDY_TIMERS = {}       # UID -> threading.Timer

def finalize_study(study_uid):
    files = RECEIVED_STUDIES.pop(study_uid, [])
    if files:
        # 1. Generar el ZIP (y enviar si aplica)
        zip_and_optionally_send(study_uid, files)
        logger.info(f"Estudio {study_uid} procesado y zip generado.")
        
        # 2. LIMPIEZA: Borrar la carpeta 'staging' original
        try:
            # Reconstruimos la ruta: /app/data/dicom/<UID>
            study_folder = Path(CONFIG["DICOM_STORAGE_PATH"]) / study_uid
            
            if study_folder.exists() and study_folder.is_dir():
                shutil.rmtree(study_folder)  # rmtree borra carpeta y contenido
                logger.info(f"Limpieza (staging) completada: {study_folder} eliminado.")
            else:
                logger.warning(f"Intento de limpieza fallido: {study_folder} no existe o no es directorio.")
                
        except Exception as e:
            logger.error(f"Error crítico limpiando carpeta temporal para {study_uid}: {e}")

    else:
        logger.warning(f"No se encontraron archivos para {study_uid}")

    # Eliminar temporizador
    if study_uid in STUDY_TIMERS:
        del STUDY_TIMERS[study_uid]

def handle_event(event):
    try:
        ds = event.dataset
        ds.file_meta = event.file_meta
        study_uid = ds.StudyInstanceUID
        
        # Guardado en staging (carpeta temporal cruda)
        output_path = Path(CONFIG["DICOM_STORAGE_PATH"]) / study_uid
        output_path.mkdir(parents=True, exist_ok=True)
        filename = output_path / f"{ds.SOPInstanceUID}.dcm"
        ds.save_as(str(filename), write_like_original=False)
        logger.info(f"Recibido: {filename}")

        RECEIVED_STUDIES.setdefault(study_uid, []).append(str(filename))

        # Reiniciar temporizador si ya existía
        if study_uid in STUDY_TIMERS:
            STUDY_TIMERS[study_uid].cancel()

        # Programar nuevo temporizador
        timeout = int(CONFIG.get("DICOM_TIMEOUT", 15))
        timer = threading.Timer(timeout, finalize_study, args=(study_uid,))
        STUDY_TIMERS[study_uid] = timer
        timer.start()

        return 0x0000  # Success
    except Exception as e:
        logger.error(f"Error procesando evento C-STORE: {e}")
        return 0xC210  # Failure

def run_listener():
    ae = AE(ae_title=CONFIG["DICOM_AET"])
    ae.supported_contexts = AllStoragePresentationContexts
    handlers = [(evt.EVT_C_STORE, handle_event)]

    logger.info(f"Iniciando servidor DICOM en puerto {CONFIG['DICOM_PORT']} con AET {CONFIG['DICOM_AET']}")
    ae.start_server(("0.0.0.0", CONFIG["DICOM_PORT"]), evt_handlers=handlers, block=True)