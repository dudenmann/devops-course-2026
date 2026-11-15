#!/usr/bin/env bash
set -euo pipefail
REMOTE="${DEPLOY_REMOTE:-devops}"
REMOTE_DIR="${DEPLOY_REMOTE_DIR:-/var/www/devops-site}"
SITE_URL="${DEPLOY_URL:-https://devops.local}"
CA_CERT="${DEPLOY_CA_CERT:-${HOME}/devops.crt}"
dry_run=false
if [[ $# -eq 1 && "$1" == --dry-run ]]; then
    dry_run=true
elif [[ $# -ne 0 ]]; then
    echo 'Usage: deploy.sh [--dry-run]' >&2
    exit 1
fi
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(git -C "$script_dir" rev-parse --show-toplevel)
if [[ ! -f "$root/site/index.html" ]]; then
    echo 'Missing site/index.html; deployment cancelled.' >&2
    exit 1
fi
if [[ -n "$(git -C "$root" status --porcelain --untracked-files=all)" ]]; then
    echo 'Commit all changes before deployment.' >&2
    exit 1
fi
options=(-avz --delete --chmod=D755,F644 -e 'ssh -o BatchMode=yes -o ConnectTimeout=5')
if "$dry_run"; then options+=(--dry-run); fi
if ! rsync "${options[@]}" "$root/site/" "$REMOTE:$REMOTE_DIR/"; then
    echo 'File transfer failed.' >&2
    exit 1
fi
if "$dry_run"; then exit 0; fi
if ! curl --fail --silent --show-error --connect-timeout 5 --max-time 20 \
    --cacert "$CA_CERT" "$SITE_URL" > /dev/null; then
    echo 'HTTPS availability check failed.' >&2
    exit 1
fi
printf 'Deployed commit %s\n' "$(git -C "$root" rev-parse --short HEAD)"
