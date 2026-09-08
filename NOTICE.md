# Third-party components and redistribution

The MIT license of this repository covers **only** the files it contains:
`Dockerfile`, `docker-entrypoint.sh`, the Compose files, the `Makefile` and the
documentation.

It does not cover the third-party software the `Dockerfile` downloads and
installs at build time, nor `ponytail`, which the entrypoint installs at
container start. Each of those keeps its own license.

| Component | Source | License |
| --- | --- | --- |
| `multica` | [multica-ai/multica](https://github.com/multica-ai/multica) | Multica License (Apache-2.0 plus additional conditions) |
| `codebase-memory-mcp` | [DeusData/codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) | MIT |
| `@openai/codex` | npm | Apache-2.0 |
| `@anthropic-ai/claude-code` | npm | [Anthropic Commercial Terms of Service](https://www.anthropic.com/legal/commercial-terms) |
| `cursor-agent` | [cursor.com/install](https://cursor.com/install) | Proprietary (Cursor terms) |
| `gh` | cli.github.com | MIT |
| `ponytail` | [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) | MIT |

## Practical consequence: do not publish the built image

Building this image for your own use is fine: every tool is downloaded from its
official source, under your own acceptance of its terms.

**Publishing the resulting image to a public registry is a different matter.**
It bundles `@anthropic-ai/claude-code` and `cursor-agent`, two proprietary
binaries whose terms grant no redistribution right. Pushing this image to a
public registry would amount to redistributing them.

CI therefore pushes to **GHCR with private visibility** by default. If you
change that setting, you are making that call knowingly.

`multica` itself is not affected by this restriction: its license permits
distribution, the limit being on operating a hosted service for third parties.
The project publishes its own images.
