# CS2 Server Automation

Automatisierte Wartung für einen CS2 Dedicated Server mit Plugin-Stack (Metamod, CounterStrikeSharp, MatchZy). Läuft seit Monaten produktiv auf meinem eigenen Server für eine feste Gruppe von Mitspielern.

Bash, systemd, Cron. Kein Framework, kein Docker – bewusst so.

---

## Das Problem

Valve patcht CS2 ohne Ankündigung. Jedes Update bringt drei Fehlerarten mit sich:

1. **Server läuft auf altem Build** und Spieler können nicht joinen, weil der Client neuer ist.
2. **Plugins sind inkompatibel**, weil Metamod und CounterStrikeSharp gegen eine bestimmte Engine-Version gebaut sind.
3. **`gameinfo.gi` wird von Valve überschrieben.** Damit verschwindet der Metamod-Eintrag – und das ist der unangenehmste Fall: Der Server startet ganz normal, meldet keinen Fehler, läuft aber ohne jedes Plugin. MatchZy ist weg, das Match lässt sich nicht starten, und niemand versteht warum.

Vorher hieß das: Jemand will spielen, es geht nicht, ich setze mich an den Rechner und suche. Meistens abends, meistens dann, wenn alle schon da sind.

## Die Lösung

Ein Wartungslauf um 06:00 Uhr, wenn niemand spielt:

```
Server stoppen  →  Build-Version merken  →  steamcmd  →  Version vergleichen
                →  bei Update: gameinfo.gi prüfen und reparieren
                →  Server starten  →  verifizieren, dass er läuft
```

Das Ergebnis: Der Server ist morgens aktuell und funktionsfähig, oder ich habe im Log eine klare Aussage, was kaputt ist. Kein Suchen mehr im laufenden Betrieb.

## Aufbau

```
scripts/cs2-start.sh      Startet den Server, liest Konfiguration aus config.env
scripts/cs2-update.sh     Der Wartungslauf, per Cron um 06:00
systemd/cs2.service       Dienst-Definition, Restart on-failure
systemd/cs2-sudoers       Minimale sudo-Rechte für den steam-Benutzer
config.example.env        Vorlage, echte config.env ist per .gitignore ausgeschlossen
docs/crontab.example      Cron-Eintrag
```

## Entscheidungen, die ich bewusst so getroffen habe

**Der Server wird immer wieder gestartet, egal was schiefgeht.**
Das Skript stoppt den Server früh und macht danach Dinge, die fehlschlagen können. Ohne Absicherung bleibt der Server bei einem Fehler in steamcmd dauerhaft unten – und das fällt erst abends auf. Deshalb gibt es einen `trap ... EXIT`, der den Dienst bei jedem Abbruch wieder hochfährt. Zusätzlich wird nach dem Start geprüft, ob er wirklich aktiv ist, statt das anzunehmen.

**Systemd statt `screen` oder `nohup`.**
Automatischer Neustart bei Absturz, sauberes Logging über journalctl, und `stop`/`start` funktioniert aus dem Skript heraus ohne PID-Gefrickel. `exec` im Start-Skript sorgt dafür, dass der Server selbst der Hauptprozess des Dienstes wird und Signale direkt bekommt statt an ein Wrapper-Bash zu gehen.

**Der steam-Benutzer bekommt genau zwei sudo-Rechte, nicht mehr.**
Das Skript braucht `systemctl start` und `stop` für einen einzigen Dienst. Genau das steht in der sudoers-Regel, namentlich, nichts darüber hinaus. Ein pauschales NOPASSWD für einen Benutzer, der einen aus dem Internet erreichbaren Gameserver betreibt, wäre der falsche Kompromiss.

**Versionsvergleich über `steam.inf` statt über die Ausgabe von steamcmd.**
Die `PatchVersion` in `steam.inf` ist die Wahrheit auf der Platte. steamcmd zu parsen ist fragil, weil sich das Ausgabeformat ändert und je nach Fehlerfall anders aussieht. Vorher/nachher vergleichen ist einfacher und robuster.

**Die gameinfo.gi-Reparatur ist abschaltbar.**
Automatisch in einer Datei herumzuschreiben, die Valve selbst verwaltet, ist ein Eingriff. Deshalb: vorher Backup, danach verifizieren, dass der Eintrag wirklich drinsteht, bei Misserfolg Backup zurückspielen. Und über `AUTO_FIX_GAMEINFO=0` lässt sich das Ganze auf reines Warnen umstellen. Wer das nicht will, muss es nicht nutzen.

## Known Issues

Was ich weiß, aber (noch) nicht gelöst habe:

- **Plugin-Versionen werden nicht automatisch aktualisiert.** Nach einem Engine-Update warnt das Skript nur, dass Metamod/CSSharp/MatchZy kaputt sein könnten. Das Nachziehen mache ich von Hand, weil die Releases nicht synchron zu den CS2-Updates erscheinen und ein blindes Update das Problem eher vergrößert.
- **Keine Benachrichtigung.** Ich sehe Fehler nur, wenn ich ins Log schaue. Ein Discord-Webhook bei Fehlern wäre der nächste sinnvolle Schritt und ist wenig Aufwand.
- **Feste Uhrzeit statt Prüfung auf aktive Spieler.** Um 06:00 spielt bei uns niemand, das reicht für den Anwendungsfall. Sauberer wäre, per RCON die Spielerzahl abzufragen und den Lauf zu verschieben, wenn jemand online ist.
- **Kein Rollback auf den vorherigen Build.** Wenn ein Update den Server unbrauchbar macht, hilft das Skript nicht weiter. Über SteamCMD wäre ein Downgrade möglich, aber das ist deutlich mehr Aufwand als der Fall bisher wert war.

## Was ich dabei gelernt habe

Der eigentliche Erkenntnisgewinn war nicht Bash, sondern **welche Fehler wehtun**. Der Server, der gar nicht startet, ist harmlos – das merkt man sofort. Gefährlich ist der Server, der scheinbar normal läuft, aber ohne Plugins. Deshalb prüft das Skript nicht nur, ob etwas geklappt hat, sondern verifiziert das Ergebnis: Ist der Eintrag nach der Reparatur wirklich in der Datei? Ist der Dienst nach dem Start wirklich aktiv?

Das Zweite: Automatisierung, die im Fehlerfall einen schlechteren Zustand hinterlässt als gar keine Automatisierung, ist ein Rückschritt. Der Trap, der den Server auf jeden Fall wieder hochfährt, ist deshalb die wichtigste Zeile im ganzen Skript.

## Setup

```bash
git clone <repo> /home/steam/cs2-server-automation
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

GSLT-Token gibt es unter https://steamcommunity.com/dev/managegameservers

---

Gebaut, weil ich keine Lust mehr hatte, den Server abends von Hand zu reparieren.
