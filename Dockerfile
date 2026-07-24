# Imagen amd64 con CLIs de codificación asistida y navegadores
FROM ubuntu:24.04

ARG TARGETARCH=amd64
ARG IMAGE_VERSION=dev
ARG NODE_MAJOR=22
ARG PNPM_VERSION=10.21.0
ARG PLAYWRIGHT_VERSION=1.52.0
ARG UV_VERSION=0.11.24
ARG PYTHON_VERSION=3.12
ARG OPENCODE_VERSION=1.16.2
ARG CODEX_VERSION=0.145.0

# Las CLIs propietarias y Google Chrome se distribuyen para amd64.
RUN test "${TARGETARCH}" = "amd64" \
    || (echo "Esta imagen solo admite linux/amd64" >&2 && exit 1)

LABEL org.opencontainers.image.title="clis-code" \
      org.opencontainers.image.description="CLIs de codificación asistida por IA (Devin, Antigravity, OpenCode, Codex) + Chrome/Playwright + Docker CLI" \
      org.opencontainers.image.source="https://github.com/nahue/clis-code" \
      org.opencontainers.image.authors="nahue" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/home/dev \
    XDG_DATA_HOME=/home/dev/.local/share \
    UV_PYTHON_INSTALL_DIR=/opt/uv/python \
    PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers \
    PATH="/home/dev/.local/bin:/opt/pnpm-global/bin:/opt/antigravity/bin:/opt/devin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    PNPM_HOME=/opt/pnpm-global

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# --- 1. Dependencias generales del sistema ---
# Las dependencias gráficas de Chromium se instalan en el bloque de Playwright.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        curl wget ca-certificates git gnupg unzip xz-utils openssh-client \
        build-essential libssl-dev pkg-config \
        vim nano htop procps tree gosu rsync \
        fonts-liberation fonts-noto-color-emoji xdg-utils \
    && rm -rf /var/lib/apt/lists/*

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
    && uv python install -i /opt/uv/python "${PYTHON_VERSION}" \
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
    && mkdir -p /home/dev/.local/bin /home/dev/projects \
        /home/dev/.cache /home/dev/.config /home/dev/.local/state /home/dev/.local/share \
        /opt/pnpm-global/bin /opt/antigravity/bin /opt/playwright-browsers \
    && chown -R dev:dev /home/dev /opt/pnpm-global /opt/antigravity /opt/playwright-browsers /opt/uv

# --- 6. Instalación de las CLIs como dev ---
USER dev
WORKDIR /home/dev

# Configuración global de git para el usuario dev
RUN git config --global user.email "nahuelcano@gmail.com" \
    && git config --global user.name "Nahuel Cano"

RUN pnpm config set global-bin-dir /opt/pnpm-global/bin

# Devin no debe guardar su binario dentro del directorio de credenciales montable.
RUN curl -fsSL https://cli.devin.ai/install.sh -o /tmp/devin-install.sh \
    && sed -i '/COMPILED_BIN_NAME" setup$/c\true # omitir la configuración durante la build' /tmp/devin-install.sh \
    && bash /tmp/devin-install.sh \
    && rm -f /tmp/devin-install.sh

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
RUN curl -fsSL https://antigravity.google/cli/install.sh | bash \
    && mkdir -p /opt/antigravity/bin \
    && mv /home/dev/.local/bin/agy /opt/antigravity/bin/agy \
    && chmod +x /opt/antigravity/bin/agy \
    && ln -sf /opt/antigravity/bin/agy /home/dev/.local/bin/agy

# OpenCode: se desactivan los scripts automáticos para ejecutar postinstall una sola vez.
RUN pnpm add -g --ignore-scripts "opencode-ai@${OPENCODE_VERSION}" \
    && OPENCODE_DIR="$(dirname "$(find /opt/pnpm-global -name "postinstall.mjs" -path "*opencode*" | head -1)")" \
    && test -f "${OPENCODE_DIR}/postinstall.mjs" \
    && node "${OPENCODE_DIR}/postinstall.mjs"

# Codex CLI de OpenAI.
RUN pnpm add -g "@openai/codex@${CODEX_VERSION}"

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
