#!/usr/bin/env bash
set -uo pipefail
export LC_ALL=C
PASS=0
FAIL=0
check() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        printf '[OK] %s\n' "$description"
        PASS=$((PASS + 1))
    else
        printf '[FAIL] %s (expected: %s; actual: %s)\n' "$description" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}
printf 'Configuration audit: %s, %s\n' "$(hostname -f)" "$(date '+%F %R')"
echo '[1] SSH'
ssh_config=$(sudo sshd -T) || exit 1
ssh_value() { awk -v key="$1" '$1 == key {print $2}' <<< "$ssh_config"; }
check 'Root login disabled' no "$(ssh_value permitrootlogin)"
check 'Password authentication disabled' no "$(ssh_value passwordauthentication)"
ports=$(ssh_value port)
nonstandard=no
if [[ -n "$ports" ]] && ! grep -qx 22 <<< "$ports"; then nonstandard=yes; fi
check 'SSH uses a nonstandard port' yes "$nonstandard"
check 'MaxAuthTries' 3 "$(ssh_value maxauthtries)"
echo '[2] Firewall'
firewall=$(sudo ufw status verbose) || exit 1
check 'UFW active' active "$(awk '/^Status:/ {print $2}' <<< "$firewall")"
check 'Incoming denied by default' deny "$(sed -n 's/^Default: \([^ ]*\) (incoming).*/\1/p' <<< "$firewall")"
echo '[3] Accounts'
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd
printf 'Passed: %s; failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
