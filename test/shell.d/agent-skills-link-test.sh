#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

home="$test_tmp/home"
mock_bin="$test_tmp/bin"
mkdir -p "$home" "$mock_bin"

# Claude Code, Hermes and Codex are installed: a plain script on PATH, which
# is how an install of the user's own looks. Nothing else is, and the mise
# shims of the machine running the test stay off PATH.
for command in claude hermes codex; do
  printf '#!/bin/bash\n' >"$mock_bin/$command"
done
printf '#!/bin/bash\nexit 1\n' >"$mock_bin/mise"
chmod +x "$mock_bin"/*

link() {
  HOME="$home" PATH="$mock_bin:/usr/bin:/bin" OMARCHY_PATH="$ROOT" \
    bash "$ROOT/bin/omarchy-agent-skills-link" "$@"
}

links_to_shipped() {
  [[ -L $1 && $(readlink "$1") == "$ROOT/default/agents/skills/${1##*/}" ]]
}

skills=()
for skill in "$ROOT"/default/agents/skills/*/; do
  skill=${skill%/}
  skills+=("${skill##*/}")
done
(( ${#skills[@]} > 0 )) || fail "the checkout ships at least one skill"

# What an earlier Omarchy left behind: links in every folder it used to write,
# a user's own skill under a shipped name, and a link that is not Omarchy's.
mkdir -p "$home/.codex/skills/.system" "$home/.pi/agent/skills" "$home/.hermes/profiles/james" "$home/.claude/skills/omarchy"
printf 'mine\n' >"$home/.claude/skills/omarchy/SKILL.md"
ln -s "/usr/share/omarchy/default/agents/skills/omarchy" "$home/.codex/skills/omarchy"
ln -s "/usr/share/omarchy/default/agents/skills/omarchy" "$home/.pi/agent/skills/omarchy"
ln -s "$test_tmp/elsewhere" "$home/.codex/skills/theirs"

link || fail "omarchy-agent-skills-link finishes"

for skill in "${skills[@]}"; do
  links_to_shipped "$home/.agents/skills/$skill" || fail "every shipped skill is linked into ~/.agents/skills ($skill)"
  links_to_shipped "$home/.hermes/skills/$skill" || fail "Hermes gets its own links ($skill)"
  links_to_shipped "$home/.hermes/profiles/james/skills/$skill" || fail "an existing Hermes profile gets links ($skill)"
done
pass "shipped skills are linked into ~/.agents/skills and into the folders of agents that do not read it"

[[ -d $home/.claude/skills/omarchy && ! -L $home/.claude/skills/omarchy && $(<"$home/.claude/skills/omarchy/SKILL.md") == "mine" ]] ||
  fail "a user's own skill under a shipped name is left alone"
for skill in "${skills[@]}"; do
  [[ $skill == "omarchy" ]] && continue
  links_to_shipped "$home/.claude/skills/$skill" || fail "Claude Code still gets the other skills ($skill)"
done
pass "a user's own skill under a shipped name is kept and the rest are linked beside it"

[[ ! -e $home/.codex/skills/omarchy ]] || fail "an old Omarchy link is removed from an agent that reads ~/.agents/skills"
[[ -L $home/.codex/skills/theirs ]] || fail "a link that is not Omarchy's is kept"
[[ -d $home/.codex/skills/.system ]] || fail "a folder with other content stays"
[[ ! -e $home/.pi/agent/skills ]] || fail "a folder Omarchy emptied is removed"
pass "links from earlier Omarchy versions are removed only where they are no longer wanted"

[[ ! -e $home/.gemini && ! -e $home/.kiro && ! -e $home/.config/opencode ]] ||
  fail "an agent that is not installed gets no folder"
pass "agents that are not installed get no folders"

before=$(cd "$home" && find . -printf '%p %y %l\n' | sort)
link || fail "omarchy-agent-skills-link finishes a second time"
after=$(cd "$home" && find . -printf '%p %y %l\n' | sort)
[[ $before == "$after" ]] || fail "a second run changes nothing" "$(diff <(echo "$before") <(echo "$after") || true)"
pass "a second run changes nothing"

# The selected default agent is linked even before mise reports it installed.
mkdir -p "$home/.config/omarchy/defaults"
printf 'agy\n' >"$home/.config/omarchy/defaults/agent"
link agy || fail "omarchy-agent-skills-link finishes for one agent"
for skill in "${skills[@]}"; do
  links_to_shipped "$home/.gemini/config/skills/$skill" || fail "the default agent gets its own links ($skill)"
done
[[ ! -e $home/.kiro ]] || fail "naming one agent leaves the others untouched"
pass "the selected default agent gets its own links, and naming an agent touches only that agent"

# A home moved by its variable is the one that gets the links.
rm -rf "$home/.claude"
CLAUDE_CONFIG_DIR="$test_tmp/claude-elsewhere" link claude || fail "omarchy-agent-skills-link honours CLAUDE_CONFIG_DIR"
for skill in "${skills[@]}"; do
  links_to_shipped "$test_tmp/claude-elsewhere/skills/$skill" || fail "a moved home gets the links ($skill)"
done
[[ ! -e $home/.claude ]] || fail "the default home is left alone when the variable moves it"
pass "a home moved by its environment variable gets the links instead of the default one"

# Some people make an agent's folder a link to ~/.agents/skills by hand. The
# cleanup of a shared-folder agent must not reach the shared links through it,
# and the link itself stays.
home="$test_tmp/home2"
mkdir -p "$home/.codex" "$home/.agents/skills"
ln -s "$home/.agents/skills" "$home/.codex/skills"
link || fail "omarchy-agent-skills-link finishes with a folder that links to ~/.agents/skills"
for skill in "${skills[@]}"; do
  links_to_shipped "$home/.agents/skills/$skill" || fail "the shared links survive a folder that links to them ($skill)"
done
[[ -L $home/.codex/skills && $(readlink "$home/.codex/skills") == "$home/.agents/skills" ]] ||
  fail "the user's folder link is kept"
pass "a folder that links to ~/.agents/skills keeps the shared links and the link itself"
