# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.28.0

# virtualboxws - machines: the registered machines, one machine's details,
# and power. Spliced into virtualboxws.j via include.

# the ways startWith starts a machine
def const START_MODES as list of string init ["headless", "gui", "separate"];

# MachineState names as VBoxManage prints them, so both decks agree
def const STATES as map of string to string init {
    "PoweredOff": "poweroff",
    "Saved": "saved",
    "Teleported": "teleported",
    "Aborted": "aborted",
    "AbortedSaved": "aborted-saved",
    "Running": "running",
    "Paused": "paused",
    "Stuck": "gurumeditation",
    "Teleporting": "teleporting",
    "LiveSnapshotting": "livesnapshotting",
    "Starting": "starting",
    "Stopping": "stopping",
    "Saving": "saving",
    "Restoring": "restoring",
    "TeleportingPausedVM": "teleportingpausedvm",
    "TeleportingIn": "teleportingin",
    "DeletingSnapshotOnline": "deletingsnapshotlive",
    "DeletingSnapshotPaused": "deletingsnapshotlivepaused",
    "OnlineSnapshotting": "onlinesnapshotting",
    "RestoringSnapshot": "restoringsnapshot",
    "DeletingSnapshot": "deletingsnapshot",
    "SettingUp": "settingup",
    "Snapshotting": "snapshotting"
};

# the states in which a machine runs (counted by runningVms)
def const RUNNING_STATES as list of string init
    [
    "running",
    "paused",
    "starting",
    "stopping",
    "saving",
    "livesnapshotting",
    "onlinesnapshotting",
    "deletingsnapshotlive",
    "deletingsnapshotlivepaused",
    "teleporting",
    "teleportingpausedvm",
    "teleportingin",
    "gurumeditation"
];

/**
 * A registered machine, from `vms` or `runningVms`.
 *
 * @field name {string} its name; `<inaccessible>` when VirtualBox cannot read its settings
 * @field uuid {string} its UUID
 */
export def struct Vm {
    name as string,
    uuid as string
};

/**
 * One machine's details, from `info`.
 *
 * @field name {string} its name
 * @field uuid {string} its UUID
 * @field osType {string} its guest OS type id, such as `Ubuntu_64`
 * @field state {string} as VBoxManage names it: `poweroff`, `running`, `paused`, `saved`, `aborted`, ...
 * @field memoryMb {int} its memory in MiB
 * @field cpus {int} its processors
 * @field description {string} its description
 * @field configFile {string} its settings file (`.vbox`) on the host
 * @field sessionState {string} `Unlocked`, `Locked` (a process uses it), `Spawning` or `Unlocking`
 * @field currentSnapshot {string} the current snapshot's name, `""` without snapshots
 * @field snapshotCount {int} how many snapshots it has
 */
export def struct VmInfo {
    name as string,
    uuid as string,
    osType as string,
    state as string,
    memoryMb as int,
    cpus as int,
    description as string,
    configFile as string,
    sessionState as string,
    currentSnapshot as string,
    snapshotCount as int
};

/**
 * Every registered machine.
 *
 * @param s {Session} the session
 * @return {list of Vm} the machines
 * @throws {VirtualboxwsError} kind "virtualboxws" if a call fails
 * @example
 *   for (def m in virtualboxws.vms($s)) {
 *       io.printf("%s %s\n", $m.uuid, $m.name);
 *   }
 */
export func vms(s as Session) {
    def refs as list of string init all(
        callOn($s, "IVirtualBox_getMachines", $s.vbox, {}, "getMachines"),
        "returnval");
    defer releaseAll($s, $refs);
    def out as list of Vm init [];
    for (def ref in $refs) {
        checkRef($ref, "getMachines");
        $out[] = vmOf($s, $ref);
    }
    return $out;
}

/**
 * The machines that run (running, paused, starting, saving, ...).
 *
 * @param s {Session} the session
 * @return {list of Vm} the machines
 * @throws {VirtualboxwsError} kind "virtualboxws" if a call fails
 */
export func runningVms(s as Session) {
    def refs as list of string init all(
        callOn($s, "IVirtualBox_getMachines", $s.vbox, {}, "getMachines"),
        "returnval");
    defer releaseAll($s, $refs);
    def out as list of Vm init [];
    for (def ref in $refs) {
        checkRef($ref, "getMachines");
        if (attribute($s, "IMachine", "Accessible", $ref, "getMachines") != "true") {
            continue;
        }
        if (lists.contains(
            RUNNING_STATES,
            stateName(attribute($s, "IMachine", "State", $ref, "getState")))) {
            $out[] = vmOf($s, $ref);
        }
    }
    return $out;
}

/**
 * A machine's name and UUID.
 *
 * @param s {Session} the session
 * @param ref {string} the machine
 * @return {Vm} its name (`<inaccessible>` if VirtualBox cannot read it) and UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if a call fails
 */
func vmOf(s as Session, ref as string) {
    def uuid as string init attribute($s, "IMachine", "Id", $ref, "getId");
    if (attribute($s, "IMachine", "Accessible", $ref, "getAccessible") != "true") {
        return Vm{name: "<inaccessible>", uuid: $uuid};
    }
    return Vm{name: attribute($s, "IMachine", "Name", $ref, "getName"), uuid: $uuid};
}

/**
 * Whether a machine is registered, by name or UUID.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @return {bool} whether it is
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or a call fails otherwise
 */
export func hasVm(s as Session, vm as string) {
    def ref as string init "";
    try {
        $ref = machine($s, $vm);
    } catch (e) {
        if ($e.kind == "virtualboxws" and $e.code == "VBOX_E_OBJECT_NOT_FOUND") {
            return false;
        }
        throw $e;
    }
    release($s, $ref);
    return true;
}

/**
 * One machine's details.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @return {VmInfo} the details
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable, there is no such machine (`VBOX_E_OBJECT_NOT_FOUND`) or a call fails
 * @example
 *   def i as virtualboxws.VmInfo init virtualboxws.info($s, "web");
 *   io.printf("%s: %s, %d MiB\n", $i.name, $i.state, $i.memoryMb);
 */
export func info(s as Session, vm as string) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def what as string init "info " + $vm;
    def current as string init "";
    def snap as string init attribute($s, "IMachine", "CurrentSnapshot", $m, $what);
    if ($snap != "") {
        checkRef($snap, $what);
        try {
            $current = attribute($s, "ISnapshot", "Name", $snap, $what);
        } catch (e) {
            release($s, $snap);
            throw $e;
        }
        release($s, $snap);
    }
    return VmInfo{
        name: attribute($s, "IMachine", "Name", $m, $what),
        uuid: attribute($s, "IMachine", "Id", $m, $what),
        osType: attribute($s, "IMachine", "OSTypeId", $m, $what),
        state: stateName(attribute($s, "IMachine", "State", $m, $what)),
        memoryMb: whole(attribute($s, "IMachine", "MemorySize", $m, $what)),
        cpus: whole(attribute($s, "IMachine", "CPUCount", $m, $what)),
        description: attribute($s, "IMachine", "Description", $m, $what),
        configFile: attribute($s, "IMachine", "SettingsFilePath", $m, $what),
        sessionState: attribute($s, "IMachine", "SessionState", $m, $what),
        currentSnapshot: $current,
        snapshotCount: whole(attribute($s, "IMachine", "SnapshotCount", $m, $what))
    };
}

/**
 * A machine's state, as VBoxManage names it.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @return {string} `poweroff`, `running`, `paused`, `saved`, `aborted`, ...
 * @throws {VirtualboxwsError} kind "virtualboxws" as `info`
 */
export func state(s as Session, vm as string) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    return stateName(attribute($s, "IMachine", "State", $m, "state " + $vm));
}

/**
 * VBoxManage's name for a `MachineState`.
 *
 * @param apiState {string} the state as the API names it, such as `PoweredOff`
 * @return {string} VBoxManage's name, such as `poweroff`; an unknown state in lower case
 */
func stateName(apiState as string) {
    if (maps.has(STATES, $apiState)) {
        return STATES[$apiState];
    }
    return strings.lower($apiState);
}

/**
 * A whole number from a reply.
 *
 * @param s {string} the text
 * @return {int} the number, 0 if it is none
 */
func whole(s as string) {
    if (not regex.matches('^-?[0-9]{1,18}$', $s)) {
        return 0;
    }
    return convert.toInt($s);
}

# --- power -----------------------------------------------------------------

/**
 * Start a machine without a window and wait until it runs.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or VirtualBox refuses (it already runs: `VBOX_E_INVALID_OBJECT_STATE`)
 * @example
 *   virtualboxws.start($s, "web");
 */
export func start(s as Session, vm as string) {
    startWith($s, $vm, "headless");
}

/**
 * Start a machine in a given mode and wait until it runs, within the long
 * deadline (restoring a saved state can take a while).
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param mode {string} `headless` (no window), `gui` (a window on the host's desktop) or `separate`
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name or mode is unusable or VirtualBox refuses
 */
export func startWith(s as Session, vm as string, mode as string) {
    if (not lists.contains(START_MODES, $mode)) {
        fail("the start mode must be one of " + strings.join(START_MODES, ", ") + ", got " +
            shown($mode));
    }
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init "start " + $vm;
    def progress as string init refOf(
        callOn($s, "IMachine_launchVMProcess", $m, {"session": [$sess], "name": [$mode]}, $what),
        $what);
    waitFor($s, $progress, $s.config.longTimeoutMs, $what);
}

/**
 * Run a console method on a running machine: lock it shared, get its
 * console, call, and wait for the progress when the method returns one.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param method {string} the `IConsole` method, such as `powerDown`
 * @param waits {bool} whether it returns an `IProgress` to wait for
 * @throws {VirtualboxwsError} kind "virtualboxws" if the machine is not running or VirtualBox refuses
 */
func onConsole(s as Session, vm as string, method as string, waits as bool) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init $method + " " + $vm;
    lock($s, $m, $sess, "Shared", $what);
    def console as string init refOf(callOn($s, "ISession_getConsole", $sess, {}, $what), $what);
    defer release($s, $console);
    def r as map of string to list of string init callOn(
        $s,
        "IConsole_" + $method,
        $console,
        {},
        $what);
    if ($waits) {
        waitFor($s, refOf($r, $what), $s.config.longTimeoutMs, $what);
    }
}

/**
 * Turn a machine off at once, as pulling the plug does, and wait for it.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not running
 */
export func powerOff(s as Session, vm as string) {
    onConsole($s, $vm, "powerDown", true);
}

/**
 * Press the machine's ACPI power button, so the guest shuts down by itself.
 * It returns at once; poll `state` for `poweroff`.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not running
 */
export func acpiShutdown(s as Session, vm as string) {
    onConsole($s, $vm, "powerButton", false);
}

/**
 * Pause a running machine.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not running
 */
export func pause(s as Session, vm as string) {
    onConsole($s, $vm, "pause", false);
}

/**
 * Resume a paused machine.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not paused
 */
export func resume(s as Session, vm as string) {
    onConsole($s, $vm, "resume", false);
}

/**
 * Reset a running machine, as the reset button does.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not running
 */
export func reset(s as Session, vm as string) {
    onConsole($s, $vm, "reset", false);
}

/**
 * Save a running machine's state to disk and stop it, and wait; `start`
 * resumes it.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or the machine is not running
 */
export func saveState(s as Session, vm as string) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    def what as string init "saveState " + $vm;
    lock($s, $m, $sess, "Shared", $what);
    def mutable as string init refOf(callOn($s, "ISession_getMachine", $sess, {}, $what), $what);
    defer release($s, $mutable);
    waitFor(
        $s,
        refOf(callOn($s, "IMachine_saveState", $mutable, {}, $what), $what),
        $s.config.longTimeoutMs,
        $what);
}
