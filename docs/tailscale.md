# Tailscale

## Registrar el nodo

1. Crea una auth key en [Tailscale Admin > Keys](https://login.tailscale.com/admin/settings/keys).
2. No marques el nodo como `ephemeral`.
3. Guarda la key en `.env` como `TS_AUTHKEY`.
4. Levanta el sidecar.

```bash
docker compose up -d tailscale
docker compose ps
```

El sidecar usa `TS_AUTH_ONCE=true`. Tras el primer registro, la identidad queda
en el volumen `tailscale-state` y los reinicios no consumen otra key.

## Aprobar el dispositivo

Si el tailnet tiene device approval, el nodo queda en
`BackendState=NeedsMachineAuth`. Entra a
[Tailscale Admin > Machines](https://login.tailscale.com/admin/machines), busca
`clis-code` y apruebalo.

Mientras esta pendiente:

- `clis` termina con un mensaje de aprobacion.
- El contenedor oficial puede reiniciarse al vencer su intento inicial.
- Tener una IP asignada no significa que el nodo ya pueda intercambiar trafico.

## Verificar el estado

```bash
docker compose exec -T tailscale tailscale status
docker compose exec -T tailscale tailscale ip -4
docker compose exec -T tailscale tailscale status --json
```

El estado util debe ser `Running`. El healthcheck de Compose valida ese estado,
no solo que el comando `tailscale status` responda.

Desde una sesion `clis`:

```bash
tailscale status
tailscale ip -4
```

El cliente usa `/var/run/tailscale/tailscaled.sock`, compartido con el sidecar.

## Exit node

Los tres modos se configuran por env. Valores booleanos: `true` o `false`.

| Modo | `TAILSCALE_ADVERTISE_EXIT_NODE` | `TAILSCALE_EXIT_NODE` |
| --- | --- | --- |
| Nodo normal (predeterminado) | `false` | vacio |
| Ofrecer salida a otros nodos | `true` | vacio |
| Utilizar otro exit node | `false` | nombre o IP Tailscale |

No combines anuncio y uso. Esa combinacion no queda saludable. Para utilizar
otro exit node, por ejemplo:

```text
TAILSCALE_EXIT_NODE=mi-exit-node
TAILSCALE_ADVERTISE_EXIT_NODE=false
TAILSCALE_EXIT_NODE_ALLOW_LAN_ACCESS=false
```

`TAILSCALE_EXIT_NODE_ALLOW_LAN_ACCESS=true` permite salida directa a la LAN al
utilizar otro exit node; no la habilites salvo que lo necesites. Con exit node
vacio debe ser `false`. Esto no anuncia rutas de subred.

El exit node elegido debe estar anunciando `--advertise-exit-node` y aprobado
en Tailscale Admin. Como `clis-code` comparte la red del sidecar, las sesiones
`clis`, SSH y Moshi heredan esa salida.

Para anunciar este nodo, define `TAILSCALE_ADVERTISE_EXIT_NODE=true` y deja
`TAILSCALE_EXIT_NODE` vacio. Compose habilita `net.ipv4.ip_forward=1` y
`net.ipv6.conf.all.forwarding=1` en el namespace del contenedor: Linux necesita
ambos para reenviar trafico. No requiere `privileged` ni capacidades nuevas.

Despues de editar las variables, aplica el cambio desde WSL (estos comandos
recrean servicios y pueden interrumpir sesiones; no borran volumenes):

```bash
docker compose up -d --force-recreate tailscale clis-code
docker compose ps
```

Un `restart` no actualiza el env del contenedor. Cierra y vuelve a abrir las
sesiones efimeras, que pueden conservar el namespace anterior.

Compose pasa los tres flags explicitos mediante `TS_EXTRA_ARGS` para el primer
`tailscale up`. Con identidad persistida, `TS_AUTH_ONCE=true` evita otro login,
pero el `tailscale set` de containerboot no reaplica esos argumentos extra.
Por eso el healthcheck ejecuta `tailscale set` con los tres valores antes de
validar `Running`, y los vuelve a reconciliar cada 10 segundos. Al volver al
modo normal, `--advertise-exit-node=false`, `--exit-node=` y
`--exit-node-allow-lan-access=false` limpian las preferencias anteriores sin
borrar identidad. Los cambios manuales a esos flags se sobrescriben.
Puede existir un intervalo inicial con preferencias previas hasta el primer
healthcheck; `clis-code` espera a que termine correctamente.

### Aprobacion y portal

Anunciar no equivale a estar aprobado. Un administrador debe abrir
[Machines](https://login.tailscale.com/admin/machines), seleccionar el nodo,
entrar a **Edit route settings** y habilitar **Use as exit node** (salvo que
la politica tenga `autoApprovers` aplicables). Esta aprobacion es distinta de
device approval y no hace que los clientes lo utilicen automaticamente.
Cada cliente debe seleccionarlo; las politicas personalizadas deben permitir
`autogroup:internet`.

Si el portal indica **waiting advertising**, aprobar en el portal no basta:
el daemon debe anunciar primero las rutas de salida `0.0.0.0/0` y `::/0`.
Comprueba el modo configurado, que recreaste el contenedor y que esta saludable:

```bash
docker compose ps
docker compose exec -T tailscale tailscale debug prefs
docker compose exec -T tailscale sh -c \
  'sysctl net.ipv4.ip_forward net.ipv6.conf.all.forwarding'
```

En modo anuncio, `AdvertiseRoutes` debe incluir ambas rutas de salida y ambos
sysctls deben valer `1`. Si no, revisa errores locales de `tailscale set` o
forwarding antes de aprobar. No compartas la salida de preferencias sin
sanitizarla. `NeedsMachineAuth` requiere primero aprobar el dispositivo;
`Running` no demuestra aprobacion del exit node ni forwarding funcional.
No borres volumenes ni generes otra auth key para corregir este estado.

Referencias oficiales:

- [Variables Docker](https://tailscale.com/docs/features/containers/docker/docker-params):
  `TS_EXTRA_ARGS`, `TS_AUTH_ONCE`, `TS_USERSPACE` y estado persistente.
- [Exit nodes](https://tailscale.com/kb/1103/exit-nodes): forwarding, aprobacion
  manual, seleccion por cliente y acceso LAN.
- [Containerboot](https://github.com/tailscale/tailscale/blob/main/cmd/containerboot/tailscaled.go):
  diferencia entre `tailscaleUp` y `tailscaleSet` con `TS_AUTH_ONCE`.

## MagicDNS

Para conexiones remotas usa el nombre completo mostrado por `tailscale status`,
por ejemplo:

```text
clis-code.<tailnet>.ts.net
```

MagicDNS es preferible a la IP porque mantiene un nombre estable y es la opcion
recomendada por Easy Pair.

## Puertos y servidores

No uses `docker -p` ni `clis --port`: `clis-code` comparte el namespace de red
del sidecar y Docker no permite publicar puertos desde un contenedor con
`network_mode: container/service`.

Para exponer un servidor al tailnet:

1. Haz que escuche en `0.0.0.0`, no solo en `127.0.0.1`.
2. Accede desde otro nodo a `clis-code:<puerto>` o al nombre MagicDNS completo.

No se publica el puerto en Internet ni en todas las interfaces del host.

## Rotar o recrear la identidad

Rotar la auth key de `.env` no cambia una identidad ya registrada por
`TS_AUTH_ONCE=true`. Para una identidad nueva hay que eliminar deliberadamente
el volumen de estado y volver a registrar el nodo. Esa operacion es destructiva
y tambien requiere eliminar o deshabilitar el nodo anterior en Tailscale Admin.

No ejecutes `docker compose down -v` salvo que quieras borrar Tailscale, claves
SSH y los demas volumenes nombrados del proyecto.
