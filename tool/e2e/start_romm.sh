#!/usr/bin/env bash
# Starts a throwaway RomM in Docker for Gargosy's end-to-end tests (#242):
# a test library (make_roms.py), an admin and a player (viewer) user, and a
# first scan. Prints the ROMM_E2E_* variables the tests read, and adds them
# to $GITHUB_ENV on CI.
#
#   ROMM_VERSION=5.4.1 tool/e2e/start_romm.sh     # RomM's image tag (latest: newest)
#   tool/e2e/start_romm.sh down                   # stop it and throw it away
#
# Needs Docker with Compose, curl, python3 and openssl (a Linux machine or WSL).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
export ROMM_VERSION="${ROMM_VERSION:-5.4.1}"
export E2E_DIR="${E2E_DIR:-$here/.work}"
export ROMM_AUTH_SECRET_KEY="${ROMM_AUTH_SECRET_KEY:-$(openssl rand -hex 32)}"
compose=(docker compose -p gargosy-e2e -f "$here/docker-compose.yml")

if [[ "${1:-}" == "down" ]]; then
  "${compose[@]}" down -v
  rm -rf "$E2E_DIR"
  exit 0
fi

url="http://localhost:8080"
admin_user="gargosy-admin"
admin_pass="gargosy-e2e-admin-1"
player_user="gargosy-player"
player_pass="gargosy-e2e-player-1"

rm -rf "$E2E_DIR"
mkdir -p "$E2E_DIR/library/roms" "$E2E_DIR/assets"
python3 "$here/make_roms.py" "$E2E_DIR/library/roms"
# RomM's container runs as its own user: let it write uploads and assets.
chmod -R a+rwX "$E2E_DIR"

echo "Starting RomM $ROMM_VERSION"
"${compose[@]}" pull --quiet
"${compose[@]}" up -d

for i in $(seq 1 90); do
  if curl -fsS "$url/api/heartbeat" > /dev/null 2>&1; then break; fi
  if [[ $i == 90 ]]; then
    echo "RomM didn't answer within 6 minutes" >&2
    "${compose[@]}" logs romm | tail -100 >&2
    exit 1
  fi
  sleep 4
done
echo "RomM answers: $(curl -fsS "$url/api/heartbeat" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("SYSTEM", {}).get("VERSION", "?"))')"

# The first user needs no login, but RomM's CSRF check wants its cookie back.
jar="$E2E_DIR/cookies.txt"
curl -fsS -c "$jar" "$url/api/heartbeat" > /dev/null
csrf="$(awk '$6 == "romm_csrftoken" { print $7 }' "$jar")"
curl -fsS -b "$jar" -H "x-csrftoken: $csrf" -H 'Content-Type: application/json' \
  -X POST "$url/api/users" \
  -d "{\"username\":\"$admin_user\",\"email\":\"admin@gargosy.invalid\",\"password\":\"$admin_pass\",\"role\":\"admin\"}" > /dev/null
# Basic auth needs no CSRF token.
curl -fsS -u "$admin_user:$admin_pass" -H 'Content-Type: application/json' \
  -X POST "$url/api/users" \
  -d "{\"username\":\"$player_user\",\"email\":\"player@gargosy.invalid\",\"password\":\"$player_pass\",\"role\":\"viewer\"}" > /dev/null
echo "Users $admin_user (admin) and $player_user (viewer) made"

task="$(curl -fsS -u "$admin_user:$admin_pass" -H 'Content-Type: application/json' \
  -X POST "$url/api/tasks/scan" -d '{"type":"quick"}' \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["task_id"])')"
for i in $(seq 1 90); do
  status="$(curl -fsS -u "$admin_user:$admin_pass" "$url/api/tasks/$task" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))')"
  case "$status" in
    finished) break ;;
    failed|stopped|canceled)
      echo "The first scan $status" >&2
      "${compose[@]}" logs romm | tail -100 >&2
      exit 1 ;;
  esac
  if [[ $i == 90 ]]; then echo "The first scan didn't end within 3 minutes ($status)" >&2; exit 1; fi
  sleep 2
done
games="$(curl -fsS -u "$admin_user:$admin_pass" "$url/api/roms?limit=1" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("total", 0))')"
echo "Scanned: $games games"
if [[ "$games" -lt 3 ]]; then
  echo "The scan found $games games, not the test library's 3" >&2
  "${compose[@]}" logs romm | tail -100 >&2
  exit 1
fi

vars=(
  "ROMM_E2E_URL=$url"
  "ROMM_E2E_USER=$player_user"
  "ROMM_E2E_PASSWORD=$player_pass"
  "ROMM_E2E_ADMIN_USER=$admin_user"
  "ROMM_E2E_ADMIN_PASSWORD=$admin_pass"
  "ROMM_E2E_PLATFORM=gb"
)
printf '%s\n' "${vars[@]}"
if [[ -n "${GITHUB_ENV:-}" ]]; then printf '%s\n' "${vars[@]}" >> "$GITHUB_ENV"; fi
