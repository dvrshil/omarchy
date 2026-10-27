#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

registry="$ROOT/default/agents/registry"

offered=$(grep -oE 'agent="[a-z-]+"' "$ROOT/bin/omarchy-default-agent" | sed -E 's/agent="([a-z-]+)"/\1/' | sort -u)
listed=$(grep -vE '^\s*(#|$)' "$registry" | awk '{print $1}' | sort -u)

missing=$(comm -23 <(echo "$offered") <(echo "$listed"))
[[ -z $missing ]] || fail "every agent omarchy-default-agent offers has a registry line" "missing: $missing"
extra=$(comm -13 <(echo "$offered") <(echo "$listed"))
[[ -z $extra ]] || fail "every registry line names an agent omarchy-default-agent offers" "unknown: $extra"
pass "the registry and omarchy-default-agent name the same agents"

while read -r agent variable home reads_shared rest; do
  [[ -z $agent || $agent == \#* ]] && continue
  [[ -z $rest ]] || fail "a registry line has four columns" "$agent: $rest"
  [[ $variable == "-" || $variable =~ ^[A-Z][A-Z0-9_]*$ ]] || fail "the home variable is a variable name or -" "$agent: $variable"
  [[ $home == "-" || $home == "~/"* ]] || fail "the home is under ~ or -" "$agent: $home"
  [[ $reads_shared == "yes" || $reads_shared == "no" ]] || fail "reads-agents-skills is yes or no" "$agent: $reads_shared"
done <"$registry"
pass "every registry line is well formed"
