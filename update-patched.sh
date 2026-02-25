#!/bin/bash
# Sync fork with upstream, push, and download the CI-built binary.
#
# Usage: ./update-patched.sh [--local]
#
# What this does:
# 1. Fetches latest from upstream (openai/codex)
# 2. Fast-forwards main
# 3. Rebases the patched branch on top
# 4. Pushes both branches to the fork (triggers CI build)
# 5. Downloads the CI-built codex-mcp-server binary
#
# Use --local to build locally instead of waiting for CI.

set -euo pipefail

cd "$(dirname "$0")"

LOCAL_BUILD=false
if [[ "${1:-}" == "--local" ]]; then
    LOCAL_BUILD=true
fi

echo "==> Fetching upstream..."
git fetch upstream main

echo "==> Updating main..."
git checkout main
git reset --hard upstream/main

echo "==> Rebasing sakib/mcp-session-rehydration branch..."
git checkout sakib/mcp-session-rehydration
if ! git rebase main; then
    echo ""
    echo "!!! Rebase conflict. Fix it manually, then run:"
    echo "    cd $(pwd)"
    echo "    git rebase --continue"
    echo "    ./update-patched.sh --local"
    exit 1
fi

echo "==> Pushing to fork..."
git push origin main --force
git push origin sakib/mcp-session-rehydration --force

if $LOCAL_BUILD; then
    echo "==> Building locally (this will take ~10-15 min)..."
    source "$HOME/.cargo/env"
    cd codex-rs
    cargo build --release -p codex-mcp-server
    cd ..
    cp codex-rs/target/release/codex-mcp-server /opt/homebrew/bin/codex-mcp-server
else
    echo "==> Waiting for CI build..."
    echo "    (push triggered GitHub Actions — waiting for artifact)"

    # Wait for the workflow run to start
    sleep 10

    # Poll for the latest run on our branch
    for i in $(seq 1 60); do
        RUN_ID=$(gh run list --workflow=build-mcp-server.yml --branch=sakib/mcp-session-rehydration --limit=1 --json databaseId,status --jq '.[0] | select(.status != "completed") | .databaseId' 2>/dev/null || true)
        if [[ -n "$RUN_ID" ]]; then
            echo "    Run $RUN_ID in progress, waiting for completion..."
            gh run watch "$RUN_ID" --exit-status && break
            echo "    CI failed! Use --local to build locally."
            exit 1
        fi

        # Check if the latest run already completed
        COMPLETED_RUN=$(gh run list --workflow=build-mcp-server.yml --branch=sakib/mcp-session-rehydration --limit=1 --json databaseId,status,headSha --jq ".[0] | select(.status == \"completed\") | select(.headSha == \"$(git rev-parse HEAD)\") | .databaseId" 2>/dev/null || true)
        if [[ -n "$COMPLETED_RUN" ]]; then
            RUN_ID="$COMPLETED_RUN"
            echo "    Run $RUN_ID already completed."
            break
        fi

        echo "    Waiting for run to appear... ($i/60)"
        sleep 5
    done

    if [[ -z "${RUN_ID:-}" ]]; then
        echo "    Timed out waiting for CI. Use --local to build locally."
        exit 1
    fi

    echo "==> Downloading binary..."
    TMPDIR=$(mktemp -d)
    gh run download "$RUN_ID" -n codex-mcp-server-aarch64-apple-darwin -D "$TMPDIR"
    chmod +x "$TMPDIR/codex-mcp-server"
    cp "$TMPDIR/codex-mcp-server" /opt/homebrew/bin/codex-mcp-server
    rm -rf "$TMPDIR"
fi

echo ""
echo "Done."
echo "  codex (TUI):       $(codex --version 2>/dev/null || echo 'brew install --cask codex')"
echo "  codex-mcp-server:  /opt/homebrew/bin/codex-mcp-server"
