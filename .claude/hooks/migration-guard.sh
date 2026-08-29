#!/usr/bin/env bash
# PreToolUse(Write|Edit): chan sua migration DA CO trong git HEAD.
# AGENTS.md luat #3: muon doi -> viet migration MOI de len.
set -uo pipefail
f=$(jq -r '.tool_input.file_path // empty')
[[ "$f" == *supabase/migrations/*.sql ]] || exit 0
f=$(realpath -q "$f") || exit 0
root=$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null) || exit 0
rel=${f#"$root"/}
git -C "$root" cat-file -e "HEAD:$rel" 2>/dev/null || exit 0
jq -nc --arg r "$rel" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:("AGENTS.md luat #3: \($r) da nam trong git HEAD (coi nhu da push). KHONG sua migration cu. Tao file supabase/migrations/0xx_*.sql moi (so tiep theo) de de len bang create or replace.")}}'
exit 0
