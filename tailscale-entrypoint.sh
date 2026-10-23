#!/bin/sh
# La imagen oficial usa Alpine: este entrypoint requiere solo /bin/sh.
set -eu

# Mantener el daemon vivo durante NeedsMachineAuth, sin el timeout de
# containerboot. El daemon conserva la conexion y recibe la aprobacion.
tailscaled --statedir="$TS_STATE_DIR" --socket="$TS_SOCKET" &
daemon_pid=$!
pause_pid=
cleanup() {
    trap - TERM INT
    if [ -n "$pause_pid" ]; then
        kill "$pause_pid" 2>/dev/null || true
    fi
    kill "$daemon_pid" 2>/dev/null || true
    wait "$daemon_pid" 2>/dev/null || true
}
trap 'exit 0' TERM INT
trap cleanup EXIT

previous_state=
while kill -0 "$daemon_pid" 2>/dev/null; do
    state=$(tailscale --socket="$TS_SOCKET" status --json 2>/dev/null \
        | sed -n 's/.*"BackendState":[[:space:]]*"\([^"]*\)".*/\1/p') || state=
    if [ "$state" != "$previous_state" ]; then
        echo "Tailscale: ${state:-iniciando}."
        previous_state=$state
        if [ "$state" = NeedsMachineAuth ]; then
            echo "Aproba el dispositivo en Tailscale Admin > Machines; esperando sin reiniciar."
        fi
    fi
    case "$state" in
        NeedsLogin|Stopped)
            # Argumentos citados; reutilizar la identidad sin auth key al
            # reanudar un nodo detenido. No repetir login durante aprobacion.
            set -- up --timeout=5s --accept-dns="$TS_ACCEPT_DNS" \
                --hostname="$TS_HOSTNAME" \
                --advertise-exit-node="$CLIS_TS_ADVERTISE_EXIT_NODE" \
                --exit-node="$CLIS_TS_EXIT_NODE" \
                --exit-node-allow-lan-access="$CLIS_TS_EXIT_NODE_ALLOW_LAN_ACCESS"
            if [ "$state" = NeedsLogin ]; then
                set -- "$@" --authkey="$TS_AUTHKEY"
            fi
            tailscale --socket="$TS_SOCKET" "$@" \
                || echo "Tailscale aun no esta listo; nueva comprobacion en 10 segundos."
            ;;
    esac
    sleep 10 &
    pause_pid=$!
    wait "$pause_pid"
    pause_pid=
done

# Una caida real del daemon debe activar la politica restart de Compose.
wait "$daemon_pid" || exit "$?"
exit 1
