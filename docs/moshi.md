# Moshi

## Requisitos

- `clis-tailscale` aprobado y en estado `Running`.
- `clis-code` levantado y sano.
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

Easy Pair habilita SSH/Mosh, pero no registra automaticamente los eventos de
agentes. Copia el token desde `Moshi > Settings > Hooks` y ejecuta:

```bash
docker compose exec -u dev clis-code \
  moshi-hook pair --token <token-de-moshi>

docker compose exec -u dev clis-code \
  moshi-hook install --target codex --target opencode

docker compose restart clis-code
```

No pegues el token en issues, logs o commits.

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
