# Docker image para CLIs de codificación (Devin + Antigravity + OpenCode + Codex + Herdr) + Chrome/Playwright

Contenedor Ubuntu 24.04 con las CLIs de codificación asistida por IA más populares, listo para usar sin riesgos en el sistema host. También incluye Google Chrome y Chromium para Playwright.

## CLIs y herramientas instaladas

- **Devin CLI** (`devin`) – Cognition AI
- **Antigravity CLI** (`agy`) – Google
- **OpenCode CLI** (`opencode`) – Anomaly
- **Codex CLI** (`codex`) – OpenAI
- **Herdr** (`herdr`) – multiplexor de terminal para agentes
- **Moshi Hook** (`moshi-hook`) – Easy Pair, notificaciones y vistas de agentes
- **OpenSSH + Mosh + tmux** – acceso remoto y sesiones persistentes
- **Tailscale CLI** – usa el daemon del sidecar para descubrir MagicDNS
- **pnpm** – gestor de paquetes Node.js
- **uv** – gestor de Python y entornos
- **Google Chrome** + **Chromium** para Playwright
- **Docker CLI** – acceso al daemon del host via socket mount (Docker-outside-of-Docker)

## Requisitos

- Docker Desktop o Docker Engine con Docker Compose v2 en Windows/Linux/macOS
- ~ 5 GB de espacio libre (imagen grande por navegadores y Node)

Para el acceso desde el celular también necesitás una cuenta de Tailscale y las
apps de [Tailscale](https://tailscale.com/download) y
[Moshi](https://getmoshi.app/) instaladas en el teléfono.

## Documentación

Las guías detalladas están organizadas por tema en [`docs/`](docs/README.md):

- [Arquitectura y modos de ejecución](docs/architecture.md)
- [Instalación en WSL](docs/setup-wsl.md)
- [Tailscale y MagicDNS](docs/tailscale.md)
- [Moshi, Easy Pair y hooks](docs/moshi.md)
- [Codex, OpenCode y sesiones Herdr](docs/agents-and-herdr.md)
- [Troubleshooting](docs/troubleshooting.md)

## Construir la imagen

```powershell
docker build -t clis-code:latest .
```

Durante cada build, Devin, Antigravity, OpenCode, Codex y Herdr resuelven su
última versión estable. Sus manifests o metadatos remotos forman parte de la
clave de caché de Docker, por lo que una nueva release invalida automáticamente
la capa de instalación correspondiente. Las CLIs se actualizan al reconstruir
la imagen, no al ejecutar el contenedor.

## Ejecutar el contenedor

### Básico (sin persistencia ni Tailscale)

```powershell
docker run -it --rm clis-code:latest
```

### Recomendado: persistir credenciales y proyectos

La imagen usa un **volume principal para todo el home** (`/home/dev`). Esto persiste automáticamente configs, credenciales, cache y estado de todas las CLIs, sin necesidad de enumerar paths individuales. Las skills se comparten por separado con el host y el entrypoint sincroniza un skeleton preconfigurado en el primer arranque.

```powershell
docker run -it --rm `
  -v "${PWD}:/home/dev/projects" `
  -w /home/dev/projects `
  -v "${env:USERPROFILE}\.clis-code\home:/home/dev" `
  -v "${env:USERPROFILE}\.agents\skills:/home/dev/.agents/skills" `
  -v "${env:USERPROFILE}\.ssh:/home/dev/.ssh:ro" `
  clis-code:latest
```

En Linux/macOS:

```bash
docker run -it --rm \
  -v "$PWD":/home/dev/projects \
  -w /home/dev/projects \
  -v "$HOME/.clis-code/home":/home/dev \
  -v "$HOME/.agents/skills":/home/dev/.agents/skills \
  -v "$HOME/.ssh":/home/dev/.ssh:ro \
  clis-code:latest
```

> **Migración desde versiones anteriores:** si tenés los directorios individuales
> (`~/.clis-code/devin`, `~/.clis-code/gemini`, etc.), podés migrarlos al nuevo
> esquema copiándolos dentro de `~/.clis-code/home/` respetando la estructura de
> directorios de Linux (por ejemplo: `~/.clis-code/home/.config/devin/`).

## Credenciales: cómo funciona la persistencia

La imagen monta un volume principal en `/home/dev` que persiste todo el home del usuario `dev`:

```
~/.clis-code/home/          # → /home/dev (volume principal)
├── .config/                # configs de Devin, OpenCode, Herdr, etc.
├── .local/share/           # credenciales, sesiones, datos de uv
├── .local/state/           # estado de OpenCode
├── .cache/                 # cache de OpenCode, uv, etc.
├── .gemini/                # token OAuth y conversaciones de Antigravity
├── .gitconfig              # configuración de git (generada en el skeleton)
└── projects/               # código de trabajo (se overlay con $PWD)
```

Además, `~/.agents/skills` se monta en `/home/dev/.agents/skills` con lectura y
escritura. Las skills instaladas o modificadas desde el host o el contenedor se
comparten inmediatamente entre ambos.

**Tools fuera del home (no se pierden al reconstruir):**

| Tool | Ubicación | Por qué |
|---|---|---|
| Devin | `/opt/devin/` | Binario separado de credenciales |
| Antigravity | `/opt/antigravity/bin/` | Binario fuera del volume |
| Herdr | `/opt/herdr/bin/` | Binario fuera del volume; config en el home |
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

## Usar Herdr

Inicia Herdr desde cualquier proyecto:

```bash
herdr
```

Su configuración se guarda en `/home/dev/.config/herdr/config.toml` mediante
`HERDR_CONFIG_PATH`. Como `/home/dev` está montado en
`~/.clis-code/home`, los ajustes, plugins e integraciones sobreviven a la
recreación del contenedor.

Para generar una configuración completa como punto de partida:

```bash
herdr --default-config > "${HERDR_CONFIG_PATH}"
```

Herdr detecta los agentes instalados. Las integraciones opcionales agregan
estado y restauración de sesiones cuando el agente lo admite:

```bash
herdr integration install codex
herdr integration install devin
herdr integration install opencode
```

## Acceso desde el celular con Tailscale + Moshi

El Compose incluye un sidecar oficial de Tailscale y hace que `clis-code`
comparta su red. OpenSSH escucha dentro del tailnet y Mosh usa su rango UDP
normal (`60000:61000`) sin publicar ningún puerto en Internet.

### 1. Registrar el contenedor en Tailscale

Generá una auth key en
[Tailscale Admin > Keys](https://login.tailscale.com/admin/settings/keys). Para
este contenedor persistente no marques el nodo como `ephemeral`; una key de un
solo uso alcanza porque la identidad queda guardada en el volume.
Después creá tu archivo local de configuración:

```powershell
Copy-Item .env.example .env
notepad .env
```

Pegá la key en `TS_AUTHKEY`, construí la imagen y levantá ambos servicios:

```powershell
docker compose build clis-code
docker compose up -d
docker compose ps
```

Si el tailnet tiene habilitada la aprobación de dispositivos, entra a
[Tailscale Admin > Machines](https://login.tailscale.com/admin/machines) y
aprobá el nodo `clis-code`. Hasta entonces aparecerá como pendiente, el estado
será `NeedsMachineAuth` y `clis` indicará que falta esa aprobación.

El estado del nodo y su nombre MagicDNS se pueden comprobar así:

```powershell
docker compose exec -u dev clis-code tailscale status
docker compose exec -u dev clis-code tailscale ip -4
```

La identidad de Tailscale queda en un volume y `TS_AUTH_ONCE=true` evita
reautenticar el nodo en cada reinicio. El archivo `.env` contiene un secreto y
está ignorado por Git.

### 2. Emparejar Moshi

En el celular, iniciá sesión en la app de Tailscale con la misma cuenta y dejá
el túnel activo. Luego abrí Moshi y ejecutá en la PC:

```powershell
docker compose exec -u dev -it clis-code moshi-hook host setup --user dev
```

Escaneá desde Moshi el QR de Easy Pair. El comando detecta el nombre MagicDNS,
Moshi genera una clave Ed25519 exclusiva en el teléfono y sólo agrega la clave
pública a `/home/dev/.ssh/authorized_keys` dentro del home persistente.

Usá **Auto** como tipo de conexión. No habilites Tailscale SSH: Moshi necesita
OpenSSH normal sobre Tailscale para Easy Pair y para iniciar Mosh.

### 3. Abrir Herdr y activar eventos de agentes

Una vez conectado desde Moshi:

```bash
cd ~/projects
herdr
```

Para recibir aprobaciones, finalizaciones y vistas de Codex/OpenCode en Moshi,
copiá el token de `Moshi > Settings > Hooks` y corré dentro de la conexión:

```bash
moshi-hook pair --token <token-de-moshi>
moshi-hook install
```

Reiniciá una vez el servicio para asegurar que el daemon quede activo con el
nuevo pairing:

```powershell
docker compose restart clis-code
```

Diagnóstico rápido:

```powershell
docker compose logs tailscale
docker compose exec -u dev clis-code moshi-hook status
docker compose exec clis-code sshd -t
```

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

El repositorio incluye un script `clis` que lanza el contenedor con los mounts
configurados correctamente. Monta la raíz `CLIS_PROJECTS_ROOT` y conserva dentro
del contenedor la ruta relativa desde la que ejecutaste el comando.

### Instalación

**Opción A: symlink (recomendado)**

```bash
# Desde la raíz del repositorio clonado
mkdir -p ~/.local/bin
ln -sf "$(pwd)/clis" ~/.local/bin/clis
```

**Opción B: copiar el script**

```bash
cp clis ~/.local/bin/clis
chmod +x ~/.local/bin/clis
echo 'export CLIS_REPO_DIR="/ruta/al/repositorio/clis-code"' >> ~/.bashrc
```

Al copiarlo, `CLIS_REPO_DIR` debe apuntar al clon que contiene
`docker-compose.yml` y `.env`. El symlink detecta esa ruta automáticamente.

> Requiere que `~/.local/bin` esté en tu `PATH`. En la mayoría de distribuciones Linux ya lo está. Si no:
```bash
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

### Uso

```bash
# Construir la imagen
clis build

# Levantar el entorno y entrar al contenedor persistente
clis up

# Levantar el entorno en segundo plano y volver al host
clis up -d

# Bajar todo el entorno desde cualquier directorio
clis down

# Abrir bash interactivo en el directorio actual
cd /mnt/c/dev/repos/mi-proyecto
clis

# Ejecutar una CLI directamente
clis devin
clis agy
clis opencode
clis codex
clis herdr

# Ejecutar cualquier comando dentro del contenedor
clis pnpm install
clis uv run python script.py

# Pasar variables de entorno
clis --env API_KEY=secret opencode
clis -e MY_VAR=value agy
```

`clis build` construye la imagen `clis-code:latest`. `clis up` levanta el
sidecar y el servicio persistente, valida Tailscale y SSH, y abre Bash dentro
del servicio persistente. Con `clis up -d` realiza el arranque en segundo plano
y vuelve al host. `clis down` cierra las sesiones efimeras, elimina los
contenedores sin borrar volumenes y conserva la identidad de Tailscale, claves
y credenciales.

Los demas comandos crean una sesion efimera con `docker run`. Compose levanta
automaticamente el sidecar `clis-tailscale`, espera a que este sano y comparte
con la sesion su red, socket de Tailscale, Docker socket, home persistente,
credenciales, skills y claves SSH. La raiz
`CLIS_PROJECTS_ROOT` (`/mnt/c/dev` por defecto) se monta completa en
`/home/dev/projects`.

El script verifica que la imagen exista antes de ejecutar. Si no existe, muestra cómo crearla:

```bash
docker compose build clis-code
```

La configuración `init: true` del servicio maneja correctamente señales y
procesos zombie. Las sesiones efímeras no arrancan otro SSH ni otro Moshi Hook,
evitando conflictos de puertos con el servicio persistente.

El script conserva la ruta relativa desde `CLIS_PROJECTS_ROOT`: si se invoca en
`/mnt/c/dev/repos/mi-proyecto/src`, abre
`/home/dev/projects/repos/mi-proyecto/src`. La raíz completa queda visible tanto
en sesiones `clis` como desde Moshi. El home persiste en
`~/.clis-code/home` y las skills se comparten desde `~/.agents/skills`.

No se publican puertos con `-p` porque el contenedor comparte el namespace de
red de Tailscale. Para exponer un servidor al tailnet, hacelo escuchar en
`0.0.0.0` y accedé a `clis-code:<puerto>` por MagicDNS.

## Docker Compose

El `docker-compose.yml` está preparado para funcionar siempre encendido con
Tailscale, OpenSSH, Mosh y Moshi. Después de configurar `.env`, levantalo en
segundo plano:

```powershell
docker compose up -d
docker compose exec -u dev -it clis-code bash
```

La guía completa de autenticación y Easy Pair está en
[Acceso desde el celular con Tailscale + Moshi](#acceso-desde-el-celular-con-tailscale--moshi).

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
- **Actualizar CLIs:** reconstruye la imagen con `docker build -t clis-code:latest .`; las versiones remotas invalidan automáticamente las capas necesarias.
- **Reducir tamaño:** si no necesitas Google Chrome, elimina el bloque de instalación de `google-chrome-stable` y su comprobación en el healthcheck.
- **Arquitectura:** la imagen se construye y publica únicamente para `linux/amd64`.
- **Versiones:** OpenCode y Codex usan `latest` por defecto mediante argumentos `ARG`; las CLIs propietarias se resuelven desde sus manifests oficiales.

## Troubleshooting

### `docker: 'compose' is not a docker command`

Instala Docker Compose v2 en Ubuntu/WSL:

```bash
sudo apt update
sudo apt install docker-compose-v2
```

### `Permission denied` al montar volúmenes en Windows

Asegúrate de que Docker Desktop tenga habilitado el recurso compartido (`Settings > Resources > File Sharing`) o usa rutas dentro de `C:\Users\<tu usuario>\`.

### `devin`, `agy` o `opencode` no se encuentran

El `PATH` remoto incluye `/home/dev/.local/bin`, `/opt/pnpm-global/bin` y
`/opt/herdr/bin`. Si la sesión se abrió antes de actualizar la imagen,
reconectala o ajusta temporalmente el PATH:

```bash
export PATH="/opt/herdr/bin:$HOME/.local/bin:/opt/pnpm-global/bin:$PATH"
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
- `docs/` – guías de arquitectura, WSL, Tailscale, Moshi, Herdr y diagnóstico
- `LICENSE` – licencia MIT
- `.github/workflows/docker-build.yml` – CI: build en push/PR
- `.github/workflows/docker-publish.yml` – CD: publish a GHCR en tags
