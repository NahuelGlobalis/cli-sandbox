# Cliente Tailscale oficial para que Moshi pueda descubrir el nombre MagicDNS
# del sidecar mediante el socket compartido.
FROM tailscale/tailscale:stable AS tailscale

# Imagen amd64 con CLIs de codificación asistida y navegadores
FROM ubuntu:24.04

ARG TARGETARCH=amd64
ARG IMAGE_VERSION=dev
ARG NODE_MAJOR=22
ARG PNPM_VERSION=10.21.0
ARG PLAYWRIGHT_VERSION=1.52.0
ARG UV_VERSION=0.11.24
ARG PYTHON_VERSION=3.12
ARG OPENCODE_VERSION=latest
ARG CODEX_VERSION=latest

# Las CLIs propietarias y Google Chrome se distribuyen para amd64.
RUN test "${TARGETARCH}" = "amd64" \
    || (echo "Esta imagen solo admite linux/amd64" >&2 && exit 1)

LABEL org.opencontainers.image.title="clis-code" \
      org.opencontainers.image.description="CLIs de codificación asistida por IA (Devin, Antigravity, OpenCode, Codex, Herdr) + Chrome/Playwright + Docker CLI" \
      org.opencontainers.image.source="https://github.com/nahue/clis-code" \
      org.opencontainers.image.authors="nahue" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/dev \
    SHELL=/bin/bash \
    XDG_DATA_HOME=/home/dev/.local/share \
    HERDR_CONFIG_PATH=/home/dev/.config/herdr/config.toml \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers \
    PATH="/opt/herdr/bin:/home/dev/.local/bin:/opt/pnpm-global/bin:/opt/antigravity/bin:/opt/devin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PNPM_HOME=/opt/pnpm-global

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- 1. Dependencias generales del sistema ---
# Las dependencias gráficas de Chromium se instalan en el bloque de Playwright.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget ca-certificates git gnupg unzip xz-utils openssh-client openssh-server \
        build-essential libssl-dev pkg-config \
        vim nano htop procps tree gosu rsync mosh tmux \
        fonts-liberation fonts-noto-color-emoji xdg-utils \
    && rm -rf /var/lib/apt/lists/* \
    && rm -f /etc/ssh/ssh_host_* \
    && mkdir -p /run/sshd /var/lib/ssh

COPY --from=tailscale /usr/local/bin/tailscale /usr/local/bin/tailscale
COPY sshd_config.d/99-clis-code.conf /etc/ssh/sshd_config.d/99-clis-code.conf

# --- 1b. Docker CLI (Docker-outside-of-Docker) ---
# Se instala solo el cliente; el daemon se consume via socket del host.
RUN install -m 0755 -d /etc/apt/keyrings \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg \
    && chmod a+r /etc/apt/keyrings/docker.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends docker-ce-cli docker-buildx-plugin docker-compose-plugin \
    && rm -rf /var/lib/apt/lists/*

# --- 2. Node.js y pnpm ---
RUN export HOME=/root \
    && curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash - \
    && apt-get update \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable \
    && corepack prepare "pnpm@${PNPM_VERSION}" --activate

# --- 3. Dependencias del sistema para Playwright ---
RUN export HOME=/root \
    && pnpm dlx "playwright@${PLAYWRIGHT_VERSION}" install-deps chromium \
    && rm -rf /root/.cache/pnpm/dlx /tmp/* /var/tmp/*

# --- 4. uv y Python ---
# Python se instala fuera de /home/dev/.local/share/uv para que los volúmenes no lo oculten.
RUN export HOME=/root \
        XDG_DATA_HOME=/root/.local/share \
        UV_INSTALL_DIR=/usr/local/bin \
    && curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | sh \
    && test -x /usr/local/bin/uv \
    && test -x /usr/local/bin/uvx \
    && mkdir -p /opt/uv/python \
    && uv python install --no-bin -i /opt/uv/python "${PYTHON_VERSION}" \
    && PYTHON_BIN="$(uv python find "${PYTHON_VERSION}")" \
    && PYTHON_DIR="$(dirname "${PYTHON_BIN}")" \
    && ln -sf "${PYTHON_BIN}" "/usr/local/bin/python${PYTHON_VERSION}" \
    && ln -sf "python${PYTHON_VERSION}" /usr/local/bin/python3 \
    && ln -sf "python${PYTHON_VERSION}" /usr/local/bin/python \
    && ln -sf "${PYTHON_DIR}/pip" "/usr/local/bin/pip${PYTHON_VERSION}" \
    && ln -sf "pip${PYTHON_VERSION}" /usr/local/bin/pip3 \
    && ln -sf "pip${PYTHON_VERSION}" /usr/local/bin/pip

# --- 5. Usuario y directorios de trabajo ---
RUN userdel -r ubuntu 2>/dev/null || true \
    && groupdel ubuntu 2>/dev/null || true \
    && useradd --create-home --shell /bin/bash --uid 1000 dev \
    && passwd -d dev \
    && mkdir -p /home/dev/.local/bin /home/dev/projects \
        /home/dev/.cache /home/dev/.config/herdr /home/dev/.local/state /home/dev/.local/share \
        /opt/pnpm-global/bin /opt/antigravity/bin /opt/herdr/bin /opt/playwright-browsers \
    && chown -R dev:dev /home/dev /opt/pnpm-global /opt/antigravity /opt/herdr /opt/playwright-browsers /opt/uv

# --- 6. Instalación de las CLIs como dev ---
USER dev
WORKDIR /home/dev

# Configuración global de git para el usuario dev
RUN git config --global user.email "nahuelcano@gmail.com" \
    && git config --global user.name "Nahuel Cano"

RUN pnpm config set global-bin-dir /opt/pnpm-global/bin

# Devin no debe guardar su binario dentro del directorio de credenciales montable.
# El manifest remoto invalida la caché cuando se publica una versión nueva.
ADD --chown=dev:dev https://static.devin.ai/cli/current/manifest.json /tmp/devin-latest.json
RUN curl -fsSL https://cli.devin.ai/install.sh -o /tmp/devin-install.sh \
    && sed -i '/COMPILED_BIN_NAME" setup$/c\true # omitir la configuración durante la build' /tmp/devin-install.sh \
    && bash /tmp/devin-install.sh \
    && rm -f /tmp/devin-install.sh /tmp/devin-latest.json

# Mover el binario de Devin fuera del directorio de credenciales persistentes.
USER root
RUN DEVIN_BIN="$(readlink -f /home/dev/.local/bin/devin)" \
    && test -x "${DEVIN_BIN}" \
    && mkdir -p /opt/devin \
    && cp -a "$(dirname "${DEVIN_BIN}")"/. /opt/devin/ \
    && chown -R dev:dev /opt/devin \
    && rm -rf /home/dev/.local/share/devin \
    && mkdir -p /home/dev/.local/share/devin \
    && chown -R dev:dev /home/dev/.local/share/devin \
    && ln -sf /opt/devin/"$(basename "${DEVIN_BIN}")" /home/dev/.local/bin/devin

USER dev

# Antigravity CLI: el binario se mueve a /opt para que sobreviva al volume del home.
ADD --chown=dev:dev https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/linux_amd64.json /tmp/antigravity-latest.json
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash \
    && mkdir -p /opt/antigravity/bin \
    && mv /home/dev/.local/bin/agy /opt/antigravity/bin/agy \
    && chmod +x /opt/antigravity/bin/agy \
    && ln -sf /opt/antigravity/bin/agy /home/dev/.local/bin/agy \
    && rm -f /tmp/antigravity-latest.json

# OpenCode: se desactivan los scripts automáticos para ejecutar postinstall una sola vez.
ADD --chown=dev:dev https://registry.npmjs.org/opencode-ai/latest /tmp/opencode-latest.json
RUN pnpm add -g --ignore-scripts "opencode-ai@${OPENCODE_VERSION}" \
    && OPENCODE_DIR="$(dirname "$(find /opt/pnpm-global -name "postinstall.mjs" -path "*opencode*" | head -1)")" \
    && test -f "${OPENCODE_DIR}/postinstall.mjs" \
    && node "${OPENCODE_DIR}/postinstall.mjs" \
    && rm -f /tmp/opencode-latest.json

# Codex CLI de OpenAI.
ADD --chown=dev:dev https://registry.npmjs.org/@openai%2Fcodex/latest /tmp/codex-latest.json
RUN pnpm add -g "@openai/codex@${CODEX_VERSION}" \
    && rm -f /tmp/codex-latest.json

# Herdr: el binario vive en /opt para que el volume persistente del home no lo oculte.
# La configuración queda en /home/dev/.config/herdr y se conserva con el resto del home.
# El manifest remoto invalida la caché de esta capa cuando aparece una versión estable.
ADD --chown=dev:dev https://herdr.dev/latest.json /tmp/herdr-latest.json
RUN HERDR_URL="$(awk -F '"' \
        '/^[[:space:]]*"linux-x86_64"[[:space:]]*:/ { print $4; exit }' \
        /tmp/herdr-latest.json)" \
    && test -n "${HERDR_URL}" \
    && curl -fsSL --retry 3 "${HERDR_URL}" -o /opt/herdr/bin/herdr \
    && chmod +x /opt/herdr/bin/herdr \
    && herdr --version \
    && rm -f /tmp/herdr-latest.json

# Moshi Hook: Easy Pair para SSH/Mosh, sesiones tmux y eventos de los agentes.
# El manifest remoto invalida la caché cuando se publica una versión nueva.
USER root
ADD https://cdn.getmoshi.app/hook/latest/version.txt /tmp/moshi-hook-latest.txt
RUN MOSHI_HOOK_VERSION="$(tr -d '[:space:]' </tmp/moshi-hook-latest.txt)" \
    && test -n "${MOSHI_HOOK_VERSION}" \
    && curl -fsSL https://getmoshi.app/install.sh -o /tmp/moshi-install.sh \
    && MOSHI_HOOK_SKIP_FIRST_RUN=1 \
        MOSHI_HOOK_VERSION="${MOSHI_HOOK_VERSION}" \
        INSTALL_DIR=/usr/local/bin \
        sh /tmp/moshi-install.sh \
    && moshi-hook --version \
    && rm -f /tmp/moshi-install.sh /tmp/moshi-hook-latest.txt

USER dev

# Registrar las CLIs del Dockerfile como integraciones de Herdr.
# Las integraciones opcionales agregan estado y restauración de sesiones
# cuando el agente lo admite. Se instalan tras el binario de Herdr.
RUN for cli in devin agy opencode codex; do \
        herdr integration install "$cli" || echo "WARN: integration '$cli' no disponible"; \
    done

# Playwright global y navegador Chromium.
RUN pnpm add -g "playwright@${PLAYWRIGHT_VERSION}" \
    && playwright install chromium

# --- 7. Google Chrome estable ---
# Chrome oficial solo está disponible para amd64; la arquitectura se valida al inicio.
USER root
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub -o /tmp/google-linux-signing.pub \
    && gpg --dearmor --yes -o /usr/share/keyrings/google-linux-signing.gpg /tmp/google-linux-signing.pub \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-linux-signing.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# --- 8. Skeleton del home ---
# Se copia la estructura de /home/dev a /home/dev-skel para que el entrypoint
# pueda sincronizarla cuando el volume del home está vacío (primer arranque).
RUN cp -a /home/dev /home/dev-skel \
    && rm -rf /home/dev-skel/.cache /home/dev-skel/.local/state \
    && mkdir -p /home/dev-skel/.cache /home/dev-skel/.local/state \
    && chown -R dev:dev /home/dev-skel

USER dev
WORKDIR /home/dev/projects

# --- 9. Comprobación básica de binarios y del navegador Playwright ---
HEALTHCHECK --interval=30s --timeout=10s --start-period=20s --retries=3 \
    CMD command -v devin \
    && command -v agy \
    && command -v opencode \
    && command -v codex \
    && command -v herdr \
    && command -v moshi-hook \
    && command -v mosh-server \
    && command -v tmux \
    && command -v sshd \
    && command -v tailscale \
    && command -v uv \
    && command -v pnpm \
    && command -v playwright \
    && command -v google-chrome \
    && command -v docker \
    && test -d /opt/playwright-browsers || exit 1

# --- 10. Entrypoint ---
# Arranca como root para sincronizar el skeleton, ajustar permisos del socket
# de Docker y luego baja privilegios a dev con gosu.
USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
