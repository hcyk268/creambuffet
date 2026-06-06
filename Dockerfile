# syntax=docker/dockerfile:1

ARG GODOT_VERSION=4.6
ARG GODOT_RELEASE=stable
ARG GODOT_SHA256=

FROM debian:bookworm-slim AS godot-downloader

ARG GODOT_VERSION
ARG GODOT_RELEASE
ARG GODOT_SHA256
ARG TARGETARCH

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		wget \
		unzip \
	&& rm -rf /var/lib/apt/lists/*

RUN set -eux; \
	case "${TARGETARCH:-amd64}" in \
		amd64) godot_platform="linux.x86_64" ;; \
		arm64) godot_platform="linux.arm64" ;; \
		*) echo "Unsupported Docker architecture: ${TARGETARCH}" >&2; exit 1 ;; \
	esac; \
	wget -O /tmp/godot.zip "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-${GODOT_RELEASE}/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_${godot_platform}.zip"; \
	if [ -n "${GODOT_SHA256}" ]; then echo "${GODOT_SHA256}  /tmp/godot.zip" | sha256sum -c -; fi; \
	unzip /tmp/godot.zip -d /tmp/godot; \
	mv "/tmp/godot/Godot_v${GODOT_VERSION}-${GODOT_RELEASE}_${godot_platform}" /usr/local/bin/godot; \
	chmod +x /usr/local/bin/godot

FROM debian:bookworm-slim AS server-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV CREAMBUFFET_SERVER_PORT=7000
ENV CREAMBUFFET_SERVER_MAX_CLIENTS=32
ENV HOME=/home/godot
ENV XDG_DATA_HOME=/home/godot/.local/share
ENV XDG_CONFIG_HOME=/home/godot/.config
ENV XDG_CACHE_HOME=/home/godot/.cache

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		tini \
		libfontconfig1 \
		libfreetype6 \
		libgcc-s1 \
		libstdc++6 \
		libgl1 \
		libx11-6 \
		libxcursor1 \
		libxi6 \
		libxinerama1 \
		libxrandr2 \
		libasound2 \
	&& rm -rf /var/lib/apt/lists/* \
	&& useradd --create-home --home-dir /home/godot --shell /usr/sbin/nologin godot \
	&& mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" \
	&& chown -R godot:godot /home/godot

COPY --from=godot-downloader /usr/local/bin/godot /usr/local/bin/godot

WORKDIR /app/server
COPY --chown=godot:godot server/ /app/server/

USER godot

EXPOSE 7000/udp

STOPSIGNAL SIGTERM
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["sh", "-c", "kill -0 1"]
ENTRYPOINT ["tini", "--"]
CMD ["godot", "--headless", "--path", "/app/server"]
