# codex-tandem

**Run OpenAI Codex and DeepSeek side by side — two agents, two isolated homes,
one installer.**

`codex-tandem` installs the Codex CLI once and gives you two commands that never
step on each other:

| Command | Talks to | Config | Sessions and history |
| --- | --- | --- | --- |
| `codex` | OpenAI, with your ChatGPT account | `~/.codex/config.toml` | `~/.codex/` |
| `deepseek` | DeepSeek, with an API key | `~/.codex-deepseek/config.toml` | `~/.codex-deepseek/` |

Both are the same binary. The difference is `CODEX_HOME`: a separate home means
separate sessions, separate history, separate credentials and separate locks, so
the two commands can run **at the same time**, even in the same repository.

```
                    ┌──────────────────────────────┐
   codex  ─────────▶│  CODEX_HOME=~/.codex         │──▶  api.openai.com
                    │  ChatGPT login, own sessions │
                    └──────────────────────────────┘
                              one codex binary
                    ┌──────────────────────────────┐
   deepseek ───────▶│  CODEX_HOME=~/.codex-deepseek│──▶  api.deepseek.com
                    │  API key, own sessions       │
                    └──────────────────────────────┘
```

## Why

- **Compare answers.** Give the same task to two models in two terminals.
- **Separate billing and identity.** ChatGPT subscription on one side, a
  metered API key on the other. Neither can see the other's credentials.
- **No shared state.** A long-running DeepSeek session never blocks a Codex
  session, and neither shows up in the other's history or `resume` picker.
- **One thing to install.** No Node, no Python packages, no containers: the
  official Codex installer plus a small wrapper.

## Requirements

- Ubuntu or another Linux distribution with bash, `tar`, `curl` or `wget`.
- `python3` — only used once, to build the DeepSeek model catalog from your own
  Codex installation.
- A ChatGPT account for `codex` (or an OpenAI API key) and a DeepSeek API key
  for `deepseek`. Get the DeepSeek key at
  <https://platform.deepseek.com/api_keys>.

No root required. The installer lives entirely inside your `$HOME` and refuses
to run under `sudo`.

## Install

Clone and run:

```bash
git clone https://github.com/martingaldeca/codex-tandem.git
cd codex-tandem
./install.sh
```

Or, if you prefer a single command, the script can bootstrap itself (it
downloads the repository into a temporary directory and re-executes from there):

```bash
curl -fsSL https://raw.githubusercontent.com/martingaldeca/codex-tandem/main/install.sh | bash
```

Then:

```bash
codex login        # once, with your ChatGPT account
deepseek           # asks for the DeepSeek API key the first time and stores it
```

Open a new shell (or `source ~/.bashrc`) so that `~/.local/bin` is on `PATH`.

### Non-interactive install

```bash
DEEPSEEK_API_KEY=sk-... ./install.sh
```

Any value you pass in `DEEPSEEK_API_KEY` is written to
`~/.config/deepseek/api_key` with mode `600`.

## What the installer does

1. **Checks the system.** Linux, non-root, `tar`, `curl` or `wget`.
2. **Installs the Codex CLI** with the official standalone installer
   (`https://chatgpt.com/codex/install.sh`) into `~/.local/bin/codex`.
3. **Configures Codex** in `~/.codex/config.toml` and drops an example
   `~/.codex/AGENTS.md` if you do not have one yet.
4. **Creates the second home** `~/.codex-deepseek/` with its own `config.toml`,
   the DeepSeek provider definition and a generated model catalog, and links
   `packages`, `skills`, `plugins` and `AGENTS.md` back to `~/.codex` so both
   sides share your tools and instructions.
5. **Installs the `deepseek` command** in `~/.local/bin/deepseek`.
6. **Stores the API key** in `~/.config/deepseek/api_key` (mode `600`).
7. **Optionally copies your skills** (`--skills-from DIR`) and adds
   `~/.local/bin` to `PATH` in `~/.bashrc` and `~/.zshrc`.
8. **Verifies** that both homes load their model catalogs.

The installer is idempotent: run it again after a `git pull` and it only adds
what is missing. Existing files are never overwritten unless you pass `--force`,
which leaves a `.bak.<timestamp>` copy first.

## Usage

### Everyday, in parallel

```bash
# terminal 1
cd ~/project && codex

# terminal 2
cd ~/project && deepseek
```

Or side by side in tmux:

```bash
tmux new-session -d 'codex' \; split-window -h 'deepseek' \; attach
```

### The `deepseek` command

`deepseek` forwards everything to `codex` with the DeepSeek home, provider and
key already set, so every Codex flag works:

```bash
deepseek                                  # interactive TUI
deepseek exec "summarise this repository"  # non-interactive
deepseek review --base main                # code review
deepseek -m deepseek-v4-pro                # the other model in the catalog
deepseek resume --last                     # pick up your last DeepSeek session
deepseek --check                           # diagnose the DeepSeek setup
```

`--check` prints the home, the catalog path, the model, where the key comes from
and the Codex version — useful when something feels off.

### Running both from a script

```bash
codex exec "list the risky parts of this diff"    > codex.md
deepseek exec "list the risky parts of this diff" > deepseek.md
diff -u codex.md deepseek.md
```

### Environment variables

| Variable | Used by | Default | Meaning |
| --- | --- | --- | --- |
| `DEEPSEEK_API_KEY` | `deepseek` | — | Key. Overrides the stored file. |
| `DEEPSEEK_MODEL` | `deepseek` | `deepseek-flash` | Model id passed to Codex. |
| `DEEPSEEK_CODEX_HOME` | `deepseek` | `~/.codex-deepseek` | Its `CODEX_HOME`. |
| `DEEPSEEK_KEY_FILE` | `deepseek` | `~/.config/deepseek/api_key` | Where the key lives. |
| `DEEPSEEK_CATALOG` | `deepseek` | `$DEEPSEEK_CODEX_HOME/models-deepseek.json` | Model catalog. |
| `CODEX_BIN` | `deepseek` | `codex` | Which binary to launch. |

## Installer options

| Option | Effect |
| --- | --- |
| `--dry-run` | Print every action, write nothing. |
| `--force` | Replace existing config files, keeping `.bak.<timestamp>` copies. |
| `--skip-codex` | Do not install or update the Codex CLI. |
| `--codex-version X` | Install a specific Codex CLI version (default: latest). |
| `--base-model SLUG` | Codex model whose instruction template is reused for the DeepSeek catalog. |
| `--skills-from DIR` | Copy your own skills from `DIR` into `~/.codex/skills`. |
| `--no-agents` | Do not install the example `~/.codex/AGENTS.md`. |
| `--safe-permissions` | Keep Codex's normal sandbox instead of the author's no-sandbox default. |
| `--login` | Run `codex login` at the end. |
| `-h`, `--help` | Full help. |

Environment equivalents: `DEEPSEEK_MODEL`, `DEEPSEEK_BASE_URL`, `CODEX_MODEL`,
`CODEX_EFFORT`, `CODEX_INSTALL_DIR`, `CODEX_CLI_VERSION`, `BASE_MODEL`,
`TANDEM_REPO`, `TANDEM_REF`.

### Reproducing a specific setup

```bash
CODEX_MODEL=gpt-5.6-luna \
DEEPSEEK_MODEL=deepseek-flash \
CODEX_CLI_VERSION=0.154.0 \
./install.sh --skills-from ~/skills-backup
```

## Configuration files

`~/.codex/config.toml` — your normal Codex configuration. The installer only
creates it when it does not exist.

`~/.codex-deepseek/config.toml` — the DeepSeek side:

```toml
model = "deepseek-flash"
model_provider = "deepseek"
preferred_auth_method = "apikey"
forced_login_method = "api"
model_reasoning_effort = "max"
web_search = "disabled"
model_catalog_json = "/home/you/.codex-deepseek/models-deepseek.json"

[model_providers.deepseek]
name = "deepseek"
base_url = "https://api.deepseek.com/"
wire_api = "responses"
env_key = "DEEPSEEK_API_KEY"
```

`~/.local/bin/deepseek` — a small wrapper, roughly:

```bash
DEEPSEEK_API_KEY=... CODEX_HOME="$HOME/.codex-deepseek" codex \
  -c 'model="deepseek-flash"' \
  -c 'model_provider="deepseek"' \
  -c 'model_catalog_json="$HOME/.codex-deepseek/models-deepseek.json"' \
  "$@"
```

That is the whole trick: same binary, different `CODEX_HOME`.

## The model catalog, and why it is generated

Codex needs a *model catalog* to know which models exist for a provider. For
third-party providers you have to supply one, and a Codex model entry embeds a
very large instruction template.

Shipping that template in this repository would mean redistributing text that
belongs to the Codex installation you already have, so `codex-tandem` does not
ship it. Instead:

1. `assets/catalog/deepseek-catalog.template.json` describes the two DeepSeek
   entries — capabilities, context window, reasoning levels, tool support — with
   a placeholder where the instruction template goes.
2. `tools/build-deepseek-catalog.py` reads the catalog from *your* Codex
   installation (`codex debug models`), copies the instruction template out of
   it and writes the finished `~/.codex-deepseek/models-deepseek.json`.

Nothing is downloaded from a third party, and the generated file stays on your
machine. Choose the source model with `--base-model` if you want a particular
prompt revision; by default the model already configured in `~/.codex/config.toml`
is used.

You can also build it by hand:

```bash
python3 tools/build-deepseek-catalog.py \
  --template assets/catalog/deepseek-catalog.template.json \
  --output ~/.codex-deepseek/models-deepseek.json \
  --base-model gpt-5.6-luna
```

If you prefer to distribute a fixed catalog (for example inside a private
bundle for your own machines), drop it at `assets/models-deepseek.json` before
running the installer: that file takes precedence over the generated one.

## Adding another provider

Any OpenAI-compatible endpoint can become a third command in a couple of
minutes. Copy the wrapper, point it at a new home and a new provider block:

```bash
cp ~/.local/bin/deepseek ~/.local/bin/moonshot
sed -i 's/deepseek/moonshot/g; s/DEEPSEEK/MOONSHOT/g' ~/.local/bin/moonshot
mkdir -p ~/.codex-moonshot
cp ~/.codex-deepseek/config.toml ~/.codex-moonshot/config.toml
```

Then edit `~/.codex-moonshot/config.toml` with the new `base_url`, `env_key`,
model id and catalog path. Because each provider gets its own `CODEX_HOME`, you
can now run `codex`, `deepseek` and `moonshot` at the same time.

## Permissions and security

- **The repository contains no credentials.** Keys are read from
  `DEEPSEEK_API_KEY` or typed at a prompt, then written with mode `600` under
  `~/.config/deepseek/`. `.gitignore` also blocks accidental commits of
  `api_key`, `auth.json` and `.env` files.
- **`default_permissions = ":danger-full-access"`** is written to both homes by
  default, matching the workflow this project came from: Codex runs commands
  without the sandbox asking for approval. If you would rather keep Codex's
  normal sandbox, install with `--safe-permissions` or edit the generated
  `config.toml` files.
- **`web_search` is disabled** for the DeepSeek provider: DeepSeek has no
  server-side web search hook here, so the tool is not advertised to the model.
- Codex itself is installed by OpenAI's official installer; this repository only
  supplies configuration and a launcher.

## Updating

```bash
cd ~/codex-tandem && git pull && ./install.sh          # refresh configuration
codex update                                            # Codex CLI itself
```

`deepseek` picks up the new binary automatically because both commands resolve
the same `codex` executable.

## Uninstalling

```bash
./uninstall.sh                 # wrapper, ~/.codex-deepseek, PATH block
./uninstall.sh --dry-run       # see what would go first
./uninstall.sh --purge-key     # also delete the stored DeepSeek API key
./uninstall.sh --all           # also delete ~/.codex (Codex login included)
```

Your own files are left alone unless you ask for them: `~/.codex` and the API
key survive a plain `./uninstall.sh`.

## Troubleshooting

**`deepseek: command not found` after installing.** `~/.local/bin` is not on
your `PATH` in this shell yet: `source ~/.bashrc` (or open a new terminal).
The installer adds the block to `~/.bashrc` and `~/.zshrc` if those files exist.

**`Cannot find the "codex" binary on PATH`.** Install or reinstall the CLI:
`./install.sh` (or `curl -fsSL https://chatgpt.com/codex/install.sh | sh`).

**`DeepSeek API key not set`.** Run `deepseek` in an interactive terminal, or
export `DEEPSEEK_API_KEY`, or write the key yourself:

```bash
mkdir -p -m 700 ~/.config/deepseek
printf '%s\n' 'sk-...' > ~/.config/deepseek/api_key && chmod 600 ~/.config/deepseek/api_key
```

**Authentication errors on the DeepSeek side.** The wrapper forces API-key auth
for that home, so a ChatGPT login is neither needed nor used. Verify with
`deepseek --check` and, if in doubt, `rm ~/.codex-deepseek/auth.json`.

**The model is not offered / unknown model.** The catalog was not built against
a usable source model. Rebuild it:

```bash
python3 tools/build-deepseek-catalog.py \
  --template assets/catalog/deepseek-catalog.template.json \
  --output ~/.codex-deepseek/models-deepseek.json --base-model gpt-5.6-luna
```

**Sessions from one side show up on the other.** They should not: check with
`env | grep CODEX_HOME` inside each session, and make sure you are running
`deepseek` rather than a `codex` alias that clears the variable.

**Skills or plugins added later are invisible to `deepseek`.** Re-run
`./install.sh` (idempotent) or create the link yourself:
`ln -s ~/.codex/skills ~/.codex-deepseek/skills`.

**Something else.** `codex doctor` and `deepseek --check` cover almost
everything; `codex --help` lists the flags that `deepseek` also accepts.

## Repository layout

```
install.sh                                     installer
uninstall.sh                                   uninstaller
assets/AGENTS.md.example                       starter global instructions
assets/catalog/deepseek-catalog.template.json  DeepSeek model entries (no prompt text)
tools/build-deepseek-catalog.py                fills the catalog from your Codex install
```

## Verified behaviour

The installer is tested on Ubuntu by running it against a throwaway `HOME`:
configuration and links land where they should, re-running it changes nothing,
`--force` keeps backups, the wrapper passes its arguments through to Codex
unchanged, and the generated catalog loads in Codex (`codex debug models` shows
`deepseek-flash` and `deepseek-v4-pro`).

## License

MIT — see [LICENSE](LICENSE).
