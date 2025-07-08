# send_email.py

import sys
import smtplib
from email.message import EmailMessage
from pathlib import Path

# Argumentos
nombre_paciente = sys.argv[1]
reporte_path = Path(sys.argv[2])
destinatarios = sys.argv[3:]

msg = EmailMessage()
msg["Subject"] = f"Reporte Morfovolumétrico - {nombre_paciente}"
msg["From"] = "neuroz8.pruebas@gmail.com"
msg["To"] = ", ".join(destinatarios)
msg.set_content(
    f"Estimados,\n\n"
    "Si recibieron este correo quiere decir que las volumetrías se están procesando y enviando vía email automáticamente desde la z8.\n\n"
    f"A continuación, se adjunta el reporte morfovolumétrico generado para el paciente {nombre_paciente}."
)

# Adjuntar PDF
with open(reporte_path, "rb") as f:
    msg.add_attachment(f.read(), maintype="application", subtype="pdf", filename=reporte_path.name)

# Configuración SMTP (Gmail)
smtp_server = "smtp.gmail.com"
smtp_port = 587
smtp_user = "neuroz8.pruebas@gmail.com"
smtp_pass = "iuuz esfq rsum xamp"

with smtplib.SMTP(smtp_server, smtp_port) as server:
    server.starttls()
    server.login(smtp_user, smtp_pass)
    server.send_message(msg)

print("Correo enviado correctamente.")
