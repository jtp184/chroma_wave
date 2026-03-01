# Feature Backlog

Feature plans for ChromaWave post-groundwork development. Each feature file contains
the product owner decision, implementation plan, and acceptance criteria.

## Priority Summary

```
P0 — Must-have (blocking usability issues)
  001  Fix README API examples                 Small     docs only
  002  Display rotation (0/90/180/270)          Medium    C + Ruby

P1 — Should-have (significant value)
  003  Atkinson dithering                       Small     Ruby only
  004  Smart refresh scheduler (opt-in)         Medium    Ruby only
  005  Flexbox-lite layout DSL                  Large     Ruby only

P2 — Nice-to-have (polish & differentiation)
  006  QR codes + 1D barcodes                   Small     Ruby + gems
  007  CIE Lab color distance                   Small     Ruby only
  008  Dirty region tracking                    Medium    Ruby only
  009  Browser preview server                   Medium    Ruby + webrick
  011  Canvas transforms (flip/scale/crop)      Small     Ruby only

P3 — Future (deferred or dependent)
  010  Widget library                           Large     depends on 005
  012  Spectra 6 preparation (format only)      Small     C + Ruby
  013  Redirect vendor Debug() macro            Small     C only
```

## Dependency Graph

```
Hard blockers (──▶) vs soft/recommended ordering (- - ▷)

 ┌─────────┐                         ┌─────────┐
 │ 001 Fix │                         │ 013     │
 │ README  │                         │Debug()  │
 └─────────┘                         └─────────┘
     Independent                      Independent


 ┌─────────┐ - - - - - - ▷ ┌─────────┐
 │ 002     │  (enhances)    │ 009     │
 │Rotation │ - - - - - - ▷ │ Preview │
 └────┬────┘                └─────────┘
      │
      └ - - - - - - - - ▷ ┌─────────┐
         (recommended      │ 008     │
          to land first)   │Dirty    │
                           │Regions  │
                           └─────────┘

 ┌─────────┐ - - - - - - ▷ ┌─────────┐
 │ 007     │  (recommended  │ 003     │
 │CIE Lab  │   to land      │Atkinson │
 └────┬────┘   first)       │Dither   │
      │                     └─────────┘
      └ - - - - - - - - ▷ ┌─────────┐
         (enhances)        │ 012     │
                           │Spectra 6│
                           └─────────┘

 ┌─────────┐               ┌─────────┐
 │ 004     │ - - - - - - ▷ │ 008     │
 │Refresh  │  (integrates)  │Dirty    │
 │Scheduler│               │Regions  │
 └─────────┘               └─────────┘

 ┌─────────┐ ════════════▶ ┌──────────┐
 │ 005     │  HARD BLOCKER  │ 010      │
 │Layout   │               │ Widgets  │
 │DSL      │               └──────────┘
 └─────────┘

 ┌─────────┐  ┌─────────┐
 │ 006     │  │ 011     │
 │QR/Bar   │  │Canvas   │
 │codes    │  │Xforms   │
 └─────────┘  └─────────┘
  Independent   Independent
```

### Hard Blockers

| Feature | Blocked by | Rationale |
|---|---|---|
| 010 (Widgets) | 005 (Layout DSL) | Widgets compose via Layout DSL's `widget` method and calculator |

### Recommended Ordering (not blocking, but avoids rework)

| Land first | Before | Rationale |
|---|---|---|
| 007 (CIE Lab) | 003 (Atkinson) | Avoids re-baselining dither test expectations twice |
| 002 (Rotation) | 008 (Dirty Regions) | Dirty rects need rotation transform for `display_region` |
| 002 (Rotation) | 009 (Preview) | Preview inherits rotation for free if Display supports it |
| 004 (Scheduler) | 008 (Dirty Regions) | Scheduler should wrap `show_dirty` for partial tracking |

## Decisions Not Taken

| Feature | Decision | Rationale |
|---|---|---|
| Touch input (GT1151) | Skipped entirely | Too niche, high maintenance burden |
| Sierra Lite / Stucki / Burkes dithering | Deferred | Atkinson alone covers the critical gap |
| Canvas-level rotation | Skipped | Display-level rotation is sufficient |
| Convenience kwargs on drawing methods | Skipped | Pen API is the correct design |
| Spectra 6 driver configs | Deferred | Requires hardware validation |
| Constraint-based layout | Skipped | Overkill for e-paper; Flexbox-lite covers 90% |
| Grid-based layout | Skipped | Flexbox-lite is more flexible |
| Separate widgets gem | Skipped | Batteries-included in main gem |
| File-watcher preview | Skipped | WebSocket preview is better UX |
