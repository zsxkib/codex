<p align="center">
  <img src="https://github.com/openai/codex/blob/main/.github/codex-cli-splash.png" alt="Codex CLI splash" width="80%" />
</p>

# Codex CLI — with MCP Session Rehydration

**Fork by [Sakib Ahamed](https://github.com/zsxkib)** | Based on [openai/codex](https://github.com/openai/codex)

> When the Codex MCP server restarts, all in-memory sessions are lost. This fork fixes that. Sessions are automatically rehydrated from disk, so you never lose a conversation.

---

## What this fork adds

Codex exposes itself as an [MCP server](https://modelcontextprotocol.io/) so other AI agents (like Claude) can spawn and manage Codex sessions programmatically via `codex` and `codex-reply` tools.

**The problem:** The upstream MCP server keeps sessions in memory only. If the server restarts — which happens frequently during development, editor reloads, or system events — every active session is gone. The calling agent gets back `"Session not found"` and has to start over from scratch, losing all prior context and work.

**The fix:** This fork adds **automatic session rehydration from disk**. When `codex-reply` is called with a thread ID that isn't in memory, the server:

1. Locates the JSONL rollout file on disk (Codex already persists these)
2. Reads the session metadata to recover the original working directory
3. Rebuilds the full conversation history from the rollout transcript
4. Resumes the session transparently — the calling agent never knows there was a restart

This makes Codex MCP sessions **durable across server restarts**, which is critical for any production multi-agent setup.

### Changes

Two files, one commit — surgical and minimal:

| File | What changed |
|------|-------------|
| `codex-rs/mcp-server/src/message_processor.rs` | Added `try_rehydrate_from_disk()` method and fallback logic in `handle_tool_call_codex_session_reply` |
| `codex-rs/core/src/thread_manager.rs` | Exposed `auth_manager()` accessor needed for rehydration |

**+76 lines, -10 lines.** No new dependencies. No breaking changes. Stays current with upstream via regular rebases.

---

## Quick start

### Use as an MCP server (for Claude Code, etc.)

Build the patched MCP server binary:

```shell
cd codex-rs
cargo build --release -p codex-mcp-server
```

Then point your MCP client config at the binary:

```json
{
  "mcpServers": {
    "codex": {
      "command": "/path/to/codex-mcp-server",
      "args": ["--model", "gpt-5.3-codex"]
    }
  }
}
```

### Stay synced with upstream

A helper script keeps this fork up to date:

```shell
./update-patched.sh
```

This fetches the latest from `openai/codex`, rebases the patch on top, rebuilds, and pushes.

---

## How it works

```
codex-reply(thread_id="abc-123", prompt="...")
        │
        ▼
┌─ In memory? ──── YES ──► Continue session normally
│
NO
│
▼
┌─ Find JSONL rollout on disk
│   ~/.codex/sessions/**/abc-123.jsonl
│
├─ Read session metadata (cwd, model, config)
│
├─ Replay conversation history
│
└─ Resume as new thread ──► Continue session normally
```

The calling agent doesn't need to handle any of this. It just keeps using `codex-reply` with the same thread ID, and sessions survive restarts automatically.

---

## Upstream

This is a fork of [openai/codex](https://github.com/openai/codex) — the official Codex CLI from OpenAI. All upstream features, docs, and installation methods apply. See the [upstream README](https://github.com/openai/codex#readme) for full documentation.

**Branch:** `sakib/mcp-session-rehydration` (default) — always 1 commit ahead of `openai/codex:main`

---

<sub>Licensed under [Apache-2.0](LICENSE), same as upstream.</sub>
