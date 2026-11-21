# Runtime verification

Run one of the newly built packages in a Debian 12 X session:

```sh
xterm -si -sl 5000 -xrm 'XTerm*autoScrollLock: true' \
  -e bash -c 'i=0; while :; do printf "line %d\\n" "$i"; i=$((i+1)); sleep 0.02; done'
```

1. Scroll up several screens while the producer continues.
2. Confirm the visible line numbers remain fixed while new output enters scrollback.
3. Confirm the scrollbar tracks the growing saved-lines history.
4. Continue beyond the `-sl 5000` limit while viewing the oldest retained history; confirm the viewport advances only as old rows are evicted.
5. Repeat with jump scrolling enabled and disabled.
6. Run an alternate-screen program such as `vim` or `htop`; confirm normal screen updates are unchanged.

The build forces `OPT_SCROLL_LOCK=1`, but `autoScrollLock` is a runtime resource and defaults to false. The test command explicitly enables it and uses `-si` to disable scrolling to the live bottom.

The CI workflow verifies package compilation only. These interactive X11 checks must be performed on a running desktop session.
