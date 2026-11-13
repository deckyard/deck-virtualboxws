# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualboxws - guest: guest properties and the guest's IP address. Spliced
# into virtualboxws.j via include.

# how often waitForIp asks, in milliseconds
def const IP_POLL_MS as int init 1000;

/**
 * A guest property, which the Guest Additions and the host set: the guest's
 * addresses under `/VirtualBox/GuestInfo/Net/`, its OS under
 * `/VirtualBox/GuestInfo/OS/`, and any key of your own.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property, such as `/VirtualBox/GuestInfo/OS/Product`
 * @return {string} its value, `""` when it is not set
 * @throws {Error} kind "virtualboxws" if an argument is unusable or a call fails
 */
export func guestProperty(s as Session, vm as string, key as string) {
    checkText($key, "the property");
    def m as string init machine($s, $vm);
    defer release($s, $m);
    return returned(callOn(
        $s,
        "IMachine_getGuestPropertyValue",
        $m,
        {"property": [$key]},
        "guestProperty " + $vm));
}

/**
 * Set a guest property.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property
 * @param value {string} its value; use `unsetGuestProperty` to remove it
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses
 */
export func setGuestProperty(s as Session, vm as string, key as string, value as string) {
    checkText($key, "the property");
    checkText($value, "the property value");
    onMutable(
        $s,
        $vm,
        "IMachine_setGuestPropertyValue",
        {"property": [$key], "value": [$value]},
        "setGuestProperty " + $vm);
}

/**
 * Remove a guest property.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param key {string} the property
 * @throws {Error} kind "virtualboxws" if an argument is unusable or VirtualBox refuses
 */
export func unsetGuestProperty(s as Session, vm as string, key as string) {
    checkText($key, "the property");
    onMutable(
        $s,
        $vm,
        "IMachine_deleteGuestProperty",
        {"name": [$key]},
        "unsetGuestProperty " + $vm);
}

/**
 * Call a method on a machine's mutable copy: lock it shared (a write lock
 * when it does not run), call, unlock.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param method {string} the `IMachine` method
 * @param args {map of string to list of string} its parameters
 * @param what {string} the operation, for error messages
 * @throws {Error} kind "virtualboxws" if VirtualBox refuses
 */
func onMutable(
    s as Session,
    vm as string,
    method as string,
    args as map of string to list of string,
    what as string) {
    def m as string init machine($s, $vm);
    defer release($s, $m);
    def sess as string init newSession($s);
    defer unlockAndRelease($s, $sess);
    lock($s, $m, $sess, "Shared", $what);
    def mutable as string init refOf(callOn($s, "ISession_getMachine", $sess, {}, $what), $what);
    defer release($s, $mutable);
    callOn($s, $method, $mutable, $args, $what);
}

/**
 * The IPv4 address the Guest Additions report for a guest interface.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the guest's network interface, from 0 (not the NIC slot, which counts from 1)
 * @return {string} the address, `""` before the guest reports one
 * @throws {Error} kind "virtualboxws" if an argument is unusable or a call fails
 */
export func guestIp(s as Session, vm as string, nic as int) {
    checkRange($nic, 0, 35, "the guest interface");
    return guestProperty($s, $vm, "/VirtualBox/GuestInfo/Net/" + convert.toString($nic) + "/V4/IP");
}

/**
 * Wait until the guest reports an IPv4 address for an interface: a started
 * machine has one once its Guest Additions run. Each request gets at most
 * the time left. The property can survive a hard power-off, so a machine
 * started after one may report its old address at first: unset
 * `/VirtualBox/GuestInfo/Net/<nic>/V4/IP` before `start` when that matters.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @param nic {int} the guest's network interface, from 0
 * @param timeoutMs {int} how long to wait, 1 to 86400000
 * @return {string} the address
 * @throws {Error} kind "virtualboxws" if an argument is unusable, a call fails, or no address comes in time
 * @example
 *   virtualboxws.start($s, "web");
 *   def ip as string init virtualboxws.waitForIp($s, "web", 0, 120000);
 */
export func waitForIp(s as Session, vm as string, nic as int, timeoutMs as int) {
    checkRange($timeoutMs, 1, 86400000, "the timeout");
    def noIp as string init $vm + " reported no IP address for interface " +
        convert.toString($nic) +
        " within " + convert.toString($timeoutMs) + " ms";
    def started as time.Time init time.now();
    def polling as Session init $s;
    while (true) {
        def left as int init $timeoutMs - time.milliseconds(time.sub(time.now(), $started));
        if ($left <= 0) {
            fail($noIp + " (are the Guest Additions running?)");
        }
        $polling.config.timeoutMs = $s.config.timeoutMs;
        if ($left < $polling.config.timeoutMs) {
            $polling.config.timeoutMs = $left;
        }
        def ip as string init "";
        try {
            $ip = guestIp($polling, $vm, $nic);
        } catch (e) {
            if (not strings.contains($e.message, ": no answer from ") or
                $polling.config.timeoutMs == $s.config.timeoutMs) {
                throw $e;
            }
            fail($noIp + " (the last request did not answer)");
        }
        if ($ip != "") {
            return $ip;
        }
        $left = $timeoutMs - time.milliseconds(time.sub(time.now(), $started));
        if ($left > 0) {
            def pause as int init IP_POLL_MS;
            if ($left < $pause) {
                $pause = $left;
            }
            time.sleep(time.fromMilliseconds($pause));
        }
    }
    return "";
}
