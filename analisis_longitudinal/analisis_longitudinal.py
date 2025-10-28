#!/usr/bin/env python3
import os, argparse
import pydicom
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
from datetime import datetime
from PIL import Image
import img2pdf

# ---------- utilidades ----------
def leer_datos_volumenes(archivo):
    return pd.read_csv(archivo, header=None, names=['Measure:volume','Volumen'], sep='\t')

def obtener_anio_estudio(dicom_file):
    ds = pydicom.dcmread(dicom_file, stop_before_pixels=True, force=True)
    da = str(getattr(ds, "StudyDate", ""))[:4]
    return da if len(da)==4 else "XXXX"

def obtener_nombre_paciente(dicom_file):
    ds = pydicom.dcmread(dicom_file, stop_before_pixels=True, force=True)
    name = str(getattr(ds, "PatientName", "PACIENTE")).strip()
    safe = "".join(c if c.isalnum() or c in "._-" else "_" for c in name)
    return safe or "PACIENTE"

def solicitar_archivo_dicom(directorio):
    for root, _, files in os.walk(directorio):
        for f in files:
            if f.lower().endswith(".dcm"):
                return os.path.join(root, f)
    raise FileNotFoundError(f"No se encontró DICOM en {directorio}")

def calcular_volumenes_sujeto(datos):
    regiones_interes = [
        'Left-Cerebellum-White-Matter','Left-Cerebellum-Cortex',
        'Right-Cerebellum-White-Matter','Right-Cerebellum-Cortex',
        'CC_Posterior','CC_Mid_Posterior','CC_Central','CC_Mid_Anterior','CC_Anterior',
        'Left-Hippocampus','Right-Hippocampus','CerebralWhiteMatterVol','TotalGrayVol'
    ]
    v = {r: float(datos.loc[datos['Measure:volume']==r,'Volumen'].values[0]) if not datos.loc[datos['Measure:volume']==r].empty else 0.0
         for r in regiones_interes}
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

# ---------- gráficos ----------
def dibujar_pentagono(vol_ctrl, vol_suj, out_png, dicom_antiguo, dicom_reciente):
    anio_ant = obtener_anio_estudio(dicom_antiguo)
    anio_rec = obtener_anio_estudio(dicom_reciente)
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
        ax.plot(ang, vals_ctrl, color='#6C6D6E', linewidth=2, label=f'Volúmenes {anio_ant}')
        ax.plot(ang, vals_outer, color='#dadddb', linewidth=3)
        ax.fill(ang, vals_outer, color='white', alpha=1)
        ax.plot(ang, vals_suj, color='#ffd966', linewidth=2, label=f'Volúmenes {anio_rec}')
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

def dibujar_heatmap(vol_ctrl, vol_suj, out_png, dicom_antiguo, dicom_reciente):
    anio_ant = obtener_anio_estudio(dicom_antiguo)
    anio_rec = obtener_anio_estudio(dicom_reciente)
    cats = list(vol_ctrl.keys())
    data = np.array([list(vol_ctrl.values()), list(vol_suj.values())])
    with plt.style.context('default'):
        fig, ax = plt.subplots(figsize=(10,4))
        sns.heatmap(data, annot=True, cmap='YlGnBu',
                    xticklabels=cats, yticklabels=[f'Volúmenes {anio_ant}', f'Volúmenes {anio_rec}'],
                    ax=ax, vmin=0, vmax=float(data.max()))
        plt.title('Comparación de Volúmenes (%VIT)', color='gray')
        for l in ax.get_xticklabels(): l.set_color('gray')
        for l in ax.get_yticklabels(): l.set_color('gray')
        fig.savefig(out_png, dpi=300, bbox_inches='tight'); plt.close(fig)

def dibujar_diferencias(vol_xlsx_ant, vol_xlsx_rec, out_png):
    sns.set(style="darkgrid")
    va = pd.read_excel(vol_xlsx_ant)
    vr = pd.read_excel(vol_xlsx_rec)
    assert (va['Regiones_ESP'] == vr['Regiones_ESP']).all(), "Regiones no coinciden"
    va = va.copy()
    va['Diferencia_%VIT'] = vr['Volumen_%VIT'] - va['Volumen_%VIT']
    cambios = va[va['Diferencia_%VIT'] != 0]
    fig, ax = plt.subplots(figsize=(10,8))
    sns.barplot(x="Diferencia_%VIT", y="Regiones_ESP", data=cambios,
                palette=sns.diverging_palette(220, 20, as_cmap=False), ci=None, ax=ax)
    plt.axvline(0, color='gray', linewidth=0.8)
    plt.xlabel('Diferencia de Volumen (%VIT)', color='gray', fontsize=10); plt.ylabel('', color='gray')
    plt.xticks(color='gray'); plt.yticks(color='gray', fontsize=8)
    plt.grid(True, axis='x', linestyle='-', color='white', linewidth=0.5)
    plt.grid(True, axis='y', linestyle='-', color='white', linewidth=0.5)
    txt = ("Cómo leerlo:\n- Cerca de 0: sin cambio relevante.\n"
           "- Negativo: reducción de volumen.\n- Positivo: aumento de volumen.\n")
    props = dict(boxstyle='round,pad=0.5', edgecolor='gray', facecolor='white', alpha=0.85)
    ax.text(0.2, 0.7, txt, transform=ax.transAxes, fontsize=8, va='top', bbox=props, color="black")
    plt.tight_layout()
    fig.savefig(out_png, dpi=300, bbox_inches='tight'); plt.close(fig)

def export_pdf(img_paths, pdf_path):
    imgs = []
    for p in img_paths:
        im = Image.open(p)
        if im.mode != "RGB": im = im.convert("RGB")
        im.save(p)  # asegurar RGB persistente
        imgs.append(p)
    with open(pdf_path, "wb") as f:
        f.write(img2pdf.convert(imgs))

# ---------- main ----------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--old", required=True, help="Carpeta estudio antiguo (contiene FreeSurfer)")
    ap.add_argument("--new", required=True, help="Carpeta estudio reciente (contiene FreeSurfer)")
    ap.add_argument("--outroot", required=True, help="Raíz de salida analisis_longitudinales")
    args = ap.parse_args()

    dir_old, dir_new = args.old, args.new
    dicom_old = solicitar_archivo_dicom(dir_old)
    dicom_new = solicitar_archivo_dicom(dir_new)
    paciente = obtener_nombre_paciente(dicom_new)  # usa el más reciente
    out_dir = os.path.join(args.outroot, paciente)
    ensure_dir(out_dir)

    aseg_old = os.path.join(dir_old, 'FreeSurfer','stats','aseg_stats_etiv.txt')
    aseg_new = os.path.join(dir_new, 'FreeSurfer','stats','aseg_stats_etiv.txt')
    vol_old = calcular_volumenes_sujeto(leer_datos_volumenes(aseg_old))
    vol_new = calcular_volumenes_sujeto(leer_datos_volumenes(aseg_new))

    xlsx_old = os.path.join(dir_old, 'FreeSurfer','stats','volumetria.xlsx')
    xlsx_new = os.path.join(dir_new, 'FreeSurfer','stats','volumetria.xlsx')

    png_pent = os.path.join(out_dir, 'comparacion_longitudinal_pentagono.png')
    png_heat = os.path.join(out_dir, 'comparacion_longitudinal_heatmap.png')
    png_diff = os.path.join(out_dir, 'comparacion_diferencias_volumenes.png')

    dibujar_pentagono(vol_old, vol_new, png_pent, dicom_old, dicom_new)
    dibujar_heatmap(vol_old, vol_new, png_heat, dicom_old, dicom_new)
    dibujar_diferencias(xlsx_old, xlsx_new, png_diff)

    pdf_path = os.path.join(out_dir, f"reporte_longitudinal_{paciente}.pdf")
    export_pdf([png_pent, png_heat, png_diff], pdf_path)

    print(f"[OK] PNGs y PDF en: {out_dir}")

if __name__ == "__main__":
    main()
