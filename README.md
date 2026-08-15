# Bongo Cat für Omarchy Quattro

Lokales, leichtgewichtiges Quickshell-Plugin ohne AUR-Paket und ohne separaten
`wayland-bongocat`-Prozess. Quickshell zeichnet die Katze; ein kleiner lokaler
C-Helfer liest ausschließlich Tastendrücke und meldet nur `L` oder `R` für die
beiden Pfoten.

## Bedienung

- Linksklick auf das Bar-Icon: Einstellungen öffnen.
- Rechtsklick auf das Bar-Icon: Bongo Cat ein-/ausschalten.
- Mittelklick: Animation testen.
- Oben rechts im Panel: Ein/Aus, Position sperren/entsperren und Test.
- Entsperrte Katze ziehen; Mausrad ändert die Größe, Rechtsklick sperrt.
- Größe: 120–640 px. Farbe: `Default`, `Theme` oder eigener `#RRGGBB`-Wert.
- Tastatur: `P` sperrt/entsperrt, `T` testet, Pfeiltasten verschieben um 10 px.

## Tastaturzugriff

Wayland stellt absichtlich keine API bereit, mit der ein passives Overlay alle
Tastendrücke beobachten kann. Deshalb ist einmalig eine Polkit-Freigabe nötig.
Der Panel-Knopf `Allow Input` installiert diese Regel:

```udev
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", TAG+="uaccess"
```

Dadurch darf der jeweils aktive lokale Desktop-Benutzer Tastatur-Events lesen.
Das ist enger als eine dauerhafte Mitgliedschaft in der Gruppe `input`, bedeutet
aber ausdrücklich: **Alle Prozesse dieses aktiven Benutzerkontos könnten rohe
Tastatureingaben lesen.** Der Zugriff kann im Panel jederzeit wieder entzogen
werden, auch wenn Bongo Cat deaktiviert ist. Das blockiert neue Leser und
startet den Bongo-Helfer ohne Zugriff neu. Fremde Prozesse, die das Gerät bereits
geöffnet hatten, verlieren ihren offenen Dateideskriptor erst nach Abmeldung,
Neustart oder erneutem Anstecken des Geräts.

Der Plugin-Helfer selbst protokolliert weder Zeichen noch Keycodes und gibt nur
linke/rechte Pfotenereignisse an Quickshell weiter. Dennoch ist der Zugriff auf
Eingabegeräte sicherheitsrelevant und wird nie automatisch freigeschaltet.

## Lokaler Build

Der Helfer wird beim ersten Laden mit dem vorhandenen C-Compiler nach
`~/.cache/omarchy/bongocat/bongo-input` gebaut. Es wird kein AUR-Paket
installiert.

## Vor dem Entfernen

Zuerst im Panel `Revoke Input` wählen. Alternativ lokal ausführen:

```bash
~/.config/omarchy/plugins/hancore.bongocat/helper/input-access remove
rm -rf ~/.cache/omarchy/bongocat
```

Erst danach den Pluginordner löschen.

## Herkunft

Grafikframes und Pfotenbelegung stammen aus `saatvik333/wayland-bongocat`.
Siehe `THIRD_PARTY.md` und `LICENSE.wayland-bongocat`.
