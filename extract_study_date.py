import sys
import pydicom
import os

def get_study_date(dicom_dir):
    # Recorre buscando el primer DICOM valido
    for root, _, files in os.walk(dicom_dir):
        for file in files:
            if file.endswith(".dcm"):
                try:
                    ds = pydicom.dcmread(os.path.join(root, file), stop_before_pixels=True)
                    # Devuelve la fecha (Tag 0008,0020) o la fecha de hoy si falla
                    return ds.get("StudyDate", "UNKNOWN")
                except:
                    continue
    return "UNKNOWN"

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("UNKNOWN")
    else:
        print(get_study_date(sys.argv[1]))