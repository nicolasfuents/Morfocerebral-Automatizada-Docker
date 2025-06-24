# %%
#!/usr/bin/env python
# coding: utf-8

import os
import argparse
import subprocess
import pandas as pd
from rich.progress import Progress, SpinnerColumn, BarColumn, TextColumn, TimeElapsedColumn
from processing.generate_stats_tables import generate_stats_tables
from processing.cortical_parcelation_plot import generate_parcelation_plot
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


 
        # Actualizar subjects_dir para apuntar a la nueva ubicación

        subjects_dir = os.path.join(dicom_dir, "FreeSurfer")

        # Buscar el subjects_dir en el log de salida
        for i, line in enumerate(lines):
            if "Resultados disponibles en" in line:
                subjects_dir = os.path.join(dicom_dir, "FreeSurfer")
                break
        else:
            raise RuntimeError("No se encontró 'Resultados disponibles en' en el log de salida.")
    
    with Progress(SpinnerColumn(), BarColumn(), SpinnerColumn(),TimeElapsedColumn(), TextColumn("[cyan]Ejecutando análisis morfométrico...[/]")) as progress:
        tarea = progress.add_task("Ejecutando análisis morfométrico...", total=None)  # Spinner global

        try:
            # 1. FreeSurfer
            print("\nGenerando tablas de FreeSurfer...")
            generate_stats_tables(dicom_dir)
        
            print("\nGenerando visualización de parcelación cortical...")
            generate_parcelation_plot(dicom_dir, subjects_dir)
        
        
        except Exception as e:
            print(f"\nSe produjo un error durante el procesamiento: {e}")
        


        finally:
            progress.remove_task(tarea)  # Detener spinner cuando termina el script

        print("\n✔ Contenedor de FreeSurfer completado con éxito.")
        #print(banner)

if __name__ == "__main__":
    main()
