#!/usr/bin/env bash
# PreToolUse(Bash) if Bash(git commit*): giu luat CLAUDE.md truoc khi commit.
#   #3 anh ship la .webp (PNG chi duoc o app/assets/icon/)   #4 commit message KHONG dau
set -uo pipefail
cmd=$(jq -r '.tool_input.command // empty')
root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
deny() {
  jq -nc --arg m "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$m}}'
  exit 0
}
staged=$(git -C "$root" diff --cached --name-only --diff-filter=AM 2>/dev/null)

png=$(printf '%s\n' "$staged" | grep -E '^app/assets/.*\.png$' | grep -vE '^app/assets/icon/' || true)
[[ -n "$png" ]] && deny "CLAUDE.md luat #3: anh ship phai la .webp (PNG chi o app/assets/icon/). Dang stage: $(printf '%s' "$png" | tr '\n' ' ') -> doi sang webp, git restore --staged file PNG."

msg=$(printf '%s' "$cmd" | grep -oP "(?<=-m )['\"].*?['\"]" | head -1 || true)
if [[ -n "$msg" ]] && printf '%s' "$msg" | LC_ALL=C.UTF-8 grep -qP '[\x{00C0}-\x{024F}\x{1E00}-\x{1EFF}]'; then
  deny "CLAUDE.md luat #4: commit message phai tieng Viet KHONG dau. Message dang co dau: $msg"
fi
exit 0
