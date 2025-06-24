# main_fsl.py
# %%
#!/usr/bin/env python
# coding: utf-8

import os
import argparse
import subprocess
import pandas as pd
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeElapsedColumn
from processing.dicom_utils import leer_dicom_y_extraer_info
from processing.generate_stats_tables import generate_stats_tables
from processing.volumetric_analysis import (
    seleccionar_base_control,
    procesar_volumenes,
    calcular_asimetrias_pares,
    exportar_volumetria_excel, 
)
from processing.cortical_thickness_analysis import procesar_espesores
from processing.thickness_plots import graficar_espesores
from processing.area_analysis import procesar_areas
from processing.area_plots import graficar_areas
from processing.foldind_index_analysis import procesar_foldind
from processing.foldind_plots import graficar_foldind
from processing.surf_processing import procesar_superficie_y_grosor
from processing.surf_visualization import visualizar_espesores
from processing.cortical_parcelation_plot import generate_parcelation_plot
from processing.heatmap_pentagono import generar_heatmap_pentagono, seleccionar_base_control_txt
from processing.generate_brain_masks import generate_brain_masks
from processing.generate_brain_masks_plots import generate_macrostructure_plots
from processing.generate_mesh_visualization import generate_mesh_visualization
from processing.generate_morphometric_report import generate_morphometric_report
import re 




def main():
    banner = """
                                              888888888        
                                            88:::::::::88      
                                          88:::::::::::::88    
                                         8::::::88888:::::8    
                     zzzzzzzzzzzzzzzzzz  8:::::8     8:::::8    
                     z:::::::::::::::z   8:::::8     8:::::8    
                     z::::::::::::::z    8:::::88888::::::8     
                     zzzzzzzz::::::z      8:::::::::::::8       
                           z::::::z      8:::::88888:::::8      
                          z::::::z      8:::::8     8:::::8     
                         z::::::z      8:::::8      8:::::8     
                        z::::::z       8:::::8     8:::::8      
                       z::::::zzzzzzzz 8::::::88888::::::8      
                      z::::::::::::::z  88:::::::::::::88       
                     z:::::::::::::::z    88:::::::::88         
                    zzzzzzzzzzzzzzzzzz      888888888           

       ██╗███╗   ██╗████████╗███████╗ ██████╗███╗   ██╗██╗   ██╗███████╗
       ██║████╗  ██║╚══██╔══╝██╔════╝██╔════╝████╗  ██║██║   ██║██╔════╝
       ██║██╔██╗ ██║   ██║   █████╗  ██║     ██╔██╗ ██║██║   ██║███████╗
       ██║██║╚██╗██║   ██║   ██╔══╝  ██║     ██║╚██╗██║██║   ██║╚════██║
       ██║██║ ╚████║   ██║   ███████╗╚██████╗██║ ╚████║╚██████╔╝███████║
       ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚══════╝ ╚═════╝╚═╝  ╚═══╝ ╚═════╝ ╚══════╝

    Script automatizado para análisis morfométricos a partir de imágenes T1.
           """

    parser = argparse.ArgumentParser(
        description=banner,
        epilog="Ejemplo: python main.py --skip_fs --dicom_dir /ruta/a/dicom",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--skip_fs",
        action="store_true",
        help="Omitir el pipeline de FreeSurfer e indicar manualmente las rutas de salida.",
    )

    parser.add_argument(
        "--dicom_dir",
        type=str,
        help="Ruta al directorio que contiene los archivos DICOM del estudio.",
    )

    parser.add_argument(
        "input_path",
        type=str,
        nargs="?",
        help="Ruta al archivo .zip o directorio con el estudio T1 (requerido si no se usa --skip_fs).",
    )

    args = parser.parse_args()

    if args.skip_fs:
        if not args.dicom_dir:
            raise RuntimeError("Debe proporcionar --dicom_dir al usar --skip_fs.")
        dicom_dir = args.dicom_dir
        subjects_dir = os.path.join(dicom_dir, "FreeSurfer")
    else:
        input_path = args.input_path
        script_path = "preprocessing/freesurfer_pipeline.sh"
        process = subprocess.Popen(
            ["bash", script_path, input_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            bufsize=1,  # Desactiva el buffering
        )

        # Leer la salida en tiempo real
        lines = []
        for line in process.stdout:
            print(line, end="")
            lines.append(line.strip())

        # Esperar a que el proceso termine
        process.wait()

        if process.returncode != 0:
            raise RuntimeError("El script freesurfer_pipeline.sh falló.")

        # Buscar el directorio de DICOM en el log de salida
        dicom_dir = next(
            (line.split(": ")[1] for line in lines if "Directorio de DICOM" in line),
            None,
        )
        if not dicom_dir:
            raise RuntimeError("No se encontró 'Directorio de DICOM' en el log de salida.")

        # Buscar el subjects_dir en el log de salida
        for i, line in enumerate(lines):
            if "Resultados disponibles en" in line:
                subjects_dir = lines[i + 1].strip()  # La ruta está en la siguiente línea
                break
        else:
            raise RuntimeError("No se encontró 'Resultados disponibles en' en el log de salida.")
    
    with Progress(SpinnerColumn(), BarColumn(), SpinnerColumn(),TimeElapsedColumn(), TextColumn("[cyan]Ejecutando análisis morfométrico...[/]")) as progress:
        tarea = progress.add_task("Ejecutando análisis morfométrico...", total=None)  # Spinner global

        try:

            print("\nIniciando contenedor de FSL...")
            # 2. FSL
            print("\nGenerando máscaras macroestructurales...")
            generate_brain_masks(subjects_dir)
            generate_brain_masks(subjects_dir)  # Ejecutar dos veces para asegurar la generación de las máscaras
            print("\nGenerando capturas de macroestructuras...")
            generate_macrostructure_plots(dicom_dir, subjects_dir)
        
            print("\nGenerando visualización de mallas corticales...")
            generate_mesh_visualization(dicom_dir, subjects_dir)
        
            # 3. Procesos Generales y Análisis Morfométrico
            print("\nLeyendo datos del paciente...")
            paciente_info = leer_dicom_y_extraer_info(dicom_dir)
            print(f"Edad: {paciente_info['edad']}, Género: {paciente_info['género']}")
        
            print("\nSeleccionando base de control...")
            edad = int(paciente_info["edad"].split()[0])
            genero = paciente_info["género"]
            base_control_path = seleccionar_base_control(edad, genero)
            print(f"Base de control seleccionada: {base_control_path}")
        
            stats_folder = os.path.join(subjects_dir, "stats")
        
            print("\nProcesando volúmenes y calculando asimetrías...")
            df_final, resultados_asimetria = procesar_volumenes(stats_folder, base_control_path)
        
            output_excel = os.path.join(stats_folder, "volumetria.xlsx")
            print("\nExportando resultados a Excel...")
            exportar_volumetria_excel(df_final, resultados_asimetria, output_excel)
        
            print("\nProcesando espesores corticales...")
            procesar_espesores(stats_folder, edad, genero)
            graficar_espesores(stats_folder)
        
            print("\nProcesando áreas corticales...")
            procesar_areas(stats_folder, edad, genero)
            graficar_areas(stats_folder)
        
            print("\nProcesando índices de plegamiento...")
            procesar_foldind(stats_folder, edad, genero)
            graficar_foldind(stats_folder)
        
            print("\nProcesando datos de superficie y espesor cortical para visualización...")
            procesar_superficie_y_grosor(subjects_dir)
        
            print("\nGenerando visualización de superficie y espesores...")
            visualizar_espesores(subjects_dir)
        
            base_control_path_txt = seleccionar_base_control_txt(edad, genero)
            print(f"\nBase de datos control seleccionada para gráficos del perfil volumétrico: {base_control_path_txt}")
            print("\nGenerando gráficos del perfil volumétrico...")
            generar_heatmap_pentagono(stats_folder, base_control_path_txt)
        
            # 4. Generación de Reporte Final
            print(f"\nRuta DICOM recibida: {dicom_dir}")
            print(f"Ruta FreeSurfer esperada: {subjects_dir}")
        
            print("\nGenerando reporte morfométrico en PDF...")
            generate_morphometric_report(dicom_dir, subjects_dir, base_control_path)
        
        except Exception as e:
            print(f"\nSe produjo un error durante el procesamiento: {e}")
        


        finally:
            progress.remove_task(tarea)  # Detener spinner cuando termina el script

        print("\n✔ Análisis completado con éxito.")
        print(banner)

if __name__ == "__main__":
    main()
