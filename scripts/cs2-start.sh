#!/bin/bash
# Startet den CS2 Dedicated Server. Wird von cs2.service aufgerufen,
# nicht direkt von Hand.

set -euo pipefail

CONFIG="$(dirname "$0")/../config.env"
if [[ ! -f "$CONFIG" ]]; then
    echo "config.env fehlt. Vorlage: config.example.env" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

if [[ -z "${GSLT_TOKEN:-}" ]]; then
    echo "GSLT_TOKEN ist nicht gesetzt. Ohne Token ist der Server nicht oeffentlich sichtbar." >&2
    exit 1
fi

cd "$INSTALL/game/bin/linuxsteamrt64"

# exec statt Subshell: der Server wird PID 1 des Dienstes, damit systemd
# Signale (stop/restart) direkt an cs2 durchreicht und nicht an ein Wrapper-Bash.
exec ./cs2 -dedicated -usercon \
    +map "$START_MAP" \
    +game_type "$GAME_TYPE" \
    +game_mode "$GAME_MODE" \
    +sv_setsteamaccount "$GSLT_TOKEN"
