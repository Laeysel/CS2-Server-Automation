#!/bin/bash
# Taeglicher Wartungslauf: Server stoppen, Update pruefen, Integritaet der
# Plugin-Kette pruefen, Server wieder starten.
#
# Laeuft per Cron um 06:00 Uhr, wenn erfahrungsgemaess niemand spielt.

set -uo pipefail

CONFIG="$(dirname "$0")/../config.env"
if [[ ! -f "$CONFIG" ]]; then
    echo "config.env fehlt. Vorlage: config.example.env" >&2
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG"

STEAMINF="$INSTALL/game/csgo/steam.inf"
GAMEINFO="$INSTALL/game/csgo/gameinfo.gi"
GAMEINFO_BACKUP="$INSTALL/game/csgo/gameinfo.gi.bak"
METAMOD_LINE="			Game	csgo/addons/metamod"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

# ---------------------------------------------------------------------------
# Logrotation: ohne das waechst die Datei unbegrenzt, weil das Skript
# taeglich laeuft und steamcmd sehr gespraechig ist.
# ---------------------------------------------------------------------------
rotate_log() {
    [[ "${LOG_MAX_BYTES:-0}" -eq 0 ]] && return 0
    [[ -f "$LOG" ]] || return 0
    local size
    size=$(stat -c%s "$LOG")
    if (( size > LOG_MAX_BYTES )); then
        mv "$LOG" "$LOG.1"
        log "Log rotiert (vorherige Datei: $LOG.1)"
    fi
}

# ---------------------------------------------------------------------------
# Sicherheitsnetz: egal wo das Skript abbricht, der Server wird wieder
# gestartet. Ohne diesen Trap bleibt der Server bei einem Fehler in steamcmd
# dauerhaft unten, und das faellt erst auf, wenn abends jemand spielen will.
# ---------------------------------------------------------------------------
server_running=1
cleanup() {
    if [[ "$server_running" -eq 0 ]]; then
        log "Abbruch erkannt. Starte Server als Sicherheitsnetz wieder..."
        sudo systemctl start cs2.service
    fi
}
trap cleanup EXIT

read_build() {
    grep -m1 "PatchVersion=" "$STEAMINF" | cut -d= -f2 | tr -d '\r'
}

rotate_log
log "=== Wartungslauf gestartet ==="

BEFORE=$(read_build)
log "Aktueller Build: $BEFORE"

log "Stoppe Server..."
sudo systemctl stop cs2.service
server_running=0
sleep 5

log "Suche nach Update..."
if ! "$STEAMCMD" +force_install_dir "$INSTALL" \
        +login anonymous +app_update 730 +quit >> "$LOG" 2>&1; then
    log "FEHLER: steamcmd wurde mit einem Fehler beendet. Update unsicher."
    log "Starte Server mit dem vorhandenen Stand wieder."
    sudo systemctl start cs2.service
    server_running=1
    log "=== Abgebrochen ==="
    exit 1
fi

AFTER=$(read_build)

if [[ "$BEFORE" != "$AFTER" ]]; then
    log "UPDATE installiert: $BEFORE -> $AFTER"
    log "Hinweis: Metamod / CounterStrikeSharp / MatchZy koennen inkompatibel sein."

    # -----------------------------------------------------------------------
    # Ein CS2-Update ueberschreibt gameinfo.gi mit der Originalversion von
    # Valve. Damit verschwindet der Metamod-Eintrag, der Server startet zwar
    # normal, aber ohne jedes Plugin. Das ist der unangenehmste Fehlerfall:
    # es sieht aus, als liefe alles.
    # -----------------------------------------------------------------------
    if ! grep -q "csgo/addons/metamod" "$GAMEINFO"; then
        if [[ "${AUTO_FIX_GAMEINFO:-0}" -eq 1 ]]; then
            cp "$GAMEINFO" "$GAMEINFO_BACKUP"
            # Eintrag direkt hinter die Zeile "Game_LowViolence" setzen,
            # das ist die von Metamod dokumentierte Position.
            if sed -i "/Game_LowViolence/a\\$METAMOD_LINE" "$GAMEINFO" \
               && grep -q "csgo/addons/metamod" "$GAMEINFO"; then
                log "gameinfo.gi: Metamod-Eintrag automatisch wiederhergestellt."
            else
                cp "$GAMEINFO_BACKUP" "$GAMEINFO"
                log "FEHLER: Reparatur fehlgeschlagen, Backup zurueckgespielt."
                log "        gameinfo.gi muss von Hand geprueft werden."
            fi
        else
            log "WARNUNG: Metamod-Eintrag in gameinfo.gi FEHLT."
            log "         Der Server startet OHNE Plugins. Bitte manuell setzen."
        fi
    else
        log "gameinfo.gi: Metamod-Eintrag vorhanden."
    fi
else
    log "Kein Update noetig (Build $AFTER)."
fi

log "Starte Server..."
sudo systemctl start cs2.service
server_running=1

sleep 10
if systemctl is-active --quiet cs2.service; then
    log "Server laeuft."
else
    log "FEHLER: Server ist nach dem Start nicht aktiv. Bitte pruefen:"
    log "        journalctl -u cs2.service -n 50"
fi

log "=== Fertig ==="
