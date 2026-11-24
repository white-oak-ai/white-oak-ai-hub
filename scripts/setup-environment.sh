#!/usr/bin/env bash
# Environment configuration manager & setup wizard for white-oak-ai-hub.
# Resolves, validates, and initializes environment settings across skills.
#
# Usage:
#   ./scripts/setup-environment.sh --check            # Exit 0 if configured, 1 if missing/placeholders
#   ./scripts/setup-environment.sh --json             # Output resolved configuration as JSON
#   ./scripts/setup-environment.sh --detect           # Auto-detect git repo & tracker info as JSON
#   ./scripts/setup-environment.sh --init [--yes]     # Run first-run setup interview (or accept defaults)
#   ./scripts/setup-environment.sh --help             # Show usage
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# Configuration search priority:
# 1. Environment variable OVERRIDE_CONFIG
# 2. Local skill override (if run from a skill directory: references/environment.local.yaml)
# 3. Hub-wide local config: config/environment.local.yaml
# 4. Hub-wide committed config: config/environment.yaml
# 5. Hub-wide template: config/environment.example.yaml

resolve_config_path() {
  if [[ -n "${OVERRIDE_CONFIG:-}" && -f "$OVERRIDE_CONFIG" ]]; then
    echo "$OVERRIDE_CONFIG"
    return 0
  fi

  if [[ -f "./references/environment.local.yaml" ]]; then
    echo "$(pwd)/references/environment.local.yaml"
    return 0
  elif [[ -f "./references/environment.yaml" ]]; then
    echo "$(pwd)/references/environment.yaml"
    return 0
  fi

  if [[ -f "$root/config/environment.local.yaml" ]]; then
    echo "$root/config/environment.local.yaml"
    return 0
  elif [[ -f "$root/config/environment.yaml" ]]; then
    echo "$root/config/environment.yaml"
    return 0
  fi

  echo "$root/config/environment.example.yaml"
}

# Auto-detect local repository and tracking signals
detect_environment() {
  local origin_url branch tracker_script
  origin_url="$(git remote get-url origin 2>/dev/null || true)"
  branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")"
  tracker_script="$root/skills/quality-audit/scripts/detect-tracker.sh"

  python3 -c "
import sys, os, re, json, subprocess

url = '$origin_url'
branch = '$branch'
tracker_script = '$tracker_script'

host = ''
slug = ''
if url:
    m = re.search(r'^(?:[a-zA-Z0-9+_.-]+://)?(?:[^@/]+@)?([^/:]+)[:/](.+?)(?:\.git)?/?$', url)
    if m:
        host = m.group(1)
        slug = m.group(2)

tracker = 'github-issues'
connector = 'github'
if 'gitlab' in host:
    tracker = 'gitlab-issues'
    connector = 'gitlab'
elif 'azure' in host or 'visualstudio' in host:
    tracker = 'azure-boards'
    connector = 'azure-boards'
elif 'bitbucket' in host:
    tracker = 'bitbucket-issues'
    connector = 'bitbucket'

if os.path.exists(tracker_script) and os.access(tracker_script, os.X_OK):
    try:
        proc = subprocess.run([tracker_script], capture_output=True, text=True, timeout=5)
        if proc.returncode == 0:
            cands = json.loads(proc.stdout)
            if cands and len(cands) > 0:
                top = cands[0].get('tracker')
                if top:
                    tracker = top
                    if tracker == 'linear':
                        connector = 'linear'
                    elif tracker == 'jira':
                        connector = 'jira'
                    elif tracker == 'github-issues':
                        connector = 'github'
                    elif tracker == 'gitlab-issues':
                        connector = 'gitlab'
    except Exception:
        pass

project_key = slug if slug else 'my-org/my-project'
if tracker in ('linear', 'jira') and '/' in project_key:
    project_key = 'ENG'

data = {
    'slug': slug,
    'host': host,
    'default_branch': branch,
    'tracker': tracker,
    'connector': connector,
    'project_key': project_key,
    'local_path': '.'
}
print(json.dumps(data, indent=2))
"
}

# Parse YAML file into JSON using Python
parse_yaml_to_json() {
  local file="$1"
  python3 -c "
import sys, json
try:
    import yaml
    with open('$file', 'r') as f:
        data = yaml.safe_load(f) or {}
    print(json.dumps(data))
except Exception as e:
    # Minimal fallback parser if pyyaml fails
    sys.stderr.write(f'Warning parsing YAML with pyyaml: {e}\\n')
    sys.exit(1)
"
}

# Check if configuration is active and not just unconfigured placeholders
check_config() {
  local config_file
  config_file="$(resolve_config_path)"

  if [[ ! -f "$config_file" ]]; then
    echo "✗ No environment configuration file found." >&2
    return 1
  fi

  if [[ "$(basename "$config_file")" == "environment.example.yaml" ]]; then
    echo "✗ Only example template found at $config_file." >&2
    echo "  Run './scripts/setup-environment.sh --init' to generate config/environment.local.yaml." >&2
    return 1
  fi

  # Check if placeholder values still exist
  local is_placeholder
  is_placeholder="$(python3 -c "
import sys, json
try:
    import yaml
    with open('$config_file', 'r') as f:
        data = yaml.safe_load(f) or {}
    slug = data.get('default_repo', '')
    if 'example-org' in slug or 'example-repo' in slug or not slug:
        print('yes')
    else:
        print('no')
except Exception:
    print('yes')
")"

  if [[ "$is_placeholder" == "yes" ]]; then
    echo "✗ Environment config at $config_file contains placeholder values (e.g. example-org/example-repo)." >&2
    echo "  Run './scripts/setup-environment.sh --init' to configure with real values." >&2
    return 1
  fi

  echo "✓ Valid environment configuration active at $config_file"
  return 0
}

# Emit merged active config as JSON
get_json_config() {
  local example_file="$root/config/environment.example.yaml"
  local active_file
  active_file="$(resolve_config_path)"

  python3 -c "
import sys, json, os

def load_yaml(path):
    if not os.path.exists(path):
        return {}
    try:
        import yaml
        with open(path, 'r') as f:
            return yaml.safe_load(f) or {}
    except Exception:
        return {}

def merge(base, override):
    res = dict(base)
    for k, v in override.items():
        if isinstance(v, dict) and k in res and isinstance(res[k], dict):
            res[k] = merge(res[k], v)
        else:
            res[k] = v
    return res

example = load_yaml('$example_file')
active = load_yaml('$active_file')
merged = merge(example, active)
print(json.dumps(merged, indent=2))
"
}

# First-run setup interview
init_setup() {
  local auto_yes=0
  for arg in "$@"; do
    if [[ "$arg" == "--yes" || "$arg" == "-y" || "$arg" == "--auto" ]]; then
      auto_yes=1
    fi
  done

  local dest="$root/config/environment.local.yaml"
  echo "==> Configuring environment for white-oak-ai-hub"

  local detected_json
  detected_json="$(detect_environment)"

  local det_slug det_branch det_tracker det_connector det_key
  det_slug="$(python3 -c "import json; d=json.loads('''$detected_json'''); print(d.get('slug') or 'my-org/my-project')")"
  det_branch="$(python3 -c "import json; d=json.loads('''$detected_json'''); print(d.get('default_branch') or 'main')")"
  det_tracker="$(python3 -c "import json; d=json.loads('''$detected_json'''); print(d.get('tracker') or 'github-issues')")"
  det_connector="$(python3 -c "import json; d=json.loads('''$detected_json'''); print(d.get('connector') or 'github')")"
  det_key="$(python3 -c "import json; d=json.loads('''$detected_json'''); print(d.get('project_key') or '$det_slug')")"

  local repo_slug="$det_slug"
  local branch="$det_branch"
  local tracker="$det_tracker"
  local project_key="$det_key"
  local connector="$det_connector"
  local branch_pattern="feat/{issue_id}-{slug}"
  local build_cmd="npm run build"
  local test_cmd="npm test"

  if [[ $auto_yes -eq 0 ]]; then
    read -r -p "Target repository GitHub slug (owner/repo) [$det_slug]: " input_slug || true
    [[ -n "${input_slug:-}" ]] && repo_slug="$input_slug"

    read -r -p "Default git branch [$det_branch]: " input_branch || true
    [[ -n "${input_branch:-}" ]] && branch="$input_branch"

    read -r -p "Issue tracker (github-issues, linear, jira, gitlab-issues) [$det_tracker]: " input_tracker || true
    [[ -n "${input_tracker:-}" ]] && tracker="$input_tracker"

    case "$tracker" in
      linear) connector="linear"; [[ "$project_key" == "$det_slug" ]] && project_key="ENG" ;;
      jira) connector="jira"; [[ "$project_key" == "$det_slug" ]] && project_key="ENG" ;;
      github-issues) connector="github"; project_key="$repo_slug" ;;
      gitlab-issues) connector="gitlab"; project_key="$repo_slug" ;;
    esac

    read -r -p "Project / Team key in tracker [$project_key]: " input_key || true
    [[ -n "${input_key:-}" ]] && project_key="$input_key"

    read -r -p "Branch naming pattern [feat/{issue_id}-{slug}]: " input_bp || true
    [[ -n "${input_bp:-}" ]] && branch_pattern="$input_bp"
  fi

  cat > "$dest" <<EOF
# ==============================================================================
# White Oak AI Hub - Local Environment Configuration (git-ignored)
# ==============================================================================
# Generated by setup-environment.sh on $(date -u +"%Y-%m-%dT%H:%M:%SZ")

default_repo: "$repo_slug"

repos:
  - name: "main"
    slug: "$repo_slug"
    local_path: "."
    default_branch: "$branch"
    purpose: "Primary project codebase"
    build_cmd: "$build_cmd"
    test_cmd: "$test_cmd"
    issue_prefixes:
      - "${project_key%%/*}-"

ticketing:
  tracker: "$tracker"
  project_key: "$project_key"
  ticket_format: "#[0-9]+"
  connector: "$connector"
  workflow_states:
    in_progress_label: "in-progress"
    quality_label: "quality"
    skip_labels:
      - "blocked"
      - "on-hold"
      - "wontfix"
      - "duplicate"
      - "invalid"
      - "question"
      - "needs-design"
      - "needs-discussion"
      - "needs-info"
      - "needs-triage"
      - "epic"
      - "discussion"

conventions:
  branch_pattern: "$branch_pattern"
  commit_format: "conventional"
  pr_reviewers:
    - "senior-code-reviewer"
  require_ci: true
EOF

  echo "✓ Successfully wrote local environment configuration to $dest"
}

# Main routing
action="${1:---help}"
case "$action" in
  --check)
    check_config
    ;;
  --detect)
    detect_environment
    ;;
  --json)
    get_json_config
    ;;
  --init)
    shift || true
    init_setup "$@"
    ;;
  --help|-h)
    sed -n '2,10p' "$0" | sed 's/^#//'
    ;;
  *)
    echo "Unknown option: $action" >&2
    echo "Run '$0 --help' for usage." >&2
    exit 1
    ;;
esac
