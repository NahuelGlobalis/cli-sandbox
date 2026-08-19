# Instalacion en WSL

## Requisitos

- WSL 2 con Ubuntu.
- Docker Engine accesible desde WSL.
- Docker Compose v2.
- Soporte de `/dev/net/tun` para el sidecar Tailscale.
- Aproximadamente 5 GB libres para la imagen.

Comprueba Docker y Compose:

```bash
docker version
docker compose version
test -c /dev/net/tun
```

Si falta Compose en Ubuntu:

```bash
sudo apt update
sudo apt install docker-compose-v2
```

## Configurar el repositorio

Desde WSL:

```bash
cd /mnt/c/dev/repos/publics/cli-sandbox
cp .env.example .env
```

Edita `.env` y define:

```dotenv
TS_AUTHKEY=tskey-auth-...
TAILSCALE_HOSTNAME=clis-code
```

La key no debe ser efimera. Puede ser de un solo uso porque la identidad se
guarda en el volumen `tailscale-state`.

## Construir y levantar

```bash
docker compose build clis-code
docker compose up -d
docker compose ps
```

El estado esperado es `healthy` para `clis-tailscale` y `clis-code`. Si el
tailnet requiere aprobar dispositivos, primero completa la aprobacion descrita
en [Tailscale](tailscale.md).

## Instalar clis

El symlink permite que el script encuentre `docker-compose.yml` y `.env`:

```bash
mkdir -p ~/.local/bin
ln -sf "$(pwd)/clis" ~/.local/bin/clis
```

Asegura que `~/.local/bin` este en el PATH:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Si copias el script en lugar de usar un symlink, define la ubicacion del repo:

```bash
export CLIS_REPO_DIR=/mnt/c/dev/repos/publics/cli-sandbox
```

Tambien se pueden sobrescribir `CLIS_COMPOSE_FILE` y `CLIS_ENV_FILE`.

## Uso local

```bash
cd /mnt/c/dev/repos/mi-proyecto
clis
clis codex
clis opencode
clis herdr
clis --env API_KEY=valor comando
```

`clis` monta la raiz Git actual y mantiene el subdirectorio desde el que se
invoco. Si no estas dentro de un repo Git, monta el directorio actual.

## Entrar al servicio persistente

Este es el mismo contenedor al que entra Moshi:

```bash
cd /mnt/c/dev/repos/publics/cli-sandbox
docker compose exec -u dev -it clis-code bash
```

Usa este modo para Easy Pair, inspeccionar el daemon Moshi o trabajar sobre
proyectos guardados en `~/.clis-code/projects`.

## Actualizar la imagen

```bash
docker compose build clis-code
docker compose up -d --force-recreate clis-code
```

El home, Tailscale y las claves SSH sobreviven a la recreacion. Si Herdr cambia
de version, revisa sus integraciones con:

```bash
docker compose exec -u dev clis-code herdr integration status --outdated-only
```
