# Runtime verification

Run the patched binary in a Debian 12 X session:

```sh
xterm -si -sl 5000 -e bash -c 'i=0; while :; do printf "line %d\\n" "$i"; i=$((i+1)); sleep 0.02; done'
```

1. Scroll up several screens while the producer continues.
2. Confirm that the visible line numbers remain unchanged while scrollback grows.
3. Confirm that the scrollbar reflects the increasing saved-lines history.
4. Keep the viewport at the oldest retained history and continue past the `-sl 5000` limit. Confirm that only rows evicted from the top are advanced and repainted.
5. Repeat with jump scrolling enabled and disabled, and with multi-line scroll commands.
6. Run an alternate-screen program (for example, `vim` or `htop`) and confirm that its normal screen updates are unchanged.
7. Exercise mouse selection while output is running; selection should stay attached to the viewed text and be clipped only when its text is evicted.

The workflow compiles both package variants. These interactive X11 checks remain manual; a successful package build alone does not establish runtime correctness.
