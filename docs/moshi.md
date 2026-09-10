# Moshi

## Requisitos

- `clis-tailscale` aprobado y en estado `Running`.
- `clis-code` levantado y sano. Invocar `clis` lo asegura automaticamente: ademas
  de la sesion efimera, arranca el servicio persistente y espera a que `sshd`
  escuche en el puerto 22 del tailnet.
- Tailscale activo en el telefono con la misma cuenta o tailnet.
- App Moshi instalada.

```bash
# WSL host
docker compose up -d
docker compose ps
docker compose exec -u dev clis-code tailscale status
docker compose exec clis-code sshd -t
```

Moshi usa OpenSSH normal sobre Tailscale. No habilites Tailscale SSH para esta
conexion.

## Easy Pair y QR

Ejecuta el setup en el servicio persistente, no dentro de una sesion antigua
que tenga un home o `.ssh` diferente:

```bash
# WSL host, desde el repo clis-code
docker compose exec -u dev -it clis-code \
  moshi-hook host setup --user dev
```

Cuando pregunte la direccion, selecciona **Tailscale MagicDNS**. Tambien puedes
evitar las preguntas:

```bash
docker compose exec -u dev -it clis-code \
  moshi-hook host setup \
  --user dev \
  --host clis-code.<tailnet>.ts.net \
  --name clis-code
```

El QR aparece en esa terminal. En Moshi:

1. Abre Easy Pair.
2. Escanea el QR.
3. Usa el tipo de conexion **Auto**.
4. Espera la confirmacion en la terminal antes de cerrarla.

Moshi genera una clave Ed25519 en el telefono. Solo la clave publica se agrega
a `/home/dev/.ssh/authorized_keys`.

Las claves SSH del host para Git se montan aparte en `/home/dev/.git-ssh`
(read-only) y se cargan en un `ssh-agent` interno, no sobre `/home/dev/.ssh`.
Asi el `authorized_keys` de Easy Pair nunca queda oculto. Ver
[Arquitectura > SSH agent](architecture.md#ssh-agent).

## Validar el login

```bash
docker compose exec -u dev clis-code moshi-hook host list
docker compose exec clis-code ls -l /home/dev/.ssh/authorized_keys
docker compose exec clis-code pgrep -a sshd
docker compose exec clis-code sshd -T
```

La conexion debe usar:

- Host: MagicDNS de `clis-code`.
- Usuario: `dev`.
- Puerto: `22`.
- Autenticacion: clave creada por Easy Pair.

## Pairing de hooks

La imagen ya instala los hooks de Codex y OpenCode durante el build, pero no
registra automaticamente los eventos: hace falta el token. Copia el token desde
`Moshi > Settings > Hooks` y ejecuta:

```bash
docker compose exec -u dev clis-code \
  moshi-hook pair --token <token-de-moshi>

docker compose exec -u dev clis-code \
  moshi-hook install --target codex --target opencode

docker compose restart clis-code
```

No pegues el token en issues, logs o commits.

Si `moshi-hook status` muestra `stale` o `not found`, reinstala con
`moshi-hook install --target <agente>`. Devin todavia no es un target
soportado por moshi-hook; sus sesiones se siguen por la integracion de Herdr.

## Validar hooks y daemon

```bash
docker compose exec -u dev clis-code moshi-hook status
docker compose exec clis-code pgrep -a moshi-hook
docker compose exec -u dev clis-code moshi-hook logs
```

El estado esperado incluye:

- `status: paired`
- `codex current`
- `opencode current`
- `herdr` en la lista de multiplexores

Tras instalar hooks, cierra las sesiones viejas de Codex/OpenCode y crea otras.
Los hooks de inicio no aparecen retroactivamente en procesos existentes.

## PATH en sesiones remotas

El servidor SSH define el PATH necesario para `herdr`, `codex`, `opencode`,
`agy` y `devin`. Despues de reconstruir o recrear `clis-code`, cierra por
completo la conexion Moshi y vuelve a entrar.

Solucion temporal para una sesion antigua:

```bash
export PATH="/opt/herdr/bin:/home/dev/.local/bin:/opt/pnpm-global/bin:/opt/antigravity/bin:/opt/devin:$PATH"
```

## Sesiones tmux de Moshi

El comando siguiente crea o adjunta una sesion tmux asociada al directorio:

```bash
moshi .
```

Esto es distinto de una sesion Herdr. Consulta
[Agentes y Herdr](agents-and-herdr.md) para compartir Herdr entre PC y telefono.

## Moshi Desktop en el host

Moshi Desktop (la web UI en `24544`) esta pensada para correr en la maquina
donde estas sentado, no en el host remoto. Si el host WSL/Windows no esta en el
tailnet, la unica forma de alcanzar la web UI desde el browser del host es
publicar el puerto en localhost.

El Compose publica `127.0.0.1:24544:24544` desde el servicio `tailscale`, que
comparte el namespace de red con `clis-code`. Como el puerto se vincula a
`127.0.0.1`, solo el host puede alcanzarlo; no se expone a la LAN.

Desktop escucha en `127.0.0.1` por defecto. Para que el puerto publicado lo
alcance, hay que iniciarla escuchando en todas las interfaces:

```bash
# WSL host
docker compose exec -u dev clis-code moshi --listen 0.0.0.0:24544 --no-open
```

Luego abre `http://localhost:24544` en el browser del host. `--no-open` evita
que Desktop intente lanzar un browser dentro del contenedor.

El daemon (`moshi-hook serve`, gateway en `127.0.0.1:24543`) sigue en loopback y
no se publica: Desktop lo alcanza directamente porque corre en el mismo
contenedor.

Advertencia de seguridad: quien alcance `localhost:24544` en el host tiene
control total sobre los agentes del contenedor. No expongas este puerto a la
red; el bind a `127.0.0.1` ya lo previene.

## Moshi Free y Herdr

Moshi Free usa SSH y no incluye la integracion de multiplexores ni el
auto-attach de Herdr. Si la app cierra la conexion, Herdr sigue ejecutando los
agentes en el servidor, pero la conexion siguiente abre un shell nuevo. Para
volver a la sesion persistente ejecuta:

```bash
herdr
```

O, para una sesion con nombre:

```bash
herdr session attach <nombre>
```

Esto no indica que Herdr haya perdido la sesion. Confirma que sigue viva con
`herdr status server` y `herdr session list`. El auto-attach despues de una
reconexion y el transporte Mosh son funciones de Moshi Pro. En Free, bloquear
el telefono, suspender la app o cambiar entre Wi-Fi y datos puede cortar SSH y
reiniciar todo el shell visible, no solo Herdr. Ejecuta cualquier trabajo que
deba sobrevivir dentro de Herdr o tmux.
