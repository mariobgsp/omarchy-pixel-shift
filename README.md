# Pixel Shift for Omarchy

OLED burn-in protection for the Omarchy bar. The bar is the one thing on an
Omarchy desktop that never moves: the same glyphs light the same subpixels for
as long as the machine is on. Pixel Shift walks the bar's widgets a few pixels
back and forth on a slow schedule, so that wear spreads over a small area
instead of etching into one. The steps are small enough and rare enough that
you will not see them, and nothing about your layout changes: the bar rests
exactly where it rested before.

<p align="center"><img src="preview.png" alt="The bar at its three edge positions, with red lines marking the resting edges" width="900"></p>

## How it works

The plugin is a bar widget that draws nothing and takes no space. From
wherever it sits in the layout it reaches the three things the built-in bar
pins to the screen and nudges them together:

| Part of the bar | Resting position | What moves | Default path |
| --- | --- | --- | --- |
| Left section | 8 px from the left edge | padding grows and shrinks, the section slides in and out | 6, 8, 10 px: a 5 px path |
| Right section | 8 px from the right edge | the same padding, at the same moment, so both sides move inward and outward symmetrically | 6, 8, 10 px: a 5 px path |
| Center | pinned to the middle of the screen (`centerAnchor`, or the whole center group without one) | its center offset | -1, 0, +1 px: a 3 px path |

Both ends of the bar step by 2 px at a time; the center, which is mostly thin
text and is the part your eye lands on, moves 1 px at a time. On a vertical
bar the same happens along the bar's long axis. On a HiDPI screen these are
logical pixels: at scale 2 every step is twice as many physical pixels.

Every instance of the bar (one per monitor) follows the same shared clock, so
a multi-monitor setup moves in lockstep.

### Schedule

The defaults follow what OLED panel makers do in their own firmware. LG,
Samsung, Philips and MSI all shift the whole picture by one or two pixels at
a fixed interval of roughly two to three minutes; the interval is not
critical, it only has to be much shorter than the hours over which burn-in
accumulates. What does matter is that every position on the path gets the
same share of time, otherwise the middle of the path wears fastest and the
protection collapses back to a single spot.

So the walk is: out to one end, hold one step, back to the other end, hold
one step. For the edges that is `-2, 0, +2, +2, 0, -2` and then again. Every
position is visited exactly twice per cycle, and no single move is bigger than
one step. The center walks `-1, 0, +1, +1, 0, -1` on the same beat.

Two refinements over a plain timer:

- **Masked steps.** A step is far harder to notice while the bar is redrawing
  anyway. When the focused workspace changes, the plugin takes its next step
  right then, provided at least a quarter of the interval has passed since the
  last one, and restarts the interval from that moment. Turn this off with
  `shiftOnWorkspaceSwitch` if you would rather have a strict clock.
- **Wall-clock phase.** The starting position is derived from the time of
  day, so a restarted shell does not always begin at the same spot.

Sources: [LG on Screen Shift and the OLED care suite](https://www.reviewed.com/televisions/features/most-oleds-have-built-measures-prevent-burn),
[Samsung on Pixel Shift for OLED monitors](https://www.samsung.com/us/support/troubleshoot/TSG10003240/),
[Philips OLED monitor care guide](https://www.documents.philips.com/assets/20240614/e9d80118b8a944aa88d7b18f009ec9de.pdf),
[MSI OLED Care](https://www.msi.com/blog/how-msi-oled-care-prevents-oled-from-burn-in),
[tvfindr on pixel shift](https://www.tvfindr.com/wiki/pixelshift/).

## Install

Requires Omarchy 4.0.2 or newer (the plugin shell) with the built-in bar or an
unmodified clone of it.

The bar names its sections through the `Bar` object it hands to its own widgets.
A third-party widget only gets a `PluginBarApi` facade since Omarchy 4.0.3-ish,
which has no `moduleSlots`, so the widget falls back to finding the section
Loaders in the scene graph when the slots are not there. Both paths are in
`BarWidget.qml` (`sectionTargets()`), so the plugin works installed either way.

```sh
omarchy plugin add https://github.com/evindor/omarchy-pixel-shift.git --enable
```

Drop `--enable` to review the code first (it is one QML file and one JS file),
then `omarchy plugin enable io.github.evindor.pixel-shift`. It lands in the
right section of the bar as an invisible, zero-width entry; where it sits does
not matter, so leave it wherever it ends up.

## Settings

Change a value with `omarchy bar set io.github.evindor.pixel-shift <key> <value>`
or from the bar settings panel. Changes apply live.

| Key | Default | Range | Meaning |
| --- | --- | --- | --- |
| `intervalSec` | 180 | 10 to 3600 | Seconds between steps. |
| `edgeTravel` | 2 | 0 to 8 | How far (px) the left and right sections move in from, and out to, their resting position. 2 gives a 5 px path; 0 leaves the edges alone. |
| `edgeStep` | 2 | 1 to 4 | Size (px) of one edge move. Smaller steps are harder to notice and take more steps to cover the path. |
| `centerTravel` | 1 | 0 to 4 | How far (px) the center moves off center, one pixel at a time. 1 gives a 3 px path; 0 leaves the center alone. |
| `shiftOnWorkspaceSwitch` | true | | Take the next step when the workspace changes, never more often than a quarter of the interval. |

A quieter profile, for example, moves every pixel one at a time:

```sh
omarchy bar set io.github.evindor.pixel-shift edgeStep 1
omarchy bar set io.github.evindor.pixel-shift intervalSec 90
```

## Remove

```sh
omarchy plugin remove io.github.evindor.pixel-shift
```

Disabling or removing the plugin puts every margin and offset back where it
was. Nothing is written anywhere except the plugin's own entry in
`~/.config/omarchy/shell.json`, which Omarchy manages.

## Limits and honest expectations

- Only the bar moves, not the whole screen. Pixel Shift is for the one
  permanently static element; the panel's own pixel shift, brightness limits
  and refresh cycles still matter for everything else.
- A few pixels of travel is what panel firmware does too, and it is a
  mitigation, not a cure. A bar that is transparent, dim, or hidden when not
  needed helps more than any amount of shifting.
- The plugin knows the layout of the built-in bar (its left and right section
  lists and its centered module). A third-party full bar, or a clone with a
  changed layout, is left alone: the plugin finds nothing to move and does
  nothing.
- With a `centerAnchor`, the bar pins the anchored module's *slot*, not the list
  around it. That slot is only reachable when the bar hands over its
  `moduleSlots` — which it does to its own bar, not to a plugin — so in the
  scene-graph fallback only the section lists themselves are moved.
- No external dependencies, no processes, no network, no sudo. Like every
  Omarchy plugin it runs unsandboxed inside your shell with your permissions.

## Develop

Clone this repository, then run the checks from its root:

```sh
bin/test      # qmltestrunner unit tests, omarchy plugin validate, qmllint
```

Layout:

- `manifest.json`: an Omarchy `bar-widget` plugin with its settings schema.
- `BarWidget.qml`: the invisible widget. Owns the timer, listens for
  workspace switches, finds the bar's pinned parts and moves them.
- `core/Schedule.js`: the walk and the shared clock as pure functions.
- `tests/tst_schedule.qml`: unit tests for the schedule.

To iterate on a local checkout, copy it into place (Omarchy refuses symlinks
inside plugin folders); the shell reloads the plugin on save:

```sh
rsync -a --delete --exclude .git ./ ~/.config/omarchy/plugins/io.github.evindor.pixel-shift/
```

To watch it work, set a short interval and compare screenshots of the bar:

```sh
omarchy bar set io.github.evindor.pixel-shift intervalSec 10
grim -g "0,0 1440x26" before.png; sleep 10; grim -g "0,0 1440x26" after.png
```

## License

MIT
