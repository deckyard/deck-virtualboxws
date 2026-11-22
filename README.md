# @deckyard/virtualboxws

[![test](https://github.com/deckyard/deck-virtualboxws/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-virtualboxws/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-virtualboxws/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-virtualboxws)](https://github.com/deckyard/deck-virtualboxws/releases/latest)

Oracle VirtualBox 7 for [Jennifer](https://jennifer-lang.dev/) programs,
through VirtualBox's SOAP web service (`vboxwebsrv`): list machines, start
and stop them, take and restore snapshots, clone, import and export
appliances, and read the guest's IP, on a host reached over HTTP(S) instead
of by running `VBoxManage` (that is the
[`@deckyard/virtualbox`](https://github.com/deckyard/deck-virtualbox) deck).
Every object reference is released, long operations have deadlines, and
the password is not sent over plain http to another machine unless asked.

**[Documentation](https://deckyard.github.io/deck-virtualboxws/)**

## Install

```sh
jvc add @deckyard/virtualboxws
```

This vendors the deck to `vendor/<scope>/virtualboxws/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`<scope>-virtualboxws-<version>.tar.gz`) there.

## Usage

```jennifer
use io;
use os;

import "@deckyard/virtualboxws/" as virtualboxws;

def s as virtualboxws.Session init virtualboxws.logon(
    virtualboxws.endpoint("https://vmhost:18083/"), "admin", os.getEnv("VBOX_PASSWORD"));
virtualboxws.start($s, "web");
io.printf("up at %s\n", virtualboxws.waitForIp($s, "web", 0, 180000));
virtualboxws.logoff($s);
```

## Requirements

Jennifer 0.27.0 or newer, the default `jennifer` binary (the deck needs
`net`; the stock `jennifer-tiny` has no network driver), and VirtualBox 7.0
or newer with its web service, `vboxwebsrv`, running on the host.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/virtualboxws_test.j  # the tests, against a fake web service
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
