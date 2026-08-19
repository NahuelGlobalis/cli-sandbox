#!/bin/bash
set -euo pipefail

# Sincronizar skeleton → home (solo archivos/dirs que no existen).
# Esto popula el volume vacío en el primer arranque.
rsync -a --ignore-existing /home/dev-skel/ /home/dev/

# Corregir ownership sin recorrer mounts anidados como projects o skills.
find /home/dev -xdev -exec chown dev:dev {} + 2>/dev/null || true

# Generar claves de host SSH persistentes en el primer arranque. Se guardan
# fuera de la imagen para que Moshi no vea una identidad distinta al recrear
# el contenedor.
install -d -m 0700 -o root -g root /var/lib/ssh
if [[ ! -f /var/lib/ssh/ssh_host_ed25519_key ]]; then
    ssh-keygen -q -t ed25519 -N '' -f /var/lib/ssh/ssh_host_ed25519_key
fi
if [[ ! -f /var/lib/ssh/ssh_host_ecdsa_key ]]; then
    ssh-keygen -q -t ecdsa -N '' -f /var/lib/ssh/ssh_host_ecdsa_key
fi
if [[ ! -f /var/lib/ssh/ssh_host_rsa_key ]]; then
    ssh-keygen -q -t rsa -b 3072 -N '' -f /var/lib/ssh/ssh_host_rsa_key
fi
chown -R root:root /var/lib/ssh
chmod 0600 /var/lib/ssh/ssh_host_*_key
chmod 0644 /var/lib/ssh/ssh_host_*_key.pub

# Si el socket de Docker está montado, asegurar que dev pueda acceder.
if [[ -S /var/run/docker.sock ]]; then
    SOCKET_GID="$(stat -c '%g' /var/run/docker.sock)"
    if ! getent group docker >/dev/null 2>&1; then
        groupadd -g "${SOCKET_GID}" docker
    fi
    if ! id dev | grep -q "docker"; then
        usermod -aG docker dev
    fi
fi

# El cliente Tailscale de esta imagen usa el daemon del sidecar. Dar acceso al
# usuario dev al socket permite que Easy Pair prefiera el nombre MagicDNS.
if [[ -n "${TAILSCALE_SOCKET:-}" ]]; then
    for _ in {1..30}; do
        [[ -S "${TAILSCALE_SOCKET}" ]] && break
        sleep 1
    done
    if [[ -S "${TAILSCALE_SOCKET}" ]]; then
        chmod 0660 "${TAILSCALE_SOCKET}"
        chown root:dev "${TAILSCALE_SOCKET}"
    else
        echo "WARN: no se encontró el socket de Tailscale: ${TAILSCALE_SOCKET}" >&2
    fi
fi

# Las sesiones efímeras creadas por `clis` comparten la red de Tailscale con el
# servicio persistente, por lo que no deben intentar ocupar otra vez sus puertos.
if [[ "${CLIS_REMOTE_SERVICES:-1}" == "1" ]]; then
    # OpenSSH normal (no Tailscale SSH) es necesario para Easy Pair y para que
    # Mosh pueda iniciar su transporte UDP.
    mkdir -p /run/sshd
    /usr/sbin/sshd

    # El daemon mantiene las notificaciones y vistas de agentes. Antes de hacer
    # pair puede quedar esperando configuración o terminar sin afectar SSH/Mosh.
    if [[ "${MOSHI_HOOK_AUTOSTART:-1}" == "1" ]]; then
        install -d -m 0755 -o dev -g dev /home/dev/.local/state/moshi-hook
        gosu dev moshi-hook serve \
            >>/home/dev/.local/state/moshi-hook/serve.log 2>&1 &
    fi
fi

exec gosu dev "$@"
