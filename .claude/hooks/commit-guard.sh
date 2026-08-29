#!/usr/bin/env bash
# PreToolUse(Bash) if Bash(git commit*): giu luat AGENTS.md truoc khi commit.
#   #4 asset PNG khong commit   #5 commit message tieng Viet KHONG dau
#   #3 migration cu khong sua
set -uo pipefail
cmd=$(jq -r '.tool_input.command // empty')
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
deny() {
  jq -nc --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'
  exit 0
}
staged=$(git -C "$root" diff --cached --name-only 2>/dev/null)

png=$(printf '%s\n' "$staged" | grep -E '^app/assets/.*\.png$' || true)
[[ -n "$png" ]] && deny "AGENTS.md luat #4: chi .webp duoc ship. Dang stage PNG goc: $(printf '%s' "$png" | tr '\n' ' ') -> git restore --staged cac file nay."

for m in $(printf '%s\n' "$staged" | grep -E '^supabase/migrations/.*\.sql$' || true); do
  git -C "$root" cat-file -e "HEAD~1:$m" 2>/dev/null && deny "AGENTS.md luat #3: $m da co tu truoc, khong duoc sua migration cu. Viet migration moi de len."
done

msg=$(printf '%s' "$cmd" | grep -oP "(?<=-m )['\"].*?['\"]" | head -1 || true)
if [[ -n "$msg" ]] && printf '%s' "$msg" | grep -qP '[\x{00C0}-\x{024F}\x{1E00}-\x{1EFF}]'; then
  deny "AGENTS.md luat #5: commit message phai tieng Viet KHONG dau. Message dang co dau: $msg"
fi
exit 0
