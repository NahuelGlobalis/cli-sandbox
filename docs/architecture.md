# Arquitectura

## Componentes

El Compose define dos servicios:

- `clis-tailscale`: ejecuta `tailscaled`, conserva la identidad del nodo y
  expone su socket Unix.
- `clis-code`: contiene las CLIs, OpenSSH, Mosh, Moshi Hook, el servidor Orca,
  Docker CLI y los navegadores.

El sidecar usa `tailscale-entrypoint.sh` sobre la imagen oficial. Mantiene el
daemon activo durante device approval, comprueba el estado cada 10 segundos y
solo usa la auth key en `NeedsLogin`. El healthcheck exige `Running` y `clis`
espera la aprobacion antes de iniciar el servicio persistente.

`clis-code` usa `network_mode: service:tailscale`. Ambos servicios comparten el
mismo namespace de red, por lo que SSH, Mosh y cualquier servidor iniciado en
`clis-code` quedan disponibles en la IP Tailscale sin publicar puertos Docker.

Compose habilita forwarding IPv4/IPv6 solo en ese namespace para poder anunciar
un exit node, con las capacidades existentes. El host WSL no se reconfigura.
El healthcheck reconcilia las preferencias exit node por env antes de exigir
`BackendState=Running`. Los [modos Tailscale](tailscale.md#exit-node) afectan
tambien a `clis-code` y las sesiones efimeras, no a la salida del host.

La unica excepcion es Moshi Desktop: su web UI escucha en `24544` y, como el
host no esta en el tailnet, el puerto se publica desde el servicio `tailscale`
vinculado a `127.0.0.1` (`127.0.0.1:24544:24544`). Asi el browser del host lo
alcanza en `http://localhost:24544` sin exponerlo a la LAN. Ver
[Moshi](moshi.md#moshi-desktop-en-el-host).
Con el mismo criterio se publica la web UI de Orca en
`127.0.0.1:6769:6768` (6769 para no chocar con un Orca nativo del host en
6768): el browser local la abre en `http://localhost:6769`.

```text
Telefono                       WSL / Docker
Tailscale + Moshi              
        |                      
        +---- tailnet ----> clis-tailscale
                                | red compartida
                                +-- clis-code persistente
                                +-- clis-code-run-* efimero (`clis`)
```

## Servicio persistente

`docker compose up -d` mantiene `clis-code` encendido con:

- OpenSSH en el puerto 22 del tailnet.
- Mosh en su rango UDP normal.
- `moshi-hook serve` y su WebSocket hacia Moshi.
- `orca-ide serve` en el puerto 6768 del tailnet.
- `cron` con el crontab del usuario dev (sembrado desde `./crontab`).
- Home y claves de host persistentes.

Este es el servicio al que se conecta Moshi. Su comando principal es
`sleep infinity`; los daemons se inician desde `entrypoint.sh`.

`clis up` inicia y valida los servicios, y luego abre Bash en este contenedor.
`clis up -d` realiza el mismo arranque sin entrar al contenedor.

## Sesiones efimeras de clis

El script `clis` levanta los servicios con Compose y crea la sesion efimera con
`docker run`. La sesion reutiliza los mounts de `clis-code` mediante
`--volumes-from` y se adjunta al namespace de `clis-tailscale`. Ademas:

- Monta la raiz compartida `CLIS_PROJECTS_ROOT` (`/mnt/c/dev` por defecto).
- Abre la sesion en la ruta absoluta del host del directorio actual; la raiz
  tambien queda montada en `/home/dev/projects`.
- Comparte red, home, credenciales, skills y Docker socket con Compose.
- Inicia primero el sidecar y exige `BackendState=Running`.
- Asegura que el servicio persistente `clis-code` quede levantado (con `sshd`
  corriendo) para que Moshi siempre tenga a quien conectarse, incluso cuando
  solo se invoca `clis`.
- Define `CLIS_REMOTE_SERVICES=0` para no arrancar otro SSH ni otro daemon de
  Moshi en el mismo namespace de red.

Por eso `clis` tiene acceso a Tailscale, pero no reemplaza al servicio
persistente que recibe las conexiones del telefono.

## Persistencia

| Host WSL / volumen | Contenedor | Contenido |
| --- | --- | --- |
| `~/.clis-code/home` | `/home/dev` | Credenciales, hooks y datos de Orca |
| `/mnt/c/dev` | `/home/dev/projects` | Todos los repos de trabajo |
| `/mnt/c/dev` | `/mnt/c/dev` (misma ruta) | Alias: los `-v` internos los resuelve el daemon en el host |
| `~/.agents/skills` | `/home/dev/.agents/skills` | Skills compartidas |
| `~/.ssh` | `/home/dev/.git-ssh` | Claves SSH del host (solo lectura) |
| `tailscale-state` | `/var/lib/tailscale` | Identidad del nodo |
| `tailscale-socket` | `/var/run/tailscale` | Socket del daemon Tailscale |
| `ssh-host-keys` | `/var/lib/ssh` | Identidad estable de OpenSSH |
| `./crontab` | `/etc/clis-code/crontab` | Tareas programadas de `dev` |

La ruta absoluta se conserva. Por ejemplo,
`/mnt/c/dev/repos/publics/cli-sandbox` se abre como `/mnt/c/dev/repos/publics/cli-sandbox`
tambien dentro del contenedor. Asi, un `docker run -v "$PWD/..."` emitido por un
agente usa una ruta que el daemon del host puede resolver. El arbol completo
sigue visible en `/home/dev/projects`, pero los paths bajo esa ruta no sirven
para bind mounts internos: hay que usar la ruta del host (`$CLIS_PROJECTS_ROOT`
esta exportada en el contenedor). El servicio persistente y las sesiones `clis`
ven el mismo arbol.

Si `clis` se invoca fuera de `CLIS_PROJECTS_ROOT`, solo el directorio actual se
monta en la misma ruta absoluta del host. Se rechazan rutas que taparian mounts
o el filesystem del contenedor (`/home`, `/etc`, `/var`, etc.).

## Servidor Orca

El servicio persistente ejecuta `orca-ide serve` como `dev` y escucha en
`0.0.0.0:6768` dentro de la red compartida con Tailscale. Los clientes Orca se
conectan por MagicDNS (`clis-code:6768`) y el pairing URL queda en
`/home/dev/.local/state/orca/serve.log`.

Orca conserva proyectos, worktrees, terminales y sesiones de agentes en el home
persistente. Las sesiones efimeras de `clis` no arrancan otro servidor Orca;
comparten el home y el runtime con el servicio persistente. Si termina el
contenedor persistente, tambien terminan sus procesos y clientes conectados.

## PATH remoto

OpenSSH y Mosh no heredan automaticamente el `ENV PATH` de la imagen. La
configuracion `sshd_config.d/99-clis-code.conf` define el PATH remoto para
incluir:

- `/opt/pnpm-global/bin`
- `/opt/antigravity/bin`
- `/opt/devin`
- `/home/dev/.local/bin`

Los cambios de PATH solo se aplican a conexiones SSH/Mosh nuevas.

## SSH agent

Las claves SSH del host se montan en `/home/dev/.git-ssh` (read-only), no sobre
`/home/dev/.ssh`: esto conserva el `authorized_keys` persistente que Easy Pair
crea para el teléfono. El `entrypoint.sh` arranca un `ssh-agent` interno en
`/tmp/clis-ssh-agent.sock` y carga todas las claves privadas de ese directorio
(cualquier nombre: `id_ed25519`, `id_rsa`, `personal`, `botsmza`, etc.), no solo
las de nombre estándar. `SSH_AUTH_SOCK` apunta al socket interno, así Git por
SSH funciona sin depender de que el agent del host esté activo.

Cada contenedor (el persistente y cada sesión efímera de `clis`) ejecuta el
entrypoint y obtiene su propio agent. Las sesiones remotas por Moshi/SSH reciben
la misma ruta mediante `SetEnv` en `sshd_config.d/99-clis-code.conf`.

Notas:

- Las claves con passphrase no se cargan (el entrypoint no puede pedirla sin
  colgar); dejalas sin passphrase o cargalas a mano con `ssh-add` dentro de la
  sesión.
- El `known_hosts` del host se enlaza en `/home/dev/.ssh/known_hosts` (si no
  existe ya) para que Git/SSH verifique hosts sin prompt.
- Ya no se reenvía `SSH_AUTH_SOCK` del host. Si necesitás claves que solo viven
  en el agent del host (p. ej. hardware tokens), copialas a `~/.ssh` o montalas
  en `.git-ssh`.
