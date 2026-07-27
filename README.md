# CS2 Server Automation

Wartungsskripte für einen CS2 Dedicated Server mit Metamod, CounterStrikeSharp und MatchZy. Bash, systemd, Cron.

## Problem

Valve patcht CS2 oft ohne Ankündigung. Danach ist meistens eins von drei Dingen kaputt:

- Server läuft noch auf dem alten Build, Spieler kommen nicht rein.
- Metamod und CSSharp sind gegen die alte Engine-Version gebaut und laden nicht.
- `gameinfo.gi` wird von Valve überschrieben, der Metamod-Eintrag ist weg.

Der dritte Fall ist der ärgerlichste. Der Server startet ganz normal und wirft keinen Fehler, hat aber kein einziges Plugin geladen. MatchZy fehlt, das Match lässt sich nicht starten, und keiner weiß warum.

Vorher lief das so, dass jemand Abends spielen wollte und mir eine Nachricht geschrieben hat, damit ich das Problem behebe.

## Was es macht

Ein Cronjob um 06:00, da spielt bei uns keiner:

```
stoppen → Build merken → steamcmd → Build vergleichen
        → bei Update: gameinfo.gi prüfen, ggf. reparieren
        → starten → nachsehen, ob er wirklich läuft
```

Morgens ist der Server aktuell oder im Log steht, was kaputt ist.

## Aufbau

```
scripts/cs2-start.sh      Startet den Server, liest config.env
scripts/cs2-update.sh     Der Wartungslauf
systemd/cs2.service       Dienst-Definition
systemd/cs2-sudoers       sudo-Rechte für den steam-User
config.example.env        Vorlage, echte config.env ist in .gitignore
docs/crontab.example      Cron-Eintrag
```

## Warum so gebaut

- **`trap ... EXIT`** — das Skript stoppt den Server und macht danach Dinge, die schiefgehen können. Ohne Sicherheitsnetz bleibt der Server nach einem steamcmd-Fehler bis abends unten.
- **systemd statt screen** — Restart bei Absturz, Logs über journalctl, kein PID-Gefrickel. `exec` im Start-Skript, damit Signale beim Server landen und nicht bei einer Wrapper-Shell.
- **sudo nur für `start` und `stop` von `cs2.service`** — mehr braucht das Skript nicht.
- **Version aus `steam.inf`** statt steamcmd-Ausgabe zu parsen. Das Ausgabeformat ändert sich, die PatchVersion auf der Platte nicht.
- **gameinfo.gi-Reparatur mit Backup, und abschaltbar** über `AUTO_FIX_GAMEINFO=0`. Automatisch in einer Valve-Datei rumzuschreiben will nicht jeder.

## Known Issues

- Plugin-Updates macht das Skript nicht, es warnt nur. Metamod, CSSharp und MatchZy ziehe ich von Hand nach, weil deren Releases nicht zeitgleich zu den CS2-Updates kommen. Teils kann es auch Tage dauern bevor ein Update von den Skripten kommt.
- Keine Benachrichtigung. Fehler sehe ich nur, wenn ich ins Log schaue. Ein Discord-Webhook wäre der nächste Schritt.
- Feste Uhrzeit statt Spielerabfrage per RCON. Reicht bisher.
- Kein Rollback auf den alten Build, wenn ein Update den Server zerlegt.

Ein Server, der gar nicht startet, ist harmlos, den merkt man sofort. Weh tut der, der läuft und trotzdem nichts kann. Deshalb prüft das Skript nach jedem Eingriff nach, statt es anzunehmen.

## Setup

```bash
git clone [<repo>](https://github.com/Laeysel/CS2-Server-Automation) /home/steam/cs2-server-automation
cd /home/steam/cs2-server-automation

cp config.example.env config.env
nano config.env                 # Pfade und GSLT eintragen
chmod +x scripts/*.sh

sudo cp systemd/cs2.service /etc/systemd/system/
sudo cp systemd/cs2-sudoers /etc/sudoers.d/cs2
sudo chmod 440 /etc/sudoers.d/cs2
sudo systemctl daemon-reload
sudo systemctl enable --now cs2.service

crontab -e                      # Inhalt aus docs/crontab.example
```

GSLT-Token: https://steamcommunity.com/dev/managegameservers

---

Gebaut, weil ich keine Lust mehr hatte, das abends von Hand zu reparieren bzw. ich ihn immer funktionsfähig haben will, auch wenn ich mal nicht da bin.
