# Agentes y Herdr

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
sesion nueva del agente despues de actualizar hooks.

## Integraciones de Herdr

Moshi detecta Herdr como multiplexor. Herdr, a su vez, necesita integraciones
propias para conservar y mostrar el estado de los agentes:

```bash
docker compose exec -u dev clis-code herdr integration install codex
docker compose exec -u dev clis-code herdr integration install opencode
docker compose exec -u dev clis-code herdr integration status
```

Los hooks de Moshi y las integraciones de Herdr pueden coexistir. Verifica
`moshi-hook status` despues de reinstalar una integracion.

Una nueva version de Herdr puede marcar integraciones persistidas como
`outdated`:

```bash
docker compose exec -u dev clis-code \
  herdr integration status --outdated-only
```

Reinstala solo las que indique el comando.

## Sesiones con nombre

Usa nombres explicitos para reconocer el mismo workspace desde ambos
dispositivos:

```bash
herdr --session cli-sandbox
```

Comandos de gestion:

```bash
herdr session list
herdr session attach cli-sandbox
herdr session stop cli-sandbox
herdr session delete cli-sandbox
```

## Ver un Herdr de la PC desde Moshi

En la PC, inicia Herdr con `clis` y deja viva esa sesion:

```bash
cd /mnt/c/dev/repos/mi-proyecto
clis herdr --session mi-proyecto
```

Desde una conexion nueva de Moshi:

```bash
herdr session list
herdr session attach mi-proyecto
```

El socket de Herdr vive en el home compartido, por lo que el servicio
persistente puede adjuntarse al servidor del contenedor efimero. Si el
contenedor `clis-code-run-*` termina, tambien termina el servidor Herdr que
estaba ejecutando.

## Ver un Herdr de Moshi desde la PC

Desde Moshi:

```bash
herdr --session movil
```

Desde WSL:

```bash
clis herdr session list
clis herdr session attach movil
```

Si ya estas dentro de `clis`, omite el prefijo `clis`.

## Sesion default

Ejecutar `herdr` sin `--session` crea o adjunta la sesion `default`:

```bash
herdr session attach default
```

Funciona, pero los nombres por proyecto son mas claros cuando hay varias
sesiones entre PC y telefono.

Desconectar el cliente no detiene el servidor Herdr. En una conexion SSH nueva,
`herdr` vuelve a adjuntar la sesion `default`; `herdr session attach <nombre>`
hace lo mismo con una sesion nombrada. Moshi Free requiere este paso manual,
porque el selector de multiplexores y el auto-attach son funciones Pro.

## Diferencia con moshi punto

- `moshi .` crea o adjunta una sesion tmux para el directorio actual.
- `herdr --session <nombre>` crea o adjunta una sesion gestionada por Herdr.
- `herdr session attach <nombre>` abre una sesion Herdr existente.

No uses `moshi .` para adjuntar una sesion Herdr.

## Proyectos visibles en remoto

El servicio persistente y las sesiones `clis` montan la misma raiz
`CLIS_PROJECTS_ROOT` en `/home/dev/projects`. Con el valor predeterminado,
`/mnt/c/dev/repos/mi-proyecto` queda disponible desde Moshi como
`/home/dev/projects/repos/mi-proyecto`. No hace falta copiar ni volver a montar
repos individuales.
