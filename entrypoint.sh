#!/bin/bash
set -euo pipefail

# Sincronizar skeleton → home (solo archivos/dirs que no existen).
# Esto popula el volume vacío en el primer arranque.
rsync -a --ignore-existing /home/dev-skel/ /home/dev/

# Corregir ownership del home (ignora read-only bind mounts).
chown -R dev:dev /home/dev 2>/dev/null || true

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

exec gosu dev "$@"
