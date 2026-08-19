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

## Sesiones efimeras de clis

El script `clis` ejecuta `docker compose run --rm --no-deps clis-code` y:

- Monta la raiz compartida `CLIS_PROJECTS_ROOT` (`/mnt/c/dev` por defecto).
- Conserva el subdirectorio actual como working directory.
- Comparte red, home, credenciales, skills y Docker socket con Compose.
- Inicia primero el sidecar y exige `BackendState=Running`.
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
