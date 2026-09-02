# Lunaris Command Glyphs

## Concept

The cursor is a tactical language shared by menus and the battlefield. Every
glyph uses the same dark-navy keyline and lunar-relic materials so transitions
feel like changes of intent, not changes of art style. Color reinforces the
meaning, but silhouette remains the primary signal:

- moon silver: neutral navigation and text;
- cyan: inspection, selection, and map movement;
- command gold: clickable UI actions and pending work;
- emerald: valid operator deployment and valid healing;
- amber: valid trap placement;
- crimson: disabled, rejected, or invalid actions.

All runtime textures are 32×32 with transparent backgrounds. The size stays
within desktop and web cursor limits, preserves crisp pixel-art presentation,
and avoids browser-side rescaling.

## State matrix

| Role | Shape signal | Used when | Priority |
| --- | --- | --- | ---: |
| `default` | northwest lunar pointer | no stronger semantic action applies | fallback |
| `action` | raised gold command hand | enabled buttons, sliders, and commands | Control-owned |
| `text` | cyan I-beam | editable text | Control-owned |
| `select` | four-corner cyan reticle | pointer is over a selectable allied operator | 40 |
| `deploy` | green diamond and plus | operator placement is valid at the hovered cell | 100 |
| `trap` | amber spike reticle | trap placement is valid at the hovered cell | 100 |
| `heal` | green crescent and plus | mend target is valid | 100 |
| `invalid` | broken red ring and slash | disabled UI or invalid action target | 100 / Control-owned |
| `pan` | open cyan hand | battlefield can be panned under the pointer | 10 |
| `pan_grab` | closed cyan hand | map drag is active | 10 |
| `busy` | lunar astrolabe hourglass | a future blocking operation claims busy state | caller-defined |

World claims are resolved by priority, then recency. This makes placement and
targeting override selectable-unit hover, while selectable-unit hover overrides
passive pan. Normal Control cursor shapes still win when a UI element is
physically under the pointer.

## Runtime contract

`CursorManager` is an autoload and installs all custom textures once. World
systems use a scoped claim and must release it when the state or node ends:

```gdscript
CursorManager.claim(self, CursorManager.ROLE_BUSY, 80)
# ... asynchronous or modal work ...
CursorManager.release_claim(self)
```

Interactive Controls are classified automatically. A special Control can opt
into a semantic role without coupling itself to a texture path:

```gdscript
CursorManager.set_control_role(help_button, CursorManager.ROLE_HEAL)
CursorManager.clear_control_role(help_button)
```

Claims store weak owner references, so freed owners cannot permanently strand a
cursor state. Every intentional caller still releases explicitly to make state
transitions immediate.

## Asset provenance

`assets/ui/cursors/lunaris_cursor_sheet_source.png` was generated with the
built-in GPT Image 2 workflow from a transparent 4×4 sprite-sheet prompt. The
eleven runtime textures are deterministic crops and downscales of that generated
source; no cursor artwork is hand-drawn or substituted. The source prompt asked
for, in order: default, action, select, deploy, trap, heal, invalid, pan,
pan-grab, busy, and text glyphs, with the remaining cells empty.
