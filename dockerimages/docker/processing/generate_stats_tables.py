#!/usr/bin/env python
# coding: utf-8

# In[ ]:


import os
import subprocess

def generate_stats_tables(dicom_dir):
    """
    Genera tablas estadísticas a partir de los archivos .stats de FreeSurfer.

    :param dicom_dir: Ruta al directorio base que contiene la subcarpeta 'FreeSurfer'.
    """
    subjects_dir = os.path.join(dicom_dir, "FreeSurfer")
    stats_dir = os.path.join(subjects_dir, "stats")

    if not os.path.exists(stats_dir):
        raise RuntimeError(f"No se encontró el directorio 'stats' en: {stats_dir}")

    os.environ["SUBJECTS_DIR"] = dicom_dir
    print(f"\nSUBJECTS_DIR configurado en: {os.environ['SUBJECTS_DIR']}\n")

    measures = ["thickness", "area", "foldind"]
    hemispheres = ["lh", "rh"]

    logs = []  # Lista para almacenar la salida de los comandos

    # Crear tablas para medidas corticales
    for measure in measures:
        for hemi in hemispheres:
            output_file = os.path.join(stats_dir, f"aparc_{hemi}_stats_{measure}.txt")
            command = f"aparcstats2table --subjects FreeSurfer --transpose --hemi {hemi} --meas {measure} --tablefile {output_file}"
            logs.append(f"Ejecutando: {command}")
            result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
            logs.append(result.stdout)
            logs.append(result.stderr)

    # Crear tablas para volúmenes subcorticales
    aseg_files = {
        "aseg_stats_etiv.txt": "--meas volume --etiv",
        "aseg_stats_cm3.txt": "--meas volume --scale=0.001"
    }
    for output_file, params in aseg_files.items():
        full_path = os.path.join(stats_dir, output_file)
        command = f"asegstats2table --subjects FreeSurfer --transpose {params} --tablefile {full_path}"
        logs.append(f"Ejecutando: {command}")
        result = subprocess.run(command, shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        logs.append(result.stdout)
        logs.append(result.stderr)

    # Imprimir todo el log de una sola vez al final, evitando reinicios del spinner
    print("\n".join(filter(None, logs)))

    print("Tablas generadas con éxito.")
