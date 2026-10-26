# Agentes y Orca

Orca reemplaza a Herdr en esta imagen. Orca no es un multiplexor de terminal:
es un servidor remoto que conserva proyectos, worktrees, terminales y sesiones
de agentes, y al que se conectan los clientes de escritorio o mobile por
WebSocket. Moshi, OpenSSH y Mosh siguen siendo el acceso de shell y no dependen
de Orca.

## Qué corre y dónde

- `clis-code` ejecuta `orca-ide serve` como el usuario `dev`.
- Orca escucha en `0.0.0.0:6768` dentro del namespace de red de Tailscale.
- El cliente se conecta por MagicDNS, por ejemplo `ws://clis-code:6768`.
- Los proyectos se montan en `/home/dev/projects`.
- La configuración, las credenciales y las sesiones viven en `/home/dev`.

Las sesiones efímeras creadas por `clis` usan `CLIS_REMOTE_SERVICES=0` y no
arrancan otro servidor Orca, SSH ni Moshi Hook. Comparten el home y la red con
el servicio persistente.

## Arranque del servidor

El entrypoint inicia `orca-ide serve` solo en el servicio persistente, después
de SSH, cron y Moshi Hook. Variables disponibles:

| Variable | Predeterminado | Efecto |
| --- | --- | --- |
| `ORCA_SERVE_AUTOSTART` | `1` | Arranca Orca en el servicio persistente |
| `ORCA_PORT` | `6768` | Puerto del servidor |
| `ORCA_PAIRING_ADDRESS` | `TAILSCALE_HOSTNAME` | Host anunciado en el pairing |
| `ORCA_MOBILE_PAIRING` | `0` | `1` genera un enlace/QR para Orca Mobile |

El servidor escribe su salida en:

```text
/home/dev/.local/state/orca/serve.log
```

El primer arranque descarga el runtime fijado de Orca (unos 150 MB) en
`/home/dev/.config/orca`. Puede tardar varios minutos según la red. El log
muestra el progreso y, cuando termina, las líneas `Orca server ready` y
`Pairing URL:`.

Para ver el enlace:

```bash
clis pairing
```

El pairing URL es un secreto: concede acceso al runtime. No lo pegues en issues,
logs compartidos ni commits. El archivo se crea con permisos `0600`.

## Conectar Orca Desktop

1. Instalá Orca en la PC cliente y conectá esa PC al mismo tailnet.
2. Abrí **Settings → Remote Orca Servers → Add Server**.
3. Pegá el pairing URL que muestra el log.
4. Guardá y conectá el servidor.

Los proyectos del servidor aparecen bajo `/home/dev/projects`. Los terminales y
agentes que lances desde el cliente corren en `clis-code`, con el `PATH`, las
credenciales y el home del usuario `dev`.

## Conectar Orca Mobile

Cambiá `ORCA_MOBILE_PAIRING=1` en `.env`, recreá el servicio y mirá el log:

```bash
docker compose up -d --force-recreate clis-code
docker compose exec -u dev clis-code \
  tail -n 120 /home/dev/.local/state/orca/serve.log
```

El log imprime un QR y un enlace con alcance mobile. Escanealo desde Orca
Mobile con el teléfono en el mismo tailnet. Después podés volver a
`ORCA_MOBILE_PAIRING=0` para el pairing normal de escritorio.

Al reiniciar el servidor se imprime un enlace nuevo. Los clientes ya
emparejados conservan su acceso hasta que se revoque desde el cliente o desde
la configuración de acceso compartido del servidor.

## CLIs y agentes

Las CLIs se instalan y autentican dentro del servidor, no en la PC cliente. El
cliente Orca abre terminales en `clis-code`; desde una sesión SSH o Mosh también
podés usar `orca-ide` para consultar el estado y abrir terminales en el runtime.

```bash
orca-ide status --json
orca-ide --version
orca-ide agent hooks status
```

Orca detecta Codex, OpenCode, Devin y Antigravity si están disponibles en el
`PATH` del servidor. Los hooks de estado de Orca son independientes de los hooks
de Moshi y pueden coexistir. Si cambiás uno, verificá el otro.

Para instalar las skills que enseñan a los agentes a usar la CLI de Orca:

```bash
orca-ide skills install --skill orca-cli --skill orchestration
```

En un servidor headless, las cuentas administradas de Claude/Codex se agregan
desde el shell del servidor:

```bash
orca-ide account add --agent claude
orca-ide account add --agent codex
orca-ide account list
```

## Hooks de Moshi para Codex y OpenCode

La imagen instala los hooks de Codex y OpenCode durante el build. Para
actualizarlos o repararlos en el home persistente:

```bash
docker compose exec -u dev clis-code \
  moshi-hook install --target codex --target opencode

docker compose restart clis-code
docker compose exec -u dev clis-code moshi-hook status
```

El estado debe mostrar:

```text
codex    current
opencode current
```

Si aparecen como `stale`, vuelve a ejecutar `moshi-hook install`. Inicia una
sesión nueva del agente después de actualizar hooks.

## Datos de Herdr

La imagen ya no instala ni arranca Herdr. Si un home persistente anterior tiene
`/home/dev/.config/herdr`, esos archivos no se borran automáticamente, pero
quedan sin uso. Podés eliminarlos manualmente cuando ya no necesites esa
configuración.

## Validación y diagnóstico

```bash
docker compose exec -u dev clis-code orca-ide --version
docker compose exec -u dev clis-code tail -n 120 \
  /home/dev/.local/state/orca/serve.log
docker compose exec clis-code curl -sS -o /dev/null -w '%{http_code}\n' \
  http://127.0.0.1:6768
docker compose exec -u dev clis-code orca-ide agent hooks status
```

Si el log muestra errores de descarga del runtime, revisá la salida de red del
contenedor y volvé a intentar; el servidor reintenta cada 5 segundos. Si el
puerto está ocupado, cambiá `ORCA_PORT` y recreá el servicio.

Si el pairing URL no aparece porque se inició con `--supervise`, reiniciá el
servicio: el entrypoint usa `serve` sin `--supervise` justamente para conservar
el enlace en el log.

## Seguridad

- El puerto se publica solo en loopback del host (`127.0.0.1:6769`); fuera del
  host es alcanzable únicamente por el tailnet.
- Cualquiera que alcance el puerto puede intentar el pairing. Mantené las ACL
  de Tailscale lo más cerradas posible.
- No reenvíes el puerto de Orca a Internet.
- Revocá los accesos de clientes que ya no uses desde Orca.
