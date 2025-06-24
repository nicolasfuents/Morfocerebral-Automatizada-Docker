import os
import nibabel as nib
import numpy as np
from pathlib import Path

def generate_brain_masks(subjects_dir):
    """
    Genera máscaras para los hemisferios, cerebelo, tallo cerebral y cuerpo calloso 
    a partir del archivo 'aparc+aseg.mgz' de FreeSurfer.

    Parameters:
    subjects_dir (str): Ruta al directorio 'FreeSurfer' donde se encuentra la carpeta 'mri'.
    """

    # Ruta del directorio 'mri' y subcarpeta 'mask'
    DIRECTORIO_APARC_ASEG = Path(subjects_dir) / "mri"
    dir_masks = os.path.join(DIRECTORIO_APARC_ASEG, 'mask')

    # Cargar el archivo 'aparc+aseg.mgz' de FreeSurfer
    archivo = os.path.join(DIRECTORIO_APARC_ASEG, 'aparc+aseg.mgz')
    img = nib.load(archivo)
    data = img.get_fdata()

    # Etiquetas para las estructuras anatómicas
    etiquetas_gris_izquierdo = list(range(1000, 1036)) + list(range(3000, 3036))
    etiquetas_gris_derecho = list(range(2000, 2036)) + list(range(4000, 4036))
    etiquetas_blanca_izquierdo = [2, 10, 11, 12, 13, 17, 18, 26, 28]
    etiquetas_blanca_derecho = [41, 49, 50, 51, 52, 53, 54, 58, 60]
    etiquetas_cerebelo = [8, 47, 7, 46]
    etiquetas_brain_stem = 16
    etiquetas_cuerpo_calloso = [251, 252, 253, 254, 255]

    # Unir etiquetas para hemisferios
    etiquetas_hemisferio_izquierdo = etiquetas_gris_izquierdo + etiquetas_blanca_izquierdo
    etiquetas_hemisferio_derecho = etiquetas_gris_derecho + etiquetas_blanca_derecho

    # Crear máscaras para cada estructura
    mask_izquierdo = np.isin(data, etiquetas_hemisferio_izquierdo)
    mask_derecho = np.isin(data, etiquetas_hemisferio_derecho)
    mask_cerebelo = np.isin(data, etiquetas_cerebelo)
    mask_brain_stem = np.isin(data, etiquetas_brain_stem)
    mask_cuerpo_calloso = np.isin(data, etiquetas_cuerpo_calloso)

    # Crear el directorio 'mask' si no existe
    os.makedirs(dir_masks, exist_ok=True)

    # Guardar las máscaras como nuevas imágenes NIFTI
    nib.save(nib.Nifti1Image(mask_izquierdo.astype(np.uint8), img.affine), f'{dir_masks}/mask_hemisferio_izquierdo.nii')
    print("✔ Máscara de hemisferio izquierdo guardada.")

    nib.save(nib.Nifti1Image(mask_derecho.astype(np.uint8), img.affine), f'{dir_masks}/mask_hemisferio_derecho.nii')
    print("✔ Máscara de hemisferio derecho guardada.")

    nib.save(nib.Nifti1Image(mask_cerebelo.astype(np.uint8), img.affine), f'{dir_masks}/mask_cerebelo.nii')
    print("✔ Máscara de cerebelo guardada.")

    nib.save(nib.Nifti1Image(mask_brain_stem.astype(np.uint8), img.affine), f'{dir_masks}/mask_brain_stem.nii')
    print("✔ Máscara de tallo cerebral guardada.")

    nib.save(nib.Nifti1Image(mask_cuerpo_calloso.astype(np.uint8), img.affine), f'{dir_masks}/mask_cuerpo_calloso.nii')
    print("✔ Máscara de cuerpo calloso guardada.")

    print("Todas las máscaras se han generado y guardado exitosamente.")
