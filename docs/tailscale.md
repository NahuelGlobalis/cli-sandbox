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
