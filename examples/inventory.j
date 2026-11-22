#!/usr/bin/env -S jennifer run
# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

/**
 * inventory example: log on to a VirtualBox web service and list its
 * machines with their state, size and snapshots.
 *
 *   VBOXWS_URL=https://vmhost:18083/ VBOXWS_USER=admin VBOXWS_PASSWORD=... \
 *       jennifer run examples/inventory.j
 *
 * VBOXWS_CA names a PEM file to trust for the service's certificate. With
 * VBOXWS_URL unset it prints how to run it, so CI runs it without
 * VirtualBox.
 */

use fs;
use io;
use os;

import "http.j" as http;
import "../src/virtualboxws.j" as virtualboxws;

def url as string init os.getEnv("VBOXWS_URL");
if ($url == "") {
    io.printf("set VBOXWS_URL (https://host:18083/), VBOXWS_USER and VBOXWS_PASSWORD\n");
    exit 0;
}

try {
    def c as virtualboxws.Config init virtualboxws.endpoint($url);
    if (os.getEnv("VBOXWS_CA") != "") {
        $c = virtualboxws.withTls(
            $c,
            http.TlsOptions{caCert: fs.readBytes(os.getEnv("VBOXWS_CA"))});
    }
    def s as virtualboxws.Session init virtualboxws.logon(
        $c,
        os.getEnv("VBOXWS_USER"),
        os.getEnv("VBOXWS_PASSWORD"));
    io.printf("VirtualBox %s\n", $s.version);
    try {
        for (def m in virtualboxws.vms($s)) {
            if ($m.name == "<inaccessible>") {
                io.printf("%s: inaccessible\n", $m.uuid);
                continue;
            }
            def i as virtualboxws.VmInfo init virtualboxws.info($s, $m.uuid);
            io.printf(
                "%s (%s): %s, %d CPU, %d MiB, %d snapshots\n",
                $i.name,
                $i.uuid,
                $i.state,
                $i.cpus,
                $i.memoryMb,
                $i.snapshotCount);
        }
    } catch (e) {
        virtualboxws.logoff($s);
        throw $e;
    }
    virtualboxws.logoff($s);
} catch (e) {
    io.printf("%s\n", $e.message);
    exit 1;
}
