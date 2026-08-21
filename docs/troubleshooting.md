# Troubleshooting

## Diagnostico base

Ejecuta desde WSL y conserva la salida, pero no compartas `.env` ni tokens:

```bash
docker compose ps
docker compose logs --tail 100 tailscale
docker compose logs --tail 100 clis-code
docker compose exec -T tailscale tailscale status
docker compose exec -u dev clis-code moshi-hook status
docker compose exec clis-code sshd -t
docker ps --format "table {{.Names}}\t{{.Status}}"
```

## Docker Compose no existe

Sintoma:

```text
docker: 'compose' is not a docker command
```

Solucion en Ubuntu/WSL:

```bash
sudo apt update
sudo apt install docker-compose-v2
docker compose version
```

## clis-code no aparece en Tailscale

`docker run clis-code:latest` no inicia el sidecar. Usa:

```bash
docker compose up -d
```

o el script `clis`, que inicia y valida el sidecar antes de abrir la sesion.

Comprueba:

```bash
docker compose exec -T tailscale tailscale status --json
```

## Invalid cluster node al iniciar clis

Compose 2.7 puede fallar al crear un contenedor efimero con
`network_mode: service:tailscale` sobre Docker 27:

```text
Error response from daemon: invalid cluster node while attaching to network
```

El script `clis` evita esa combinacion: usa Compose para asegurar los servicios
persistentes y `docker run` para adjuntar la sesion al namespace de Tailscale.
Actualiza el script instalado si una copia anterior todavia usa
`docker compose run`.

## NeedsMachineAuth

El nodo esta registrado pero pendiente de aprobacion. Aprueba `clis-code` en
[Tailscale Admin > Machines](https://login.tailscale.com/admin/machines).

El contenedor puede reiniciarse periodicamente mientras espera. No borres el
volumen de estado ni generes keys nuevas para resolver una aprobacion pendiente.

## Moshi muestra login error

Verifica primero que el telefono aparezca `active` en `tailscale status`.
Despues comprueba la clave:

```bash
docker compose exec clis-code \
  ls -l /home/dev/.ssh/authorized_keys
docker compose exec -u dev clis-code moshi-hook host list
```

Si `authorized_keys` no existe, Easy Pair no termino. Elimina el host fallido de
Moshi y repite desde WSL:

```bash
docker compose exec -u dev -it clis-code \
  moshi-hook host setup --user dev
```

Selecciona MagicDNS, escanea el QR y espera la confirmacion. Usa el usuario
`dev`, conexion `Auto` y no actives Tailscale SSH.

## Comando no encontrado desde Moshi

Las conexiones abiertas antes de actualizar `sshd_config` conservan el PATH
anterior. Cierra completamente la sesion y reconecta.

Comprueba la configuracion efectiva:

```bash
docker compose exec clis-code sh -lc "sshd -T | grep '^setenv'"
docker compose exec -u dev clis-code sh -lc \
  "command -v herdr; command -v codex; command -v opencode"
```

Solucion temporal dentro de la sesion remota:

```bash
export PATH="/opt/herdr/bin:/home/dev/.local/bin:/opt/pnpm-global/bin:/opt/antigravity/bin:/opt/devin:$PATH"
```

## Codex u OpenCode no aparecen en Moshi

```bash
docker compose exec -u dev clis-code \
  moshi-hook install --target codex --target opencode
docker compose restart clis-code
docker compose exec -u dev clis-code moshi-hook status
```

El daemon debe estar `paired`, los hooks deben estar `current` y el log debe
mostrar un WebSocket conectado. Crea sesiones nuevas de los agentes.

## Herdr no aparece o no adjunta

```bash
docker compose exec -u dev clis-code herdr session list
docker compose exec -u dev clis-code herdr status server
docker compose exec -u dev clis-code herdr integration status
docker ps --format "table {{.Names}}\t{{.Status}}"
```

Si el servidor vivia en un contenedor `clis-code-run-*` que ya termino, la
sesion no puede recuperarse como proceso activo. Crea una nueva sesion con
nombre y manten vivo el contenedor que aloja el servidor.

Si una integracion esta `outdated`:

```bash
herdr integration install codex
herdr integration install opencode
```

## --port no funciona con clis

Es intencional. La red se comparte con el sidecar Tailscale y no admite
publicacion de puertos Docker. Haz que el proceso escuche en `0.0.0.0` y usa
`clis-code:<puerto>` desde el tailnet.

## Docker no funciona dentro del contenedor

Comprueba el socket y el grupo efectivo:

```bash
ls -l /var/run/docker.sock
id
docker info
```

El entrypoint agrega `dev` al grupo con el GID del socket. Recrea el contenedor
si el daemon del host cambio el GID:

```bash
docker compose up -d --force-recreate clis-code
```

## No borrar volumenes por accidente

`docker compose down -v` elimina identidad Tailscale y claves de host SSH. Usa
normalmente:

```bash
docker compose down
docker compose up -d
```
