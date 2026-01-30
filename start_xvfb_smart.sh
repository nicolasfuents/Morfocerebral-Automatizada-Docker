#!/usr/bin/env bash
# Xvfb Smart Launcher (Concurrency Safe)
# Busca un Display libre entre :99 y :120 respetando procesos existentes.

# Definimos un directorio de runtime único para este proceso (Fix para QStandardPaths)
export XDG_RUNTIME_DIR="/tmp/runtime-xvfb-$$"
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

for i in {99..120}; do
  LOCK_FILE="/tmp/.X$i-lock"

  # 1. Chequeo NO destructivo: Si el lock existe, verificamos si el proceso está vivo.
  if [ -f "$LOCK_FILE" ]; then
    PID_LOCK=$(head -n 1 "$LOCK_FILE" | tr -d ' \n')
    
    # Si el proceso dueño del lock está corriendo, RESPETAMOS y saltamos al siguiente.
    if kill -0 "$PID_LOCK" 2>/dev/null; then
      echo "[Xvfb] Display :$i ocupado por PID $PID_LOCK. Probando siguiente..."
      continue
    else
      echo "[Xvfb] Display :$i tiene un lock muerto (PID $PID_LOCK). Limpiando..."
      rm -f "$LOCK_FILE"
      rm -f "/tmp/.X11-unix/X$i"
    fi
  fi
  
  # 2. Intentamos levantar Xvfb
  # Usamos 'exec' dentro del subshell o lanzamos directo para capturar bien el PID.
  Xvfb :$i -screen 0 1720x900x24 >/dev/null 2>&1 &
  PID=$!
  
  # 3. Esperamos un toque para ver si levanta
  sleep 2
  
  # 4. Verificamos si sigue vivo
  if kill -0 $PID 2>/dev/null; then
    echo "[Xvfb] Iniciado correctamente en DISPLAY=:$i (PID $PID)"
    export DISPLAY=:$i
    # No hacemos disown acá para que el script padre pueda matarlo al salir si quiere,
    # pero como es 'source', queda en el ambiente.
    return 0 2>/dev/null || exit 0
  else
    # Si murió al intentar arrancar, limpiamos ESTE intento fallido
    echo "[Xvfb] Falló arranque en :$i. Limpiando y reintentando..."
    rm -f "/tmp/.X$i-lock"
    rm -f "/tmp/.X11-unix/X$i"
  fi
done

echo "[Xvfb] ERROR CRÍTICO: No se encontró display libre entre 99 y 120."
rm -rf "$XDG_RUNTIME_DIR" # Limpiamos el dir temporal si fallamos
return 1 2>/dev/null || exit 1