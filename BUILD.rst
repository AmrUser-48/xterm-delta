==========================================
xterm .deb packages for Debian 12 (agent)
==========================================

Goal: build **two** trimmed xterm packages for Debian 12 (bookworm), both with
scroll lock (``autoScrollLock``) available and without features we do not need.

======  ===========  ==========================  ==========================
Track   Upstream     Package name                Version
======  ===========  ==========================  ==========================
A       Debian's     ``xterm``                   ``<stock>+custom1``
B       latest tag   ``xterm-latest``            ``<tag>-0custom1``
======  ===========  ==========================  ==========================

Track B installs to ``/opt/xterm-latest`` so both can be installed side by side.

Rules
=====

1. Do not guess. Run ``./configure --help`` and read ``debian/rules`` before
   editing. Use only flags that exist in that version.
2. Build only inside a clean bookworm chroot or container
   (``debian:12``, sbuild, or pbuilder). Never on the host.
3. No source code edits. Packaging and configure flags only.
4. Stop and report any failure. Quote the exact failing line.

Common configure flags
======================

Verified against xterm 412. Re-check each one with ``--help`` for track A.

.. code-block:: text

   --without-xinerama --disable-tek4014 --disable-vt52
   --disable-sixel-graphics --disable-print-graphics
   --disable-session-mgt --disable-tcap-fkeys --disable-tcap-query
   --disable-sun-fkeys --disable-paste64 --disable-exec-selection

Keep wide chars, 256 colors, and i18n. Scroll lock is compiled in by default
(no flag); it exists in xterm 379 and 412.

Setup (in the container)
========================

.. code-block:: sh

   # enable deb-src for bookworm first
   apt update
   apt install build-essential devscripts equivs
   apt build-dep xterm
   mkdir work && cd work

Track A: Debian's xterm, trimmed
================================

.. code-block:: sh

   apt source xterm
   cd xterm-*/
   # edit debian/rules: remove flags for the features above, add the common flags
   dch --local +custom --distribution bookworm "Trim unused features"
   dpkg-buildpackage -us -uc -b

Check ``apt-cache policy xterm`` for the stock version and report it. If
``debian/rules`` already passes a flag, do not duplicate it.

Track B: latest upstream
========================

1. Find the newest tag:
   ``git ls-remote --tags https://github.com/ThomasDickey/xterm-snapshots.git``
   (latest seen: ``xterm-412``). Get the tarball for that tag.
2. Copy ``debian/`` from track A's source tree into the new tree
   (or run ``uupdate``). Refresh or drop patches that no longer apply.
   Report which patches were dropped.
3. In ``debian/control`` and ``debian/changelog`` rename the package to
   ``xterm-latest``, version ``<tag>-0custom1``.
4. In ``debian/rules`` pass ``--prefix=/opt/xterm-latest`` and the common flags.
   Rename installed files so no path collides with the ``xterm`` package
   (check with ``dpkg -c``).
5. Build: ``dpkg-buildpackage -us -uc -b``.

Verify (both packages)
======================

.. code-block:: sh

   dpkg -c ../*.deb | head -30
   lintian ../*.deb
   dpkg -i ../*.deb
   xterm -version     # or /opt/xterm-latest/bin/xterm -version

Scroll back with Shift+PageUp, run ``yes | head -n 1000``; the view should stay
pinned when ``~/.Xresources`` has::

   XTerm*autoScrollLock: true
   XTerm*scrollTtyOutput: false

Report: flags used, package versions, ``lintian`` output, test result.
