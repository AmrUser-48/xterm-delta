===================================
Minimal xterm build (agent checklist)
===================================

Goal: build xterm with scroll-lock support (``autoScrollLock``) and without
features we do not need (Xinerama, toolbar, Tek4014, sixel, and so on).

Rules
=====

1. Run ``./configure --help`` first. Use only options that it prints.
   Do not guess option names.
2. Do not edit source files for this task. Build configuration only.
3. Stop and report on any error. Quote the exact failing line.

Dependencies (Debian/Ubuntu)
============================

.. code-block:: sh

   sudo apt install build-essential pkg-config \
       libx11-dev libxt-dev libxaw7-dev libxmu-dev libxext-dev \
       libncurses-dev

Not needed with the flags below: ``libxinerama-dev``, ``libxpm-dev``,
``libfreetype-dev``, ``libxft-dev``.

Configure
=========

.. code-block:: sh

   ./configure \
       --prefix="$HOME/.local" \
       --without-xinerama \
       --disable-tek4014 \
       --disable-vt52 \
       --disable-sixel-graphics \
       --disable-print-graphics \
       --disable-session-mgt \
       --disable-tcap-fkeys \
       --disable-tcap-query \
       --disable-sun-fkeys \
       --disable-paste64 \
       --disable-exec-selection \
       --disable-desktop \
       --disable-setuid \
       --disable-setgid

Not enabled (off by default): ``--enable-toolbar``, ``--enable-regis-graphics``,
``--enable-hp-fkeys``, ``--enable-sco-fkeys``, ``--enable-dec-locator``.

Keep these (usually wanted): wide chars, 256 colors, i18n, bold color.
Add ``--disable-wide-chars`` or ``--disable-i18n`` only if UTF-8 is not needed.
Add ``--disable-freetype`` if you do not use TrueType fonts (``-fa``/``faceName``).

Build and install
=================

.. code-block:: sh

   make -j"$(nproc)"
   make install

Scroll lock
===========

Scroll lock (``OPT_SCROLL_LOCK``) is compiled in by default. There is no
configure flag for it, so nothing to enable. It stays off until set at runtime.

``~/.Xresources``::

   XTerm*autoScrollLock: true
   XTerm*scrollTtyOutput: false

Apply and test:

.. code-block:: sh

   xrdb -merge ~/.Xresources
   "$HOME/.local/bin/xterm"

Verify
======

1. Run ``"$HOME/.local/bin/xterm" -version``.
2. Scroll back with Shift+PageUp, then run ``yes | head -n 1000``.
   The viewport should stay on the same lines.
3. Report which configure flags were used and the result of step 2.
