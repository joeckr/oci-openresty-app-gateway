# OCI OpenResty Gateway

This repository builds a hardened, rootless **OpenResty OIDC Gateway** container image (`ghcr.io/joeckr/openresty`) compliant with modern rootless container standards and Kubernetes Pod Security Standards (`restricted`).

## Purpose

Standard `openresty` images run as `root` by default, do not bundle OpenID Connect (OIDC) Lua modules in the minimal `alpine-slim` variant, and require permission adjustments to run under arbitrary non-root UIDs in restricted Kubernetes and rootless Podman environments.

This project provides:
- A multi-stage build that compiles `lua-resty-openidc` (and its dependencies `lua-resty-http`, `lua-resty-session`, and `lua-resty-jwt`) in `openresty:alpine-fat` and copies only the Lua runtime libraries into `openresty:alpine-slim`.
- Pre-configured OpenID Connect (OIDC) authentication for browser sessions and OAuth 2.0 Bearer token introspection for API clients.
- Rootless, non-root execution (`USER 1031`, GID `0` permissions `g+rwX`) listening on unprivileged port `8080`.
- Dynamic DNS resolver discovery and configuration templating at container startup via `entrypoint.sh`.

## Features

- **Dual OIDC Authentication Modes**:
  - **Web App Flow**: Browser requests are authenticated via the OIDC Authorization Code flow (`resty.openidc.authenticate`) backed by an Nginx shared-memory session store (`lua_shared_dict sessions 10m`).
  - **API Bearer Token Validation**: Requests containing an `Authorization: Bearer <token>` or `Accept: application/json` header validate tokens locally via JWKS signature verification (`resty.openidc.bearer_jwt_verify`), avoiding latency-heavy network round-trips to the IdP. Opaque tokens can also be validated via OAuth 2.0 token introspection (`OIDC_BEARER_VALIDATION_METHOD=introspect`). Validated tokens are exported to `$backend_auth_token`.
  - **CORS Preflight Pass-Through**: `OPTIONS` requests immediately return `200 OK` prior to OIDC checks.
  - **RP-Initiated Logout**: Built-in `/logout` and `/logged_out/` endpoints (`src/logout.conf`).
- **Rootless & Hardened Image Design**: Runs without root privileges (`USER 1031`) and handles arbitrary runtime UIDs (`chgrp -R 0` and `chmod -R g+rwX`) under restricted Pod Security Standards.
- **Minimal Alpine Footprint**: Uses a multi-stage build to keep the final image based on `openresty:<version>-alpine-slim` without shipping compiler toolchains or Luarocks build dependencies.
- **Dynamic Resolver Configuration**: Automatically resolves the container's nameserver from `/etc/resolv.conf` (or uses `NGINX_RESOLVER`) at startup.
- **Modular Routing**: Includes `/etc/nginx/oidc/*.conf` so static assets (`src/client.conf`) or reverse-proxy upstream routes can be mounted or extended cleanly.

## Repository Structure

- `Dockerfile`: Multi-stage Dockerfile building the hardened OpenResty OIDC gateway image.
- `src/entrypoint.sh`: Startup script that detects `NGINX_RESOLVER`, renders configuration templates with `envsubst`, and launches OpenResty.
- `src/nginx.conf`: Core OpenResty configuration defining non-root temp paths under `/tmp/nginx/*`, shared session memory (`sessions`), and environment variable passthrough.
- `src/oidc.conf`: Server block on port `8080` implementing Lua OIDC authentication and Bearer token introspection.
- `src/client.conf`: Default static location block (`/`) serving `/usr/share/nginx/html`.
- `src/logout.conf`: OIDC `/logout` and `/logged_out/` location blocks.
- `src/index.html`: Default placeholder landing page.
- `compose.yml`: Local Podman/Docker Compose stack for building and testing the gateway image.
- `compose.upstream.yml`: Baseline Compose configuration using the unmodified upstream OpenResty image.
- `mise.toml`: Task runner definitions for local builds, compose workflows, linting, and Trivy security scans.
- `.github/workflows/`: Automated CI/CD workflows for linting, security auditing, and multi-arch image releases.

## Configuration & Environment Variables

The gateway is configured at runtime via environment variables passed to the container:

| Variable | Default | Description |
|---|---|---|
| `OIDC_ENABLED` | *(unset)* | Set to `"true"` to enforce OIDC authentication and Bearer introspection. When unset or not `"true"`, requests bypass OIDC checks. |
| `OIDC_ISSUER` | *(required when enabled)* | Base OIDC issuer URL (e.g., `https://idp.example.com/realms/main`). `/.well-known/openid-configuration` is appended automatically. |
| `OIDC_CLIENT_ID` | *(required when enabled)* | OIDC relying party client ID. |
| `OIDC_CLIENT_SECRET` | *(required when enabled)* | OIDC relying party client secret. |
| `OIDC_REDIRECT_URI` | *(required when enabled)* | Base application URL (e.g., `https://app.example.com`). `/redirect_uri` and `/logged_out` are appended automatically. |
| `OIDC_SSL_VERIFY` | *(required when enabled)* | Set to `"yes"` or `"no"` to control TLS certificate verification against the OIDC discovery/token endpoints. |
| `OIDC_SESSION_SECRET` | *(required when enabled)* | Secret string used by `lua-resty-session` to encrypt session cookies. |
| `OIDC_COOKIE_SECURE` | `"false"` | Set to `"true"` to mark session cookies `Secure` (HTTPS-only). |
| `OIDC_BEARER_VALIDATION_METHOD` | `"jwt"` | Method for validating Bearer tokens: `"jwt"` (local signature & claims validation via JWKS) or `"introspect"` (outbound OAuth 2.0 introspection call). |
| `NGINX_RESOLVER` | First `nameserver` in `/etc/resolv.conf` | DNS resolver IP injected into `resolver ${NGINX_RESOLVER} valid=30s;`. |

## Security & Hardened Image Architecture

Modern hardened Kubernetes environments enforce strict runtime constraints under the **Pod Security Admission (PSA)** `restricted` profile:

- **Must Run As Non-Root**: The image runs as `USER 1031` so it never executes as UID `0` (and avoids Nginx's root `chown()` behavior on temp directories).
- **Arbitrary Dynamic UIDs**: Runtime configuration and temp directories (`/tmp/nginx`, `/var/run/openresty`, `/usr/local/openresty/nginx/logs`, `/usr/local/openresty/nginx/conf`, `/etc/nginx/conf.d`) are assigned to group `0` (`chgrp -R 0`) with group read/write/execute permissions (`chmod -R g+rwX`).
- **Unprivileged Ports**: OpenResty listens on port `8080` (`> 1024`), allowing all Linux capabilities (`ALL`, including `NET_BIND_SERVICE` and `CHOWN`) to be dropped.
- **Ephemeral PID & Temp Paths**: PID file (`/tmp/nginx.pid`) and temp directories (`/tmp/nginx/*`) reside in `/tmp` to support read-only root filesystems when `/tmp` and config directories are mounted as writable volumes.

### Compliance Matrix

| Security Dimension | Restricted Standard Requirement | Implementation in This Repo |
|---|---|---|
| **Build Execution** | Unprivileged / rootless builder compatible | Multi-stage build runs cleanly via rootless Podman/Buildah (`mise run build`) |
| **User ID** | Non-root UID (`runAsNonRoot: true`) / dynamic UID | `USER 1031` in `Dockerfile` |
| **Group Permissions** | GID `0` (`root` group) with `g+rwX` | `chgrp -R 0` & `chmod -R g+rwX` on runtime & config paths |
| **Port Binding** | Unprivileged (`> 1024`) | Listens on port `8080` (`EXPOSE 8080`) |

---

## Local Testing & Development

### 1. Build and Run with Podman Compose (`compose.yml`)

```sh
# Build and start the gateway container
mise run compose
# or: podman compose up -d --build

# View container logs
mise run logs
# or: podman compose logs -f

# Verify connectivity (with OIDC_ENABLED unset, returns index.html)
curl http://localhost:8080

# Stop the stack
mise run down
# or: podman compose down
```

### 2. Baseline Upstream Comparison (`compose.upstream.yml`)

To compare against the unmodified upstream `openresty/openresty:1.27.1.2-alpine-fat` image:

```sh
podman compose -f compose.upstream.yml up -d
podman compose -f compose.upstream.yml down
```

### 3. Linting & Security Scanning

```sh
# Run pre-commit and linter checks (hadolint, shellcheck, actionlint, zizmor, etc.)
mise run hk

# Build local test image and scan with Trivy
mise run trivy-fs
mise run trivy-i
```

---

## Mise Tasks Quick Reference

| Task | Description | Command |
|---|---|---|
| `install` | Install Git hooks (`pre-commit` and `commit-msg`). | `hk install --mise` |
| `hk` (or `check`) | Run all repository pre-commit and formatting checks. | `hk check --all` |
| `build` | Build local test container image for `linux/amd64`. | `podman buildx build --platform linux/amd64 -t ghcr.io/joeckr/openresty:test . --load` |
| `compose` | Build and run the gateway image in Podman Compose. | `podman compose up -d --build` |
| `down` | Stop and remove the Podman Compose stack. | `podman compose down` |
| `logs` | Follow logs from the Podman Compose stack. | `podman compose logs -f` |
| `trivy-fs` | Scan repository filesystem for security vulnerabilities. | `trivy fs .` |
| `trivy-i` | Scan the built container image with Trivy. | `trivy image ghcr.io/joeckr/openresty:test` |

## Support

If you find this project useful, consider supporting my work on [Ko-fi](https://ko-fi.com/joeckr):

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/joeckr)

## License

Licensed under the Apache License, Version 2.0. Please refer to the [LICENSE](LICENSE) file for details.
