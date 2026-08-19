# clis-code agent guide

`clis-code` construye una imagen Ubuntu `linux/amd64` con CLIs de agentes,
Docker, navegadores y acceso remoto privado mediante Tailscale, OpenSSH, Mosh y
Moshi.

## Scope and routing

- Este archivo aplica a todo el repositorio y es la guia comun para Codex,
  OpenCode y otros agentes.
- Lee `docs/README.md` para localizar la guia del subsistema que vas a cambiar.
- Para red, procesos y volumenes, lee `docs/architecture.md` antes de editar
  `docker-compose.yml`, `entrypoint.sh` o `clis`.
- Para Tailscale, Moshi o Herdr, consulta respectivamente `docs/tailscale.md`,
  `docs/moshi.md` y `docs/agents-and-herdr.md`.
- No hay instrucciones anidadas ni contenido generado en el estado actual.

## Repository map

- `Dockerfile`: imagen, versiones y herramientas. Mantiene `linux/amd64` y los
  binarios fuera del home persistente.
- `docker-compose.yml`: fuente de verdad de red, volumenes y runtime remoto.
- `entrypoint.sh`: bootstrap, permisos y daemons; baja de root a `dev` con
  `gosu`.
- `clis`: entrada desde WSL; crea sesiones Compose efimeras y monta el repo.
- `sshd_config.d/`: politica SSH/Mosh y PATH remoto para el usuario `dev`.
- `.env.example`: contrato publico; nunca autoriza leer el `.env` real.
- `docs/`: guias por subsistema; actualizar ante cambios observables.
- `.github/workflows/`: build en ramas y publicacion solo mediante tags `v*`.

## Runtime model

- `clis-tailscale` ejecuta `tailscaled` y conserva identidad y socket en
  volumenes nombrados.
- `clis-code` usa `network_mode: service:tailscale`; no tiene red propia.
- El servicio persistente ejecuta SSH y Moshi Hook. Las sesiones `clis` usan
  `CLIS_REMOTE_SERVICES=0` para evitar puertos y daemons duplicados.
- `/home/dev` se comparte mediante `~/.clis-code/home`; contiene credenciales,
  hooks, `authorized_keys` y sockets de Herdr.
- `clis` superpone el repo actual en `/home/dev/projects/<repo>`.
- La imagen y algunas CLIs solo soportan `linux/amd64`.

## Environment and setup

- Entorno principal: Ubuntu 24.04 en WSL 2 con Docker Engine y Compose v2.
- Requiere `/dev/net/tun` para Tailscale y aproximadamente 5 GB para la imagen.
- Bootstrap documentado: `docs/setup-wsl.md`.
- Variables publicas: `.env.example`.
- No leas, imprimas, edites ni agregues `.env`, tokens, credenciales o el
  contenido de `~/.clis-code/home`.
- Un build consulta manifests remotos y puede resolver versiones nuevas aunque
  el Dockerfile no cambie. Informa esa variabilidad al verificar.

## Commands

Ejecuta desde la raiz del repo dentro de WSL salvo que se indique otra cosa.

- Sintaxis shell: `bash -n clis entrypoint.sh` debe terminar con codigo 0.
- Whitespace: `git diff --check` no debe mostrar errores. Los warnings CRLF no
  son fallos.
- Compose estatico, sin secretos reales:

  ```bash
  TS_AUTHKEY=tskey-auth-placeholder \
    docker compose --env-file .env.example config --quiet
  ```

- Lint de docs: `clis pnpm dlx markdownlint-cli2 docs/*.md` debe indicar
  `0 issues`. Requiere imagen, red y Tailscale activo.
- Build local: `docker compose build clis-code` debe crear
  `clis-code:latest`.
- Build equivalente a CI:

  ```bash
  docker buildx build --platform linux/amd64 --load \
    -t clis-code:latest .
  ```

- Inspeccion: `docker image inspect clis-code:latest` debe mostrar metadata.

No hay suite de unit tests. Los flujos reales de Tailscale, Easy Pair y Moshi
requieren credenciales, aprobacion y telefono; no los ejecutes como test
automatico. Marca esas verificaciones como no ejecutadas si no fueron pedidas.

## Change workflow

1. Inspecciona el archivo objetivo, la guia de `docs/` correspondiente y el
   estado Git. Conserva cambios ajenos.
2. Haz el cambio minimo en la fuente de verdad; evita duplicar configuracion
   entre `clis`, Compose y el entrypoint.
3. Actualiza ejemplos y troubleshooting cuando cambien comandos, mounts, PATH,
   red, pairing o persistencia.
4. Ejecuta primero sintaxis, `git diff --check` y validacion Compose. Construye
   la imagen cuando cambie el Dockerfile o contenido copiado a la imagen.
5. Revisa el diff final y reporta checks ejecutados, checks omitidos y riesgos.

## Conventions and invariants

- Shell: Bash con `set -euo pipefail`, arrays para argumentos y paths citados.
- Mantener LF en `clis`, `entrypoint.sh`, `Dockerfile` y scripts `*.sh`.
- Binarios viven en `/opt` o rutas del sistema; datos y credenciales viven en
  `/home/dev`.
- El usuario de trabajo es `dev` UID 1000. El entrypoint solo usa root para
  bootstrap, claves, sockets y permisos.
- Moshi usa OpenSSH normal sobre Tailscale. No cambies el flujo a Tailscale SSH.
- No montes `~/.ssh` del host sobre `/home/dev/.ssh`: ocultaria la
  `authorized_keys` persistente de Easy Pair.
- Con la red compartida no se pueden publicar puertos desde `clis-code`. Los
  servicios deben escuchar en `0.0.0.0` y usarse por MagicDNS dentro del
  tailnet.
- El healthcheck Tailscale debe exigir `BackendState=Running`; una IP asignada
  no prueba que el nodo este aprobado.
- Herdr y Moshi tienen hooks distintos y compatibles; valida ambos despues de
  cambiar integraciones.

## Safety boundaries

- Nunca expongas secretos ni uses una auth key real en pruebas o documentacion.
- No ejecutes `docker compose down -v`: elimina identidad Tailscale y claves SSH.
- No borres o recrees volumenes, nodos, pairings ni `authorized_keys` sin
  autorizacion explicita.
- No cambies permisos para evitar controles de SSH, Docker o sockets.
- No hagas push, tags, releases, login a registros ni publiques GHCR salvo
  solicitud explicita.
- No habilites puertos publicos, `privileged`, Tailscale SSH o capacidades
  adicionales sin una necesidad concreta y revision de seguridad.
- El Docker socket equivale a control del host; no amplifiques su exposicion.

## Definition of done

- El comportamiento solicitado esta implementado en la fuente de verdad
  correcta y la documentacion afectada coincide.
- `bash -n clis entrypoint.sh`, `git diff --check` y la validacion Compose pasan
  cuando aplican.
- Los cambios de imagen se construyen, o se declara claramente por que el build
  no se ejecuto.
- Las pruebas remotas no ejecutadas se reportan como limitacion, nunca como
  exito implicito.
- El diff final no contiene secretos, artefactos de build ni cambios ajenos.
