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
    f"Estimado/a,\n\n"
    f"Le informamos que el procesamiento morfovolumétrico del paciente {nombre_paciente} se ha completado exitosamente.\n\n"
    "Adjunto a este correo encontrará el reporte correspondiente generado automáticamente por el sistema.\n\n"
    "Ante cualquier duda o inconveniente, por favor no dude en comunicarse con el equipo técnico.\n\n"
    "Saludos cordiales,"
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
