#!/usr/bin/env bash
# Xvfb Smart Launcher - V4 (Redirección Agresiva / Silenciosa)
# Busca un Display libre entre :99 y :120.

for i in {99..120}; do
  # 1. Limpieza preventiva de basura en el contenedor
  rm -f /tmp/.X$i-lock
  rm -f /tmp/.X11-unix/X$i
  
  # 2. Intentamos levantar Xvfb "ENCAPSULADO"
  # Los paréntesis y la redirección aseguran que si falla, no imprima NADA en el log.
  ( Xvfb :$i -screen 0 1720x900x24 >/dev/null 2>&1 ) &
  PID=$!
  
  # 3. Esperamos a que arranque o falle (2 seg)
  sleep 2
  
  # 4. Verificamos si sigue vivo
  if kill -0 $PID 2>/dev/null; then
    echo "[Xvfb] Iniciado correctamente en DISPLAY=:$i (PID $PID)"
    export DISPLAY=:$i
    disown $PID
    return 0 2>/dev/null || exit 0
  fi
  
  # Si murió, limpiamos y seguimos probando el siguiente
  rm -f /tmp/.X$i-lock
done

echo "[Xvfb] ERROR CRÍTICO: No se pudo iniciar Xvfb en ningún puerto del 99 al 120."
return 1 2>/dev/null || exit 1