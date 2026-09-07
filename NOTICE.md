# Composants tiers et redistribution

La licence MIT de ce depot couvre **uniquement** les fichiers qu'il contient :
`Dockerfile`, `docker-entrypoint.sh`, les fichiers Compose, le `Makefile` et la
documentation.

Elle ne couvre pas les logiciels tiers que le `Dockerfile` telecharge et
installe au moment du build. Chacun reste soumis a sa propre licence.

| Composant | Source | Licence |
| --- | --- | --- |
| `multica` | [multica-ai/multica](https://github.com/multica-ai/multica) | Multica License (Apache-2.0 + conditions additionnelles) |
| `codebase-memory-mcp` | [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | MIT |
| `@openai/codex` | npm | Apache-2.0 |
| `@anthropic-ai/claude-code` | npm | [Anthropic Commercial Terms of Service](https://www.anthropic.com/legal/commercial-terms) |
| `cursor-agent` | [cursor.com/install](https://cursor.com/install) | Proprietaire (conditions Cursor) |
| `gh` | cli.github.com | MIT |

## Consequence pratique : ne pas publier l'image construite

Construire cette image pour ton propre usage est sans probleme : chaque outil
est telecharge depuis sa source officielle, sous ta propre acceptation de ses
conditions.

**Publier l'image resultante sur un registre public est une autre chose.** Elle
embarque `@anthropic-ai/claude-code` et `cursor-agent`, deux binaires
proprietaires dont les conditions n'accordent pas de droit de redistribution.
Pousser cette image sur un registre public reviendrait a les redistribuer.

La CI de ce depot pousse donc vers **GHCR en visibilite privee** par defaut. Si
tu changes ce reglage, tu prends cette decision en connaissance de cause.

`multica` lui-meme n'est pas concerne par cette restriction : sa licence
autorise la distribution, la limite portant sur l'exploitation en service
heberge pour des tiers. Le projet publie d'ailleurs ses propres images.
