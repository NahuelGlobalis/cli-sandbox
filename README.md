# Docker image para CLIs de codificación (Devin + Antigravity + OpenCode) + Chrome/Playwright

Contenedor Ubuntu 24.04 con las CLIs de codificación asistida por IA más populares, listo para usar sin riesgos en el sistema host. También incluye Google Chrome y Chromium para Playwright.

## CLIs y herramientas instaladas

- **Devin CLI** (`devin`) – Cognition AI
- **Antigravity CLI** (`agy`) – Google
- **OpenCode CLI** (`opencode`) – Anomaly
- **pnpm** – gestor de paquetes Node.js
- **uv** – gestor de Python y entornos
- **Google Chrome** + **Chromium** para Playwright
- **Docker CLI** – acceso al daemon del host via socket mount (Docker-outside-of-Docker)

## Requisitos

- Docker Desktop o Docker Engine en Windows/Linux/macOS
- ~ 5 GB de espacio libre (imagen grande por navegadores y Node)

## Construir la imagen

```powershell
docker build -t clis-code:latest .
```

## Ejecutar el contenedor

### Básico (sin persistencia)

```powershell
docker run -it --rm clis-code:latest
```

### Recomendado: persistir credenciales y proyectos

La imagen usa un **único volume para todo el home** (`/home/dev`). Esto persiste automáticamente configs, credenciales, cache y estado de todas las CLIs, sin necesidad de enumerar paths individuales. El entrypoint sincroniza un skeleton preconfigurado en el primer arranque.

```powershell
docker run -it --rm `
  -v "${PWD}:/home/dev/projects" `
  -w /home/dev/projects `
  -v "${env:USERPROFILE}\.clis-code\home:/home/dev" `
  -v "${env:USERPROFILE}\.ssh:/home/dev/.ssh:ro" `
  clis-code:latest
```

En Linux/macOS:

```bash
docker run -it --rm \
  -v "$PWD":/home/dev/projects \
  -w /home/dev/projects \
  -v "$HOME/.clis-code/home":/home/dev \
  -v "$HOME/.ssh":/home/dev/.ssh:ro \
  clis-code:latest
```

> **Migración desde versiones anteriores:** si tenés los directorios individuales
> (`~/.clis-code/devin`, `~/.clis-code/gemini`, etc.), podés migrarlos al nuevo
> esquema copiándolos dentro de `~/.clis-code/home/` respetando la estructura de
> directorios de Linux (por ejemplo: `~/.clis-code/home/.config/devin/`).

## Credenciales: cómo funciona la persistencia

La imagen monta **un solo volume** en `/home/dev` que persiste todo el home del usuario `dev`:

```
~/.clis-code/home/          # → /home/dev (volume principal)
├── .config/                # configs de Devin, OpenCode, etc.
├── .local/share/           # credenciales, sesiones, datos de uv
├── .local/state/           # estado de OpenCode
├── .cache/                 # cache de OpenCode, uv, etc.
├── .gemini/                # token OAuth y conversaciones de Antigravity
├── .gitconfig              # configuración de git (generada en el skeleton)
└── projects/               # código de trabajo (se overlay con $PWD)
```

**Tools fuera del home (no se pierden al reconstruir):**

| Tool | Ubicación | Por qué |
|---|---|---|
| Devin | `/opt/devin/` | Binario separado de credenciales |
| Antigravity | `/opt/antigravity/bin/` | Binario fuera del volume |
| pnpm global | `/opt/pnpm-global/` | OpenCode, Playwright |
| Playwright browsers | `/opt/playwright-browsers/` | Chromium |
| Python (uv) | `/opt/uv/python/` | Interprete fuera del volume |

> **Seguridad:** `~/.clis-code/home` contiene tokens de acceso. No lo subas a Git ni lo compartas. Git y SSH se montan en modo lectura desde el host; el home del contenedor permanece escribible para persistir autenticación y estado.

## Autenticar cada CLI

Dentro del contenedor corre:

### Devin

```bash
devin auth login
```

Si estás en un contenedor sin navegador interactivo, usa el flujo manual de token:

```bash
devin auth login --force-manual-token-flow
```

### Antigravity

```bash
agy
```

En sesiones remotas sin navegador, `agy` detecta SSH y muestra una URL para autenticar localmente. También puedes copiar un token existente de otra máquina a `/home/dev/.gemini/antigravity-cli/antigravity-oauth-token`.

### OpenCode

```bash
opencode auth login
```

O configura providers directamente con `/connect` dentro de la TUI.

## Usar Docker dentro del contenedor

La imagen incluye el CLI de Docker (`docker`), `docker buildx` y `docker compose`. Se usa el patrón **Docker-outside-of-Docker**: el contenedor no ejecuta un daemon propio, sino que se conecta al daemon del host montando `/var/run/docker.sock`.

```bash
docker ps
docker build -t mi-app .
docker compose up -d
```

> **Nota:** al montar el socket, los contenedores lanzados desde dentro se ejecutan en el host, no anidados. Ten cuidado: equivalen a ejecutarlos directamente en el host.

## Usar Playwright con Chrome

La imagen incluye:

- `google-chrome` (Google Chrome estable)
- `playwright` disponible globalmente en el `PATH`
- Chromium descargado en `/home/dev/.cache/ms-playwright`

### Con Node.js y pnpm

Para proyectos que declaran Playwright como dependencia, usa el binario local:

```bash
pnpm exec playwright test
```

Si solo quieres usar la versión incluida en la imagen:

```bash
playwright test
```

### Con Python y uv

```bash
uv init my-e2e
uv add pytest-playwright
uv run pytest
```

Para correr Chrome en modo headless:

```bash
google-chrome --headless --no-sandbox --disable-gpu --dump-dom https://example.com
```

> **Nota:** en contenedores Docker es normal necesitar `--no-sandbox` para Chrome/Chromium.

## Script `clis` (acceso rápido)

El repositorio incluye un script `clis` que lanza el contenedor con todos los mounts configurados correctamente, montando el directorio actual como workspace:

### Instalación

**Opción A: symlink (recomendado)**

```bash
# Desde la raíz del repositorio clonado
ln -sf "$(pwd)/clis" ~/.local/bin/clis
```

**Opción B: copiar el script**

```bash
cp clis ~/.local/bin/clis
chmod +x ~/.local/bin/clis
```

> Requiere que `~/.local/bin` esté en tu `PATH`. En la mayoría de distribuciones Linux ya lo está. Si no:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Uso

```bash
# Abrir bash interactivo en el directorio actual
clis

# Ejecutar una CLI directamente
clis devin
clis agy
clis opencode

# Ejecutar cualquier comando dentro del contenedor
clis pnpm install
clis uv run python script.py

# Exponer puertos (ej: servidor web de una CLI)
clis --port 3000 opencode
clis -p 8080:80 -p 8443:443 devin

# Pasar variables de entorno
clis --env API_KEY=secret opencode
clis -e MY_VAR=value agy
```

El script verifica que la imagen exista antes de ejecutar. Si no existe, muestra cómo crearla:

```bash
docker build -t clis-code:latest .
```

El flag `--init` se pasa automáticamente a `docker run` para manejo correcto de señales (Ctrl+C, procesos zombie).

El script monta `$PWD` como `/home/dev/projects` y un volume en `~/.clis-code/home` como `/home/dev` para persistir credenciales y configuración de todas las CLIs.

## Docker Compose

Existe un `docker-compose.yml` de ejemplo con `init: true` y `restart: unless-stopped`. Para usarlo:

```powershell
docker-compose run --rm clis-code
```

O en segundo plano:

```powershell
docker-compose up -d clis-code
```

## Versionado

La imagen usa tags por versión además de `:latest`:

- `clis-code:latest` — última versión
- `clis-code:1.0.0` — versión específica (semver)
- `ghcr.io/nahue/clis-code:1.0.0` — imagen publicada en GHCR

Para construir una versión específica:

```bash
docker build -t clis-code:1.0.0 .
```

Los tags `v*` en Git disparan automáticamente la publicación a GitHub Container Registry (ver CI/CD).

## Arquitectura

La imagen soporta únicamente `linux/amd64` porque Google Chrome y algunas CLIs propietarias no distribuyen actualmente binarios para ARM64.

Para construirla localmente:

```bash
docker buildx build --platform linux/amd64 --load -t clis-code:latest .
```

En Apple Silicon o servidores ARM, Docker Desktop puede ejecutarla mediante emulación, con un coste de rendimiento.

## CI/CD

El repositorio incluye dos workflows de GitHub Actions:

- **`docker-build.yml`** — construye la imagen en cada push a `main` y en PRs. Usa cache de capas (`type=gha`).
- **`docker-publish.yml`** — publica la imagen a GitHub Container Registry (GHCR) en cada tag `v*`. Genera tags semver automáticamente (`1.0.0`, `1.0`, `latest`).

## Consejos

- **Usuario:** la imagen corre con el usuario `dev` (uid 1000) para evitar escribir como root en tu host.
- **Aislamiento:** los procesos se ejecutan como `dev` dentro del contenedor, pero los volúmenes montados siguen exponiendo datos del host.
- **Persistencia:** un solo volume en `~/.clis-code/home` persiste todo el home. Las herramientas (binarios, navegadores, Python) viven en `/opt` y sobreviven a rebuilds. El entrypoint sincroniza un skeleton preconfigurado en el primer arranque.
- **Actualizar CLIs:** reconstruye la imagen con `docker build --no-cache -t clis-code:latest .` o corre los comandos de upgrade dentro del contenedor.
- **Reducir tamaño:** si no necesitas Google Chrome, elimina el bloque de instalación de `google-chrome-stable` y su comprobación en el healthcheck.
- **Arquitectura:** la imagen se construye y publica únicamente para `linux/amd64`.
- **Versiones:** las herramientas con versión configurable usan argumentos `ARG` en el `Dockerfile`; los instaladores propietarios siguen dependiendo de sus scripts oficiales remotos.

## Troubleshooting

### `Permission denied` al montar volúmenes en Windows

Asegúrate de que Docker Desktop tenga habilitado el recurso compartido (`Settings > Resources > File Sharing`) o usa rutas dentro de `C:\Users\<tu usuario>\`.

### `devin`, `agy` o `opencode` no se encuentran

El `PATH` está configurado para `/home/dev/.local/bin` y `/home/dev/.pnpm-global/bin`. Si un script no agregó el binario correctamente, recarga el shell:

```bash
export PATH="$HOME/.local/bin:$HOME/.pnpm-global/bin:$PATH"
```

### Playwright no encuentra el navegador

Reinstala Chromium dentro del contenedor:

```bash
playwright install chromium
```

### Python con uv

`uv` y Python 3.12 vienen preinstalados. Python se conserva en `/opt/uv/python` para que el volumen de datos de uv no lo oculte. Para usarlo en un proyecto:

```bash
uv init
uv add <paquete>
uv run python script.py
```

## Archivos del repositorio

- `Dockerfile` – definición de la imagen
- `docker-compose.yml` – orquestación de ejemplo
- `clis` – script de acceso rápido para lanzar el contenedor
- `README.md` – este documento
- `LICENSE` – licencia MIT
- `.github/workflows/docker-build.yml` – CI: build en push/PR
- `.github/workflows/docker-publish.yml` – CD: publish a GHCR en tags
