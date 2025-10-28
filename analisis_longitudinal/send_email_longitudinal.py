#!/usr/bin/env python3
import sys
import smtplib
from email.message import EmailMessage
from pathlib import Path

# --- Argumentos ---
nombre_paciente = sys.argv[1]           # Nombre del paciente
reporte_path = Path(sys.argv[2])        # Ruta del PDF longitudinal
mensaje_path = Path(sys.argv[3])        # Plantilla del mensaje
destinatarios_path = Path(sys.argv[4])  # Lista de destinatarios

# --- Leer mensaje base ---
with open(mensaje_path, "r") as f:
    mensaje = f.read()

# Reemplazar placeholders
mensaje = mensaje.replace("{nombre_paciente}", nombre_paciente)
mensaje = mensaje.replace("{tipo_reporte}", "análisis morfovolumétrico longitudinal")

# --- Leer destinatarios ---
with open(destinatarios_path, "r") as f:
    destinatarios = [line.strip() for line in f if line.strip()]

# --- Crear mensaje de correo ---
msg = EmailMessage()
msg["Subject"] = f"Análisis Morfovolumétrico Longitudinal - {nombre_paciente}"
msg["From"] = "neuroz8.pruebas@gmail.com"
msg["To"] = ", ".join(destinatarios)
msg.set_content(mensaje)

# --- Adjuntar el PDF ---
with open(reporte_path, "rb") as f:
    msg.add_attachment(
        f.read(),
        maintype="application",
        subtype="pdf",
        filename=reporte_path.name
    )

# --- Envío SMTP ---
smtp_server = "smtp.gmail.com"
smtp_port = 587
smtp_user = "neuroz8.pruebas@gmail.com"
smtp_pass = "iuuz esfq rsum xamp"  # App password de Gmail

with smtplib.SMTP(smtp_server, smtp_port) as server:
    server.starttls()
    server.login(smtp_user, smtp_pass)
    server.send_message(msg)

print(f"Correo longitudinal enviado correctamente a {', '.join(destinatarios)}.")
