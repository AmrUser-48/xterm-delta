# xterm

> Problem: In xterm, when live output is streaming into the terminal and the user scrolls up into the scrollback buffer to read, the visible lines on screen keep moving instead of staying still, whereas alacritty, tilda, and vte hold the viewed buffer fixed in place during live output. When the user is scrolled back into history and scroll-on-output is disabled, new lines appended at the bottom must not shift the currently displayed lines on screen (until the scrollback history ring buffer overflows and evicts those lines), while keeping the display and scrollbar synchronized without shaking or moving the text the user is reading.                   [info.txt](info.txt)


The big finding: xterm already has this feature
The xtermScroll function in util.c already contains the pinning branch.
```c
if OPT_SCROLL_LOCK
    else if ((screen->allowScrollLock && screen->scroll_lock)
             || (screen->autoScrollLock && screen->topline < 0)) {
        ...
        if (--(screen->topline) < -screen->savelines) { SetWindowTop(...) }
        if (++(screen->savedlines) > screen->savelines) { ... }
    }
endif
```
It is controlled by the autoScrollLock resource, which defaults to False. 

```xdefaults
XTerm*autoScrollLock: true
XTerm*scrollTtyOutput: false
```
If your build was compiled without OPT_SCROLL_LOCK, rebuild with scroll-lock enabled. That may be the entire fix.
