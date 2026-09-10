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
    # El GID del socket puede ya estar usado por un grupo del sistema
    # (p. ej. systemd-journal en GID 999). Reusar ese grupo en vez de
    # intentar crear uno nuevo con un GID colisionado.
    EXISTING_GROUP="$(getent group "${SOCKET_GID}" | cut -d: -f1 || true)"
    if [[ -n "$EXISTING_GROUP" ]]; then
        DOCKER_GROUP="$EXISTING_GROUP"
    else
        if ! getent group docker >/dev/null 2>&1; then
            groupadd -g "${SOCKET_GID}" docker
        fi
        DOCKER_GROUP="docker"
    fi
    if ! id dev | grep -q "(${DOCKER_GROUP})"; then
        usermod -aG "${DOCKER_GROUP}" dev
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

# SSH agent interno: las claves del host se montan en /home/dev/.git-ssh
# (read-only) y se cargan en un ssh-agent propio. Así Git por SSH funciona sin
# depender del agent del host ni montar ~/.ssh sobre /home/dev/.ssh, lo que
# ocultaría el authorized_keys persistente que Easy Pair crea para Moshi.
# Corre en el persistente y en las sesiones efímeras de `clis` (ambas ejecutan
# este entrypoint); cada contenedor obtiene su propio agent en /tmp.
if [[ -d /home/dev/.git-ssh ]]; then
    rm -f /tmp/clis-ssh-agent.sock
    gosu dev ssh-agent -a /tmp/clis-ssh-agent.sock >/dev/null 2>&1 &
    for _ in {1..20}; do
        [[ -S /tmp/clis-ssh-agent.sock ]] && break
        sleep 0.1
    done
    if [[ -S /tmp/clis-ssh-agent.sock ]]; then
        export SSH_AUTH_SOCK=/tmp/clis-ssh-agent.sock
        for _key in id_ed25519 id_ecdsa id_rsa id_dsa; do
            _keyfile="/home/dev/.git-ssh/${_key}"
            if [[ -f "$_keyfile" ]]; then
                # SSH_ASKPASS_REQUIRE=force evita colgar pidiendo passphrase en
                # el tty: las claves con passphrase se omiten con warning.
                if SSH_ASKPASS=/bin/false SSH_ASKPASS_REQUIRE=force \
                        gosu dev ssh-add "$_keyfile" </dev/null >/dev/null 2>&1; then
                    :
                else
                    echo "WARN: no se pudo cargar ${_keyfile} (¿passphrase? el agent del host ya no se reenvía)." >&2
                fi
            fi
        done
        # known_hosts del host para que Git/SSH verifique hosts sin prompt.
        if [[ -f /home/dev/.git-ssh/known_hosts && ! -e /home/dev/.ssh/known_hosts ]]; then
            install -d -m 0700 -o dev -g dev /home/dev/.ssh
            ln -s /home/dev/.git-ssh/known_hosts /home/dev/.ssh/known_hosts
        fi
    else
        echo "WARN: no se pudo iniciar el ssh-agent interno en /tmp/clis-ssh-agent.sock." >&2
    fi
else
    echo "WARN: /home/dev/.git-ssh no existe; Git por SSH no tendrá claves del host." >&2
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
