# Documentacion de clis-code

Esta carpeta contiene la guia operativa del entorno `clis-code`. El README de
la raiz sigue siendo la referencia general; estos documentos explican en
detalle la configuracion de WSL, Tailscale, Moshi y las sesiones compartidas.

## Indice

1. [Arquitectura](architecture.md): servicios, red, volumenes y diferencias
   entre el contenedor persistente y las sesiones de `clis`.
2. [Instalacion en WSL](setup-wsl.md): requisitos, build, Compose e instalacion
   del comando `clis`.
3. [Tailscale](tailscale.md): auth key, aprobacion, MagicDNS y exposicion de
   servicios al tailnet.
4. [Moshi](moshi.md): Easy Pair, QR, SSH/Mosh, hooks y validacion.
5. [Agentes y Herdr](agents-and-herdr.md): Codex, OpenCode, integraciones y
   sesiones compartidas entre PC y celular.
6. [Troubleshooting](troubleshooting.md): diagnostico de los errores mas
   frecuentes.

## Flujo recomendado

```bash
# WSL, desde el repositorio clis-code
cp .env.example .env
# Editar .env y definir TS_AUTHKEY
docker compose build clis-code
docker compose up -d
docker compose ps
```

Despues:

1. Aprobar `clis-code` en Tailscale Admin si el tailnet lo exige.
2. Ejecutar Easy Pair desde el servicio persistente.
3. Instalar los hooks de Moshi para Codex y OpenCode.
4. Usar sesiones Herdr con nombre para adjuntarlas desde PC o celular.

## Contextos de comandos

Los ejemplos indican uno de estos contextos:

- **WSL host**: shell de Ubuntu/WSL donde corre Docker.
- **Sesion `clis`**: contenedor efimero abierto con el comando `clis`.
- **Moshi**: shell remoto del servicio persistente `clis-code`.

No son equivalentes. En especial, Easy Pair debe configurarse sobre el home
persistente y los procesos solo existen en el contenedor donde se iniciaron.

## Seguridad

- `.env` contiene una auth key y no debe versionarse.
- `~/.clis-code/home` contiene credenciales de agentes y claves autorizadas.
- `/var/run/docker.sock` concede control equivalente al daemon Docker del host.
- El acceso remoto usa OpenSSH por clave publica sobre Tailscale. No habilites
  Tailscale SSH para el host usado por Moshi.
