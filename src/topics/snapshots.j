# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualboxws - snapshots: snapshots, full and linked clones, and OVA / OVF
# import and export. Spliced into virtualboxws.j via include.

/**
 * A snapshot of a machine, from `snapshots`.
 *
 * @field name {string} its name
 * @field uuid {string} its UUID
 * @field description {string} its description, `""` if it has none
 * @field depth {int} how deep in the tree it is: 0 for the first snapshot, 1 for one taken from it, ...
 * @field current {bool} whether the machine runs from it
 */
export def struct Snapshot {
    name as string,
    uuid as string,
    description as string,
    depth as int,
    current as bool
};

/**
 * A machine's snapshots, as a tree in depth-first order (parents before
 * children).
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @return {list of Snapshot} the snapshots, empty without any
 * @throws {Error} kind "virtualboxws" if the name is unusable, there is no such machine or a call fails
 * @example
 *   for (def snap in virtualboxws.snapshots($s, "web")) {
 *       io.printf("%s%s\n", strings.repeat("  ", $snap.depth), $snap.name);
 *   }
 */
export func snapshots(s as Session, vm as string) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def what as string init "snapshots " + $vm;
    def out as list of Snapshot init [];
    if (whole(attribute($s, "IMachine", "SnapshotCount", $m, $what)) == 0) {
        return $out;
    }
    def currentId as string init "";
    def cur as string init attribute($s, "IMachine", "CurrentSnapshot", $m, $what);
    if ($cur != "") {
        checkRef($cur, $what);
        try {
            $currentId = attribute($s, "ISnapshot", "Id", $cur, $what);
        } catch (e) {
            release($s, $cur);
            throw $e;
        }
        release($s, $cur);
    }
    # the root: findSnapshot with an empty name
    def stack as list of string init [
        refOf(callOn($s, "IMachine_findSnapshot", $m, {"nameOrId": [""]}, $what), $what)
    ];
    def depths as list of int init [0];
    while (len($stack) > 0) {
        def ref as string init $stack[len($stack) - 1];
        def depth as int init $depths[len($depths) - 1];
        $stack = lists.slice($stack, 0, len($stack) - 1);
        $depths = lists.slice($depths, 0, len($depths) - 1);
        def children as list of string init [];
        try {
            def uuid as string init attribute($s, "ISnapshot", "Id", $ref, $what);
            $out[] = Snapshot{
                name: attribute($s, "ISnapshot", "Name", $ref, $what),
                uuid: $uuid,
                description: attribute($s, "ISnapshot", "Description", $ref, $what),
                depth: $depth,
                current: $uuid == $currentId
            };
            $children = all(callOn($s, "ISnapshot_getChildren", $ref, {}, $what), "returnval");
        } catch (e) {
            release($s, $ref);
            releaseAll($s, $stack);
            throw $e;
        }
        release($s, $ref);
        # push in reverse, so the first child comes next
        def i as int init len($children) - 1;
        while ($i >= 0) {
            checkRef($children[$i], $what);
            $stack[] = $children[$i];
            $depths[] = $depth + 1;
            $i = $i - 1;
        }
    }
    return $out;
}

/**
 * Take a snapshot and wait for it, within the long deadline. A running
 * machine is paused while it is taken.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name
 * @param description {string} its description, `""` for none
 * @return {string} the snapshot's UUID
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses
 * @example
 *   virtualboxws.takeSnapshot($s, "web", "before-upgrade", "");
 */
export func takeSnapshot(s as Session, vm as string, name as string, description as string) {
    checkName($name, "the snapshot name");
    checkChars($description, "the description");
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init "takeSnapshot " + $vm;
    lock($s, $m, $sess, "Shared", $what);
    def mutable as string init refOf(callOn($s, "ISession_getMachine", $sess, {}, $what), $what);
    defer release($s, $mutable);
    def r as map of string to list of string init callOn(
        $s,
        "IMachine_takeSnapshot",
        $mutable,
        {"name": [$name], "description": [$description], "pause": ["true"]},
        $what);
    waitFor($s, refOf($r, $what), $s.config.longTimeoutMs, $what);
    return first($r, "id");
}

/**
 * Return a powered-off machine to a snapshot and wait, within the long
 * deadline.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name or UUID
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses (the machine runs, no such snapshot)
 */
export func restoreSnapshot(s as Session, vm as string, name as string) {
    checkName($name, "the snapshot name");
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init "restoreSnapshot " + $vm;
    lock($s, $m, $sess, "Write", $what);
    def mutable as string init refOf(callOn($s, "ISession_getMachine", $sess, {}, $what), $what);
    defer release($s, $mutable);
    def snap as string init refOf(
        callOn($s, "IMachine_findSnapshot", $mutable, {"nameOrId": [$name]}, $what),
        $what);
    defer release($s, $snap);
    waitFor(
        $s,
        refOf(
            callOn($s, "IMachine_restoreSnapshot", $mutable, {"snapshot": [$snap]}, $what),
            $what),
        $s.config.longTimeoutMs,
        $what);
}

/**
 * Delete a snapshot, merging its changes into the disks after it, and wait,
 * within the long deadline.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param name {string} the snapshot's name or UUID
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses
 */
export func deleteSnapshot(s as Session, vm as string, name as string) {
    checkName($name, "the snapshot name");
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init "deleteSnapshot " + $vm;
    lock($s, $m, $sess, "Shared", $what);
    def mutable as string init refOf(callOn($s, "ISession_getMachine", $sess, {}, $what), $what);
    defer release($s, $mutable);
    def snap as string init refOf(
        callOn($s, "IMachine_findSnapshot", $mutable, {"nameOrId": [$name]}, $what),
        $what);
    defer release($s, $snap);
    def id as string init attribute($s, "ISnapshot", "Id", $snap, $what);
    waitFor(
        $s,
        refOf(callOn($s, "IMachine_deleteSnapshot", $mutable, {"id": [$id]}, $what), $what),
        $s.config.longTimeoutMs,
        $what);
}

# --- clones ----------------------------------------------------------------

/**
 * Copy a machine and its disks into a new, registered machine (a full
 * clone), within the long deadline.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param newName {string} the clone's name
 * @return {string} the clone's UUID
 * @throws {Error} kind "virtualboxws" if a name is unusable or VirtualBox refuses
 * @example
 *   virtualboxws.clone($s, "template", "web2");
 */
export func clone(s as Session, vm as string, newName as string) {
    checkName($newName, "the clone's name");
    def m as string init machine($s, $vm);
    defer release($s, $m);
    return cloneFrom($s, $m, $m, $newName, [], "clone " + $vm);
}

/**
 * Make a linked clone: a new, registered machine whose disks are difference
 * images on a snapshot's disks. Fast and small, but tied to that snapshot.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param snapshot {string} the snapshot's name or UUID
 * @param newName {string} the clone's name
 * @return {string} the clone's UUID
 * @throws {Error} kind "virtualboxws" if a name is unusable or VirtualBox refuses
 */
export func linkedClone(s as Session, vm as string, snapshot as string, newName as string) {
    checkName($snapshot, "the snapshot name");
    checkName($newName, "the clone's name");
    def what as string init "linkedClone " + $vm;
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def snap as string init refOf(
        callOn($s, "IMachine_findSnapshot", $m, {"nameOrId": [$snapshot]}, $what),
        $what);
    defer release($s, $snap);
    def source as string init refOf(callOn($s, "ISnapshot_getMachine", $snap, {}, $what), $what);
    defer release($s, $source);
    return cloneFrom($s, $m, $source, $newName, ["Link"], $what);
}

/**
 * Create the target machine, clone into it and register it.
 *
 * @param s {Session} the session
 * @param original {string} the machine being cloned, for its OS type and platform
 * @param source {string} what is cloned: the machine, or a snapshot's machine
 * @param newName {string} the clone's name
 * @param options {list of string} `CloneOptions`, such as `Link`
 * @param what {string} the operation, for error messages
 * @return {string} the clone's UUID
 * @throws {Error} kind "virtualboxws" if VirtualBox refuses
 */
func cloneFrom(
    s as Session,
    original as string,
    source as string,
    newName as string,
    options as list of string,
    what as string) {
    def args as map of string to list of string init {"settingsFile": [""], "name": [$newName]};
    if ($s.major > 7 or $s.minor >= 1) {
        # 7.1 added the platform architecture; clone onto the original's
        def platform as string init refOf(
            callOn($s, "IMachine_getPlatform", $original, {}, $what),
            $what);
        def arch as string init "";
        try {
            $arch = attribute($s, "IPlatform", "Architecture", $platform, $what);
        } catch (e) {
            release($s, $platform);
            throw $e;
        }
        release($s, $platform);
        $args["platform"] = [$arch];
    }
    $args["osTypeId"] = [attribute($s, "IMachine", "OSTypeId", $original, $what)];
    for (def empty in ["flags", "cipher", "passwordId", "password"]) {
        $args[$empty] = [""];
    }
    def target as string init refOf(
        callOn($s, "IVirtualBox_createMachine", $s.vbox, $args, $what),
        $what);
    defer release($s, $target);
    waitFor(
        $s,
        refOf(
            callOn(
                $s,
                "IMachine_cloneTo",
                $source,
                {"target": [$target], "mode": ["MachineState"], "options": $options},
                $what),
            $what),
        $s.config.longTimeoutMs,
        $what);
    callOn($s, "IVirtualBox_registerMachine", $s.vbox, {"machine": [$target]}, $what);
    return attribute($s, "IMachine", "Id", $target, $what);
}

# --- appliances ------------------------------------------------------------

/**
 * Import an appliance (`.ova` or `.ovf`, a path on the host) as VirtualBox
 * names its machines, within the long deadline.
 *
 * @param s {Session} the session
 * @param path {string} the appliance file on the VirtualBox host
 * @return {list of string} the UUIDs of the imported machines
 * @throws {Error} kind "virtualboxws" if the path is unusable or VirtualBox refuses
 */
export func importOva(s as Session, path as string) {
    return importAppliance($s, $path, "");
}

/**
 * Import an appliance's first machine under a name of your choice.
 *
 * @param s {Session} the session
 * @param path {string} the appliance file on the VirtualBox host
 * @param name {string} the imported machine's name
 * @return {list of string} the UUIDs of the imported machines
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses (the name is taken)
 * @example
 *   virtualboxws.importAs($s, "/srv/images/debian.ova", "build-1");
 */
export func importAs(s as Session, path as string, name as string) {
    checkName($name, "the machine name");
    return importAppliance($s, $path, $name);
}

/**
 * Read, interpret and import an appliance, renaming its first machine when
 * a name is given (as `VBoxManage import --vmname` does).
 *
 * @param s {Session} the session
 * @param path {string} the appliance file
 * @param name {string} the first machine's new name, `""` to keep it
 * @return {list of string} the imported machines' UUIDs
 * @throws {Error} kind "virtualboxws" if the path is unusable or VirtualBox refuses
 */
func importAppliance(s as Session, path as string, name as string) {
    checkAppliance($path);
    def what as string init "import " + $path;
    def app as string init refOf(
        callOn($s, "IVirtualBox_createAppliance", $s.vbox, {}, $what),
        $what);
    defer release($s, $app);
    waitFor(
        $s,
        refOf(callOn($s, "IAppliance_read", $app, {"file": [$path]}, $what), $what),
        $s.config.longTimeoutMs,
        $what);
    callOn($s, "IAppliance_interpret", $app, {}, $what);
    if ($name != "") {
        rename($s, $app, $name, $what);
    }
    waitFor(
        $s,
        refOf(callOn($s, "IAppliance_importMachines", $app, {}, $what), $what),
        $s.config.longTimeoutMs,
        $what);
    return all(callOn($s, "IAppliance_getMachines", $app, {}, $what), "returnval");
}

/**
 * Give an interpreted appliance's first machine a name: every description
 * entry stays enabled with its suggested value, but `Name`.
 *
 * @param s {Session} the session
 * @param app {string} the appliance
 * @param name {string} the name
 * @param what {string} the operation, for error messages
 * @throws {Error} kind "virtualboxws" if the appliance holds no machine or VirtualBox refuses
 */
func rename(s as Session, app as string, name as string, what as string) {
    def descriptions as list of string init all(
        callOn($s, "IAppliance_getVirtualSystemDescriptions", $app, {}, $what),
        "returnval");
    defer releaseAll($s, $descriptions);
    if (len($descriptions) == 0) {
        fail($what + ": the appliance holds no machine");
    }
    def d as map of string to list of string init callOn(
        $s,
        "IVirtualSystemDescription_getDescription",
        $descriptions[0],
        {},
        $what);
    def types as list of string init all($d, "types");
    def values as list of string init all($d, "VBoxValues");
    def extra as list of string init all($d, "extraConfigValues");
    if (len($values) != len($types) or len($extra) != len($types) or
        not lists.contains($types, "Name")) {
        fail($what + ": the appliance's description has no usable Name entry");
    }
    def enabled as list of string init [];
    for (def i in 0..len($types)) {
        $enabled[] = "true";
        if ($types[$i] == "Name") {
            $values[$i] = $name;
        }
    }
    callOn(
        $s,
        "IVirtualSystemDescription_setFinalValues",
        $descriptions[0],
        {"enabled": $enabled, "VBoxValues": $values, "extraConfigValues": $extra},
        $what);
}

/**
 * Export a powered-off machine to an appliance (OVF 2.0) on the VirtualBox
 * host, within the long deadline. The file name's extension picks the form:
 * `.ova` one archive, `.ovf` a descriptor with the disks beside it.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param path {string} the appliance file to write on the host
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses
 */
export func exportOva(s as Session, vm as string, path as string) {
    checkAppliance($path);
    def what as string init "export " + $vm;
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def app as string init refOf(
        callOn($s, "IVirtualBox_createAppliance", $s.vbox, {}, $what),
        $what);
    defer release($s, $app);
    def description as string init refOf(
        callOn($s, "IMachine_exportTo", $m, {"appliance": [$app], "location": [$path]}, $what),
        $what);
    release($s, $description);
    waitFor(
        $s,
        refOf(
            callOn($s, "IAppliance_write", $app, {"format": ["ovf-2.0"], "path": [$path]}, $what),
            $what),
        $s.config.longTimeoutMs,
        $what);
}

/**
 * Refuse an appliance path: a path ending in `.ova` or `.ovf`.
 *
 * @param path {string} the path
 * @throws {Error} kind "virtualboxws" if it is unusable
 */
func checkAppliance(path as string) {
    checkText($path, "the appliance file");
    def lower as string init strings.lower($path);
    if (not strings.endsWith($lower, ".ova") and not strings.endsWith($lower, ".ovf")) {
        fail("the appliance file must end in .ova or .ovf, got " + shown($path));
    }
}
