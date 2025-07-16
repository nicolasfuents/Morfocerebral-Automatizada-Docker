# send_email.py

import sys
import smtplib
from email.message import EmailMessage
from pathlib import Path

nombre_paciente = sys.argv[1]
reporte_path = Path(sys.argv[2])
mensaje_path = Path(sys.argv[3])
destinatarios_path = Path(sys.argv[4])

# Leer mensaje
with open(mensaje_path, "r") as f:
    mensaje = f.read()
mensaje = mensaje.replace("{nombre_paciente}", nombre_paciente)


# Leer destinatarios
with open(destinatarios_path, "r") as f:
    destinatarios = [line.strip() for line in f if line.strip()]

msg = EmailMessage()
msg["Subject"] = f"Reporte Morfovolumétrico - {nombre_paciente}"
msg["From"] = "neuroz8.pruebas@gmail.com"
msg["To"] = ", ".join(destinatarios)
msg.set_content(mensaje)

with open(reporte_path, "rb") as f:
    msg.add_attachment(f.read(), maintype="application", subtype="pdf", filename=reporte_path.name)

smtp_server = "smtp.gmail.com"
smtp_port = 587
smtp_user = "neuroz8.pruebas@gmail.com"
smtp_pass = "iuuz esfq rsum xamp"

with smtplib.SMTP(smtp_server, smtp_port) as server:
    server.starttls()
    server.login(smtp_user, smtp_pass)
    server.send_message(msg)

print("Correo enviado correctamente.")
