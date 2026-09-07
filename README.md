# Multica agent runtime — image Docker reutilisable

Runtime Multica conteneurise : daemon `multica`, CLI agents (Claude Code, Codex,
Cursor) et `codebase-memory-mcp` cable automatiquement au demarrage.

Concu pour etre depose tel quel sur n'importe quel serveur : tout ce qui est
specifique a une machine vit dans `.env`, jamais dans le `Dockerfile` ni dans le
`docker-compose.yml`.

## Demarrage rapide

```bash
cp .env.example .env
$EDITOR .env              # MULTICA_TOKEN, MULTICA_DATA_ROOT, device name
docker compose up -d --build
docker compose logs -f
```

Sans `MULTICA_TOKEN`, le conteneur demarre et attend, puis :

```bash
docker compose exec multica-runtime multica login --token
docker compose restart multica-runtime
```

## Image prete a l'emploi (GHCR)

La CI construit une image multi-arch (amd64 + arm64) et la pousse sur GHCR.
Sur un nouveau serveur, plus besoin de rebuilder :

```bash
docker login ghcr.io -u <user> -p <token-avec-read:packages>
MULTICA_IMAGE=ghcr.io/digital-kickoff-labs/multica-runtime-docker:latest \
  docker compose up -d --no-build
```

Le registre est en visibilite **privee** par defaut, et ce n'est pas un detail
d'organisation : voir [NOTICE.md](NOTICE.md).

## Ce qui persiste

| Chemin conteneur       | Support                          | Contenu                                        |
| ---------------------- | -------------------------------- | ---------------------------------------------- |
| `/home/node`           | volume nomme `multica_home`      | auth Multica, `~/.claude`, `~/.codex`, `~/.cursor` |
| `/data/workspaces`     | bind `${MULTICA_DATA_ROOT}`      | workspaces des runs                            |
| `/data/codebase-memory`| bind `${MULTICA_DATA_ROOT}`      | index codebase-memory-mcp                      |
| `/workspace`           | volume nomme `multica_scratch`   | scratch                                        |

Aucun binaire livre par l'image ne vit dans `/home/node` : l'outillage est en
`/usr/local/bin`, `/opt/cursor` et `/opt/multica/bin`. Un `docker compose build`
suivi d'un `up -d` met donc reellement a jour les CLI, meme si le volume home
existe deja.

## Portage sur un autre serveur

1. Copier le dossier (ou cloner le repo qui le contient).
2. `cp .env.example .env`, renseigner `MULTICA_TOKEN`, `MULTICA_DATA_ROOT`,
   `MULTICA_DAEMON_DEVICE_NAME`.
3. Aligner `PUID`/`PGID` sur le proprietaire du repertoire hote
   (`stat -c '%u %g' "$MULTICA_DATA_ROOT"`).
4. `docker compose up -d --build`.

Plusieurs runtimes sur une meme machine : changer `COMPOSE_PROJECT_NAME`,
`MULTICA_DAEMON_DEVICE_NAME` et poser `MULTICA_PROFILE` (isole config, etat du
daemon et workspaces cote CLI).

## Coolify

Pointer l'application Coolify sur le repo, type « Docker Compose », fichier
`docker-compose.yml`. Les variables Coolify remplacent le `.env`. Le service est
`build:` — pas de `dockerfile_inline`, donc le `Dockerfile` reste relisable et
diffable en revue.

## Builds reproductibles

`MULTICA_REF=main` reconstruit depuis la branche, mais Docker met en cache la
couche `git fetch` : un `build` ne rapatriera pas forcement le dernier commit.

- Reproductible : epingler un tag ou un SHA — `MULTICA_REF=v1.4.2`.
- Forcer un rafraichissement sur `main` : `make rebuild`
  (`docker compose build --no-cache-filter multica-builder`).

Meme logique pour `CLAUDE_CODE_VERSION`, `CODEX_VERSION` et `CBM_VERSION` :
`latest` par defaut pour demarrer, a epingler des que le runtime est en prod.

`codebase-memory-mcp` est verifie en deux temps : `checksums.txt` contre le
sha256 epingle (`CBM_CHECKSUMS_SHA256`), puis l'archive contre `checksums.txt`.
Changer `CBM_VERSION` impose de mettre a jour ce sha256.

## Auto-update du daemon

`MULTICA_DAEMON_AUTO_UPDATE=false` par defaut : l'image est l'unite de
deploiement, on met a jour par rebuild. Si tu preferes l'auto-update, passe la
variable a `true` — le binaire est en `/opt/multica/bin`, repertoire possede par
`node`, donc l'ecriture fonctionne (ce n'etait pas le cas avec un binaire
root-only sous `/usr/local/bin`).

## Screenshots / navigateur

`INSTALL_BROWSER_DEPS=true` ajoute Chromium et les polices necessaires aux
captures d'ecran des agents. `shm_size` est a 1 Go pour eviter les crashes
Chromium en `/dev/shm` trop petit.

## Plafonds de ressources

```bash
docker compose -f docker-compose.yml -f docker-compose.limits.yml up -d
```

## Depannage

```bash
make status                      # etat du daemon
make health                      # healthcheck Docker
docker compose logs --tail=200   # bootstrap + daemon
make shell                       # shell dans le conteneur
```

`MULTICA_FIX_PERMISSIONS` : `shallow` (defaut, corrige la racine si non
inscriptible), `deep` (chown recursif, lent sur gros volumes), `off`.

## Notes d'implementation

- **Pas de `USER node` dans l'image** : l'entrypoint demarre en root pour aligner
  les droits des bind mounts (`PUID`/`PGID`), puis redescend via `gosu`. Le
  daemon ne tourne jamais en root. Corollaire : `docker compose exec` doit
  passer `--user node` (c'est ce que fait le `Makefile`), sinon les fichiers
  ecrits dans `/home/node` deviennent root-owned et cassent le demarrage suivant.
- **`tini` est dans l'image** (`ENTRYPOINT`), donc pas de `init: true` dans le
  compose : un seul reaper de zombies, ce qui compte quand les agents lancent
  des arbres de sous-processus.
- **Le healthcheck passe par `gosu`** pour interroger l'etat du daemon avec le
  bon utilisateur.

## Licence

Le contenu de ce depot est sous licence MIT (voir [LICENSE](LICENSE)).

Cette licence ne couvre **que** les fichiers du depot. Les logiciels que le
build telecharge — dont Claude Code et cursor-agent, proprietaires — gardent
leurs propres conditions. C'est la raison pour laquelle l'image construite ne
doit pas etre republiee sur un registre public : [NOTICE.md](NOTICE.md) detaille
le raisonnement composant par composant.
