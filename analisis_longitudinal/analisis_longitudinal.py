#!/usr/bin/env python3
import os, argparse, sys
import matplotlib
# FIX: Backend no interactivo para evitar crash en Docker/Servidores
matplotlib.use('Agg') 
import matplotlib.pyplot as plt
import pydicom
import pandas as pd
import numpy as np
import seaborn as sns
from pathlib import Path
from PIL import Image
import img2pdf

# ---------- UTILIDADES ----------
def detectar_carpeta_surfer(root_path):
    """Busca FastSurfer o FreeSurfer indistintamente."""
    for candidate in ['FastSurfer', 'FreeSurfer']:
        path = os.path.join(root_path, candidate)
        if os.path.exists(path):
            return path
    # Si no encuentra, asume estructura directa o falla controladamente
    return None

def leer_datos_volumenes(archivo):
    if not os.path.exists(archivo):
        raise FileNotFoundError(f"No se encuentra el archivo: {archivo}")
    return pd.read_csv(archivo, header=None, names=['Measure:volume','Volumen'], sep='\t')

def obtener_anio_estudio(dicom_file):
    if not dicom_file: return "XXXX"
    try:
        ds = pydicom.dcmread(dicom_file, stop_before_pixels=True, force=True)
        da = str(getattr(ds, "StudyDate", ""))[:4]
        return da if len(da)==4 else "XXXX"
    except:
        return "XXXX"

def obtener_nombre_paciente(dicom_file):
    if not dicom_file: return "PACIENTE"
    try:
        ds = pydicom.dcmread(dicom_file, stop_before_pixels=True, force=True)
        name = str(getattr(ds, "PatientName", "PACIENTE")).strip()
        safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in name)
        return safe or "PACIENTE"
    except:
        return "PACIENTE"

def solicitar_archivo_dicom(directorio):
    for root, _, files in os.walk(directorio):
        for f in files:
            if f.lower().endswith(".dcm"):
                return os.path.join(root, f)
    return None

def calcular_volumenes_sujeto(datos):
    regiones_interes = [
        'Left-Cerebellum-White-Matter','Left-Cerebellum-Cortex',
        'Right-Cerebellum-White-Matter','Right-Cerebellum-Cortex',
        'CC_Posterior','CC_Mid_Posterior','CC_Central','CC_Mid_Anterior','CC_Anterior',
        'Left-Hippocampus','Right-Hippocampus','CerebralWhiteMatterVol','TotalGrayVol'
    ]
    v = {}
    for r in regiones_interes:
        row = datos.loc[datos['Measure:volume']==r]
        v[r] = float(row['Volumen'].values[0]) if not row.empty else 0.0

    out = {
        'Cerebelo': v['Left-Cerebellum-White-Matter']+v['Left-Cerebellum-Cortex']+
                    v['Right-Cerebellum-White-Matter']+v['Right-Cerebellum-Cortex'],
        'Cuerpo Calloso': v['CC_Posterior']+v['CC_Mid_Posterior']+v['CC_Central']+v['CC_Mid_Anterior']+v['CC_Anterior'],
        'Hipocampo': v['Left-Hippocampus']+v['Right-Hippocampus'],
        'Sustancia Blanca': v['CerebralWhiteMatterVol'],
        'Sustancia Gris': v['TotalGrayVol']
    }
    return out

def ensure_dir(p): Path(p).mkdir(parents=True, exist_ok=True)

# ---------- GRÁFICOS ----------
def dibujar_pentagono(vol_ctrl, vol_suj, out_png, anio_ant, anio_rec):
    labels = list(vol_ctrl.keys())
    vals_norm = {k: (vol_suj[k]/vol_ctrl[k] if vol_ctrl[k]!=0 else 0) for k in labels}

    num_vars = len(labels)
    ang = np.linspace(0, 2*np.pi, num_vars, endpoint=False).tolist()
    ang = [a + np.pi/10 for a in ang] + [ang[0] + np.pi/10]

    vals_ctrl = [1]*(num_vars+1)
    vals_outer = [1.3]*(num_vars+1)
    vals_suj = [vals_norm[k] for k in labels] + [vals_norm[labels[0]]]

    with plt.style.context('default'):
        fig, ax = plt.subplots(figsize=(6,6), subplot_kw=dict(polar=True))
        for a in ang[:-1]:
            ax.plot([a,a],[0,1.3], color='white', linestyle='dotted', linewidth=2)
        ax.plot(ang, vals_ctrl, color='#6C6D6E', linewidth=2, label=f'Vol {anio_ant}')
        ax.plot(ang, vals_outer, color='#dadddb', linewidth=3)
        ax.fill(ang, vals_outer, color='white', alpha=1)
        ax.plot(ang, vals_suj, color='#ffd966', linewidth=2, label=f'Vol {anio_rec}')
        ax.fill(ang, vals_suj, color='#ffd966', alpha=0.15)

        ax.yaxis.set_visible(False); ax.spines['polar'].set_visible(False)
        ax.set_xticks(ang[:-1]); ax.set_xticklabels([])
        for lab, a in zip(labels, ang[:-1]):
            ha = 'center' if lab=='Cuerpo Calloso' else ('right' if np.cos(a)<0 else 'left')
            va = 'bottom' if np.sin(a)>0 else 'top'
            ax.text(a, 1.4, lab, ha=ha, va=va, color='gray', fontsize=12)
        leg = plt.legend(loc='lower center', bbox_to_anchor=(0.5,-0.05))
        for t in leg.get_texts(): t.set_color("gray")
        fig.savefig(out_png, dpi=300, bbox_inches='tight'); plt.close(fig)

def dibujar_heatmap(vol_ctrl, vol_suj, out_png, anio_ant, anio_rec):
    cats = list(vol_ctrl.keys())
    data = np.array([list(vol_ctrl.values()), list(vol_suj.values())])
    with plt.style.context('default'):
        fig, ax = plt.subplots(figsize=(10,4))
        sns.heatmap(data, annot=True, cmap='YlGnBu', fmt='.1f',
                    xticklabels=cats, yticklabels=[f'Vol {anio_ant}', f'Vol {anio_rec}'],
                    ax=ax)
        plt.title('Comparación de Volúmenes (mm3)', color='gray')
        fig.savefig(out_png, dpi=300, bbox_inches='tight'); plt.close(fig)

def dibujar_diferencias(xlsx_old, xlsx_new, out_png):
    sns.set(style="darkgrid")
    if not os.path.exists(xlsx_old) or not os.path.exists(xlsx_new):
        print("Aviso: No se encontraron excels de volumetría para diferencias.")
        return

    va = pd.read_excel(xlsx_old)
    vr = pd.read_excel(xlsx_new)
    
    # Merge robusto
    merged = pd.merge(va, vr, on="Regiones_ESP", suffixes=('_old', '_new'))
    merged['Diferencia_%VIT'] = merged['Volumen_%VIT_new'] - merged['Volumen_%VIT_old']
    cambios = merged[merged['Diferencia_%VIT'] != 0]

    if cambios.empty: return

    fig, ax = plt.subplots(figsize=(10,8))
    sns.barplot(x="Diferencia_%VIT", y="Regiones_ESP", data=cambios,
                palette=sns.diverging_palette(220, 20, as_cmap=False), ci=None, ax=ax)
    plt.axvline(0, color='gray', linewidth=0.8)
    plt.xlabel('Diferencia (%VIT)', color='gray')
    plt.tight_layout()
    fig.savefig(out_png, dpi=300, bbox_inches='tight'); plt.close(fig)

def export_pdf(img_paths, pdf_path):
    imgs = []
    for p in img_paths:
        if os.path.exists(p):
            im = Image.open(p).convert("RGB")
            im.save(p)
            imgs.append(p)
    if imgs:
        with open(pdf_path, "wb") as f:
            f.write(img2pdf.convert(imgs))

# ---------- MAIN ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=True)
    ap.add_argument("--new", required=True)
    ap.add_argument("--outroot", required=True)
    args = ap.parse_args()

    # Detectar carpetas FS (FastSurfer o FreeSurfer)
    fs_old = detectar_carpeta_surfer(args.old)
    fs_new = detectar_carpeta_surfer(args.new)

    if not fs_old or not fs_new:
        print(f"Error: No se encontró FastSurfer/FreeSurfer en {args.old} o {args.new}")
        sys.exit(1)

    # Buscar DICOMs para metadatos
    dicom_old = solicitar_archivo_dicom(args.old)
    dicom_new = solicitar_archivo_dicom(args.new)
    
    paciente = obtener_nombre_paciente(dicom_new)
    anio_ant = obtener_anio_estudio(dicom_old)
    anio_rec = obtener_anio_estudio(dicom_new)

    out_dir = os.path.join(args.outroot, paciente)
    ensure_dir(out_dir)

    print(f"Analizando: {paciente} ({anio_ant} vs {anio_rec})")
    
    # Rutas Stats
    aseg_old = os.path.join(fs_old, 'stats', 'aseg_stats_etiv.txt')
    aseg_new = os.path.join(fs_new, 'stats', 'aseg_stats_etiv.txt')
    
    vol_old = calcular_volumenes_sujeto(leer_datos_volumenes(aseg_old))
    vol_new = calcular_volumenes_sujeto(leer_datos_volumenes(aseg_new))

    # Graficar
    png_pent = os.path.join(out_dir, 'pentagono.png')
    png_heat = os.path.join(out_dir, 'heatmap.png')
    png_diff = os.path.join(out_dir, 'diff.png')
    
    xlsx_old = os.path.join(fs_old, 'stats', 'volumetria.xlsx')
    xlsx_new = os.path.join(fs_new, 'stats', 'volumetria.xlsx')

    dibujar_pentagono(vol_old, vol_new, png_pent, anio_ant, anio_rec)
    dibujar_heatmap(vol_old, vol_new, png_heat, anio_ant, anio_rec)
    dibujar_diferencias(xlsx_old, xlsx_new, png_diff)

    # PDF
    pdf_path = os.path.join(out_dir, f"reporte_longitudinal_{paciente}.pdf")
    export_pdf([png_pent, png_heat, png_diff], pdf_path)
    print(f"[OK] PDF generado: {pdf_path}")

if __name__ == "__main__":
    main()