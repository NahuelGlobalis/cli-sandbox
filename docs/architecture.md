# Arquitectura

## Componentes

El Compose define dos servicios:

- `clis-tailscale`: ejecuta `tailscaled`, conserva la identidad del nodo y
  expone su socket Unix.
- `clis-code`: contiene las CLIs, OpenSSH, Mosh, Moshi Hook, Herdr, Docker CLI y
  los navegadores.

`clis-code` usa `network_mode: service:tailscale`. Ambos servicios comparten el
mismo namespace de red, por lo que SSH, Mosh y cualquier servidor iniciado en
`clis-code` quedan disponibles en la IP Tailscale sin publicar puertos Docker.

La unica excepcion es Moshi Desktop: su web UI escucha en `24544` y, como el
host no esta en el tailnet, el puerto se publica desde el servicio `tailscale`
vinculado a `127.0.0.1` (`127.0.0.1:24544:24544`). Asi el browser del host lo
alcanza en `http://localhost:24544` sin exponerlo a la LAN. Ver
[Moshi](moshi.md#moshi-desktop-en-el-host).

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
- Conserva el subdirectorio actual como working directory.
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
| `~/.clis-code/home` | `/home/dev` | Credenciales, hooks y sockets |
| `/mnt/c/dev` | `/home/dev/projects` | Todos los repos de trabajo |
| `~/.agents/skills` | `/home/dev/.agents/skills` | Skills compartidas |
| `~/.ssh` | `/home/dev/.git-ssh` | Claves SSH del host (solo lectura) |
| `tailscale-state` | `/var/lib/tailscale` | Identidad del nodo |
| `tailscale-socket` | `/var/run/tailscale` | Socket del daemon Tailscale |
| `ssh-host-keys` | `/var/lib/ssh` | Identidad estable de OpenSSH |

La ruta relativa se conserva. Por ejemplo,
`/mnt/c/dev/repos/publics/cli-sandbox` se abre como
`/home/dev/projects/repos/publics/cli-sandbox`. El servicio persistente y las
sesiones `clis` ven el mismo arbol completo.

## Sesiones Herdr entre contenedores

Herdr guarda su socket en `/home/dev/.config/herdr/herdr.sock`. Como el home se
comparte, el servicio persistente y una sesion `clis` pueden descubrir el mismo
servidor Herdr mientras el contenedor que lo aloja siga vivo.

Los archivos compartidos no implican procesos compartidos. Si termina el
contenedor que ejecuta el servidor Herdr, esa sesion deja de existir aunque el
socket o la configuracion permanezcan en el home.

## PATH remoto

OpenSSH y Mosh no heredan automaticamente el `ENV PATH` de la imagen. La
configuracion `sshd_config.d/99-clis-code.conf` define el PATH remoto para
incluir:

- `/opt/herdr/bin`
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
