# Multica agent runtime — reusable Docker image

Containerised Multica runtime: the `multica` daemon, the agent CLIs (Claude
Code, Codex, Cursor) and `codebase-memory-mcp`, wired up automatically at start.

Designed to be dropped as-is onto any server: everything machine-specific lives
in `.env`, never in the `Dockerfile` or in `docker-compose.yml`.

## Quick start

```bash
cp .env.example .env
$EDITOR .env              # MULTICA_TOKEN, MULTICA_DATA_ROOT, device name
docker compose up -d --build
docker compose logs -f
```

Without `MULTICA_TOKEN` the container starts and waits, then:

```bash
docker compose exec multica-runtime multica login --token
docker compose restart multica-runtime
```

## Prebuilt image (GHCR)

CI builds a multi-arch image (amd64 + arm64) and pushes it to GHCR. On a new
server there is nothing left to build:

```bash
docker login ghcr.io -u <user> -p <token-with-read:packages>
MULTICA_IMAGE=ghcr.io/digital-kickoff-labs/multica-runtime-docker:latest \
  docker compose up -d --no-build
```

The registry is **private** by default, and that is not an organisational
detail: see [NOTICE.md](NOTICE.md).

## What persists

| Container path          | Backing store                    | Contents                                            |
| ----------------------- | -------------------------------- | --------------------------------------------------- |
| `/home/node`            | named volume `multica_home`      | Multica auth, `~/.claude`, `~/.codex`, `~/.cursor`   |
| `/data/workspaces`      | bind `${MULTICA_DATA_ROOT}`      | run workspaces                                       |
| `/data/codebase-memory` | bind `${MULTICA_DATA_ROOT}`      | codebase-memory-mcp index                            |
| `/workspace`            | named volume `multica_scratch`   | scratch                                              |

No image-provided binary lives in `/home/node`: tooling sits in
`/usr/local/bin`, `/opt/cursor` and `/opt/multica/bin`. A `docker compose build`
followed by `up -d` therefore really does update the CLIs, even when the home
volume already exists.

## Moving to another server

1. Copy the directory (or clone the repository holding it).
2. `cp .env.example .env`, then fill in `MULTICA_TOKEN`, `MULTICA_DATA_ROOT` and
   `MULTICA_DAEMON_DEVICE_NAME`.
3. Match `PUID`/`PGID` to the owner of the host directory
   (`stat -c '%u %g' "$MULTICA_DATA_ROOT"`).
4. `docker compose up -d --build`.

Several runtimes on one machine: change `COMPOSE_PROJECT_NAME` and
`MULTICA_DAEMON_DEVICE_NAME`, and set `MULTICA_PROFILE` (it isolates config,
daemon state and workspaces on the CLI side).

## Coolify

Point the Coolify application at the repository, type "Docker Compose", file
`docker-compose.yml`. Coolify variables replace the `.env`. The service uses
`build:` — no `dockerfile_inline`, so the `Dockerfile` stays readable and
reviewable in a diff.

## Reproducible builds

`MULTICA_REF=main` rebuilds from the branch, but Docker caches the `git fetch`
layer: a `build` will not necessarily pick up the latest commit.

- Reproducible: pin a tag or a SHA — `MULTICA_REF=v1.4.2`.
- Force a refresh on `main`: `make rebuild`
  (`docker compose build --no-cache-filter multica-builder`).

The same applies to `CLAUDE_CODE_VERSION`, `CODEX_VERSION` and `CBM_VERSION`:
`latest` to get started, pin them once the runtime is in production.

`codebase-memory-mcp` is verified in two steps: `checksums.txt` against the
pinned sha256 (`CBM_CHECKSUMS_SHA256`), then the archive against
`checksums.txt`. Changing `CBM_VERSION` means updating that sha256.

## Daemon auto-update

`MULTICA_DAEMON_AUTO_UPDATE=false` by default: the image is the deployment unit,
updates happen through a rebuild. If you prefer auto-update, flip the variable to
`true` — the binary lives in `/opt/multica/bin`, a directory owned by `node`, so
the write succeeds (which was not the case with a root-only binary under
`/usr/local/bin`).

## Screenshots / browser

`INSTALL_BROWSER_DEPS=true` adds Chromium and the fonts agents need for
screenshots. `shm_size` is set to 1 GB to avoid Chromium crashes caused by a
`/dev/shm` that is too small.

## Resource caps

```bash
docker compose -f docker-compose.yml -f docker-compose.limits.yml up -d
```

## Troubleshooting

```bash
make status                      # daemon status
make health                      # Docker healthcheck
docker compose logs --tail=200   # bootstrap + daemon
make shell                       # shell inside the container
```

`MULTICA_FIX_PERMISSIONS`: `shallow` (default, fixes the root directory when it
is not writable), `deep` (recursive chown, slow on large volumes), `off`.

## Implementation notes

- **No `USER node` in the image**: the entrypoint starts as root to align bind
  mount permissions (`PUID`/`PGID`), then drops to `node` through `gosu`. The
  daemon never runs as root. Consequence: `docker compose exec` must pass
  `--user node` (the `Makefile` does), otherwise files written to `/home/node`
  end up root-owned and break the next start.
- **`tini` ships in the image** (`ENTRYPOINT`), so there is no `init: true` in
  the compose file: a single zombie reaper, which matters when agents spawn
  trees of subprocesses.
- **The healthcheck goes through `gosu`** so it queries daemon state as the
  right user.

## License

The contents of this repository are MIT licensed (see [LICENSE](LICENSE)).

That license covers **only** the files in this repository. The software the
build downloads — including Claude Code and cursor-agent, both proprietary —
keeps its own terms. This is why the resulting image must not be republished to
a public registry: [NOTICE.md](NOTICE.md) walks through the reasoning component
by component.
