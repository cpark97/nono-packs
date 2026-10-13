# OpenCode v2 nono pack

`opencode` is the `nono` pack for OpenCode 2.x. Use the separate `nolabs-ai/opencode-v1` pack for OpenCode 1.x.

It installs a sandbox profile, a TypeScript plugin, and a skill that make opencode behave correctly when running inside a `nono` security sandbox — including credential injection, detach/attach session support, and denial diagnostics.

## What It Does

The pack provides:

- a sandbox profile (`policy.json`) granting the correct filesystem and network access, with credential injection routes for OpenAI, Anthropic, Gemini, GitHub, and GitLab
- a `session_hooks.before` hook (`bin/ensure-dirs.sh`) that creates opencode's state directories on the host before the sandbox is applied, so first-run doesn't fail when a directory the profile grants access to doesn't exist yet
- a TypeScript plugin (`plugin/nono-sandbox.ts`) that injects nono sandbox context at session start, detects denial signatures in tool results, appends capability context and Option A/B remediation guidance, surfaces the network egress allowlist, and registers a `nono_status` tool
- a `nono-sandbox` skill that teaches the correct diagnostic flow for filesystem and network-egress denials, credential route setup, and detach/attach usage

The plugin targets the OpenCode v2 plugin API. Its `setup()` entrypoint registers the session `context` hook, a `nono_status` tool, and the `tool.execute.after` hook.

## OpenCode v2 Sandbox Isolation

OpenCode v2 normally connects clients to a shared background server. That server owns tool execution, plugins, permissions, and network requests, so sandboxing only the client can allow work to escape the active nono session.

For a fully contained interactive session, launch OpenCode with `--standalone`:

```bash
nono run --profile nolabs-ai/opencode -- opencode --standalone
```

This starts a private OpenCode server inside the same nono sandbox as the client. The pack deliberately does not append `--standalone` automatically because the flag is incompatible with workflows and administrative subcommands such as `serve`, `auth`, and `acp`.

If you omit `--standalone`, OpenCode may connect to an already-running server outside the sandbox. In that configuration, the profile constrains the client process but cannot guarantee that model tools, plugins, or network requests executed by the external server are contained.

The profile sets two OpenCode compatibility variables. nono grants the active workdir, not its parent directories or the user's whole home. OpenCode v2 probes those broader locations during project and instruction discovery and treats the expected sandbox denials as fatal initialization errors. `OPENCODE_DISABLE_PROJECT_CONFIG=1` prevents the parent-directory discovery walk, while `OPENCODE_TEST_HOME=$WORKDIR` keeps core instruction initialization rooted in the granted workdir.

These are compatibility workarounds, not security controls; nono remains the enforcement boundary. Granting a broad parent such as `~/Work` or all of `$HOME` instead would unnecessarily expose sibling projects and unrelated user data. The workaround disables project configuration, instructions, plugins, and other project-discovered OpenCode components. Global OpenCode configuration and the installed nono plugin remain available.

This isolation mode has deliberate compatibility tradeoffs:

- global OpenCode configuration and the installed nono plugin remain available
- project `opencode.json`/`opencode.jsonc`, `AGENTS.md`, plugins, and other project-discovered components are disabled by the startup workaround
- OpenCode's logical home is set to the active workdir for instruction initialization, while its XDG config, state, data, and cache paths remain unchanged
- `~/.opencode` is read-only because it contains an executable directory on `PATH`; run OpenCode upgrades outside the sandbox

OpenCode and its runtime may probe parent or system directories during startup. A successful session can therefore end with denied-path notices for paths such as `$HOME`, `$HOME/.config`, `$NONO_CONFIG`, or `/System`. Do not grant those broad paths merely to silence the notices; add a narrower grant only when a required operation actually fails.

## Behavior

When opencode is running inside a `nono` sandbox the installed plugin:

- no-ops if `NONO_CAP_FILE` is not set (not inside a nono session)
- injects sandbox context into the system prompt at session start so the model knows the rules before its first tool call
- surfaces the session ID (for `nono attach`) when running detached
- detects sandbox-denial signatures in tool results (`Operation not permitted`, `EACCES`, `EPERM`, `landlock`)
- appends the active capability set, credential route summary, and remediation instructions so the model always receives correct guidance
- reports the network egress allowlist (reachable hosts) with state-aware guidance for blocked, allowlisted, and unrestricted networking
- steers the model toward the two valid remediations: `--allow` restart or a persistent profile draft

This prevents common bad guidance such as retrying the same action, suggesting `chmod`, attempting network workarounds, or treating the failure as a macOS TCC issue.

## First-Run Directory Bootstrap

Landlock and Seatbelt can only grant a filesystem rule for a path that already exists. On a first run, a few state/cache/etc. directories don't exist yet, so the sandboxed opencode process fails immediately.

`policy.json` wires `bin/ensure-dirs.sh` as a `session_hooks.before` hook, which nono runs on the host before applying the sandbox to `mkdir -p` them first. The hook resolves through `$PACK_DIR` to the installed pack directory.

## Credential Injection

nono intercepts outbound HTTPS and injects API keys from its keychain — opencode never sees the raw secret. Routes are defined in the profile but **disabled by default**.

To enable a route, create an extending profile:

```json
{
  "extends": "opencode",
  "meta": { "name": "opencode-with-anthropic", "version": "1.0.0" },
  "network": { "credentials": ["anthropic"] }
}
```

Built-in route names: `openai`, `anthropic`, `gemini`, `github`, `gitlab`.

Store the corresponding secret in the nono keychain under the env-var-shaped account name (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, etc.).

## Detach and Attach

Run opencode in a detached session that survives terminal disconnects:

```bash
nono run --profile nolabs-ai/opencode --detach -- opencode --standalone
```

Reattach from any terminal:

```bash
nono attach <session-id>
```

The `nono_status` tool (registered by the plugin) shows the active session ID and capability set.

## Install

```bash
nono pull nolabs-ai/opencode
```

Or let nono prompt you on first use:

```bash
nono run --profile nolabs-ai/opencode -- opencode --standalone
```

## Activation

After pulling, opencode reads the plugin from `$XDG_CONFIG_HOME/opencode/plugins/nono-sandbox.ts` and the skill from `$XDG_CONFIG_HOME/opencode/skills/nono-sandbox/SKILL.md`. Both are symlinked from the pack store and update automatically on `nono pull`. If `XDG_CONFIG_HOME` is unset, the default `~/.config` applies.

OpenCode 2.x scans the `plugins/` directory (it also accepts the `plugin/` name). The plugin is a self-contained TypeScript file with no external package dependencies, so it loads as a raw file.

## Compatibility

This pack supports OpenCode 2.x only. Use `--standalone` for interactive agent sessions that require the OpenCode server and client to remain inside the same nono sandbox. The pack documents but does not enforce this flag.

For OpenCode 1.x, use `nolabs-ai/opencode-v1`. Both packs install into OpenCode's standard plugin and skill locations, so remove the currently installed pack before switching between them.

## Removing

```bash
nono remove nolabs-ai/opencode
```

## Package Metadata

- Name: `opencode`
- Version: `0.4.0`
- OpenCode: `2.x`
- Pack type: `agent`
- Platforms: `macos`, `linux`
- License: `Apache-2.0`
