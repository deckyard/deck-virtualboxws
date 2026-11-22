# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualboxws - white-box tests for the guest topic. Spliced into
# virtualboxws_test.j via include.

func testGuestProperties() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getGuestPropertyValue#1"] = "returnval=Ubuntu 24.04 LTS";
    $answers["IMachine_getGuestPropertyValue#2"] = "returnval=";
    $answers["IMachine_setGuestPropertyValue"] = "";
    $answers["IMachine_deleteGuestProperty"] = "";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    testing.assertEqual(
        guestProperty($s, "web", "/VirtualBox/GuestInfo/OS/Product"),
        "Ubuntu 24.04 LTS");
    testing.assertEqual(guestProperty($s, "web", "/mine"), "");
    setGuestProperty($s, "web", "/mine", "a b");
    unsetGuestProperty($s, "web", "/mine");
    try {
        setGuestProperty($s, "web", "/mine", "");
        missed("empty");
    } catch (e) {
        testing.assertContains($e.message, "the property value is empty");
    }
    def calls as string init work(stopFake($f));
    testing.assertContains(
        $calls,
        "IMachine_getGuestPropertyValue|_this=" + MACHINE_REF +
            "|property=/VirtualBox/GuestInfo/OS/Product");
    testing.assertContains(
        $calls,
        "lockType=Shared;ISession_getMachine|_this=" + SESSION_REF +
            ";IMachine_setGuestPropertyValue|_this=" + MUTABLE_REF + "|property=/mine|value=a b");
    testing.assertContains(
        $calls,
        "IMachine_deleteGuestProperty|_this=" + MUTABLE_REF + "|name=/mine");
}

func testGuestIpAndWaitForIp() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getGuestPropertyValue#1"] = "returnval=10.0.2.15";
    $answers["IMachine_getGuestPropertyValue#2"] = "returnval=10.0.2.15";
    $answers["IMachine_getGuestPropertyValue"] = "returnval=";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    testing.assertEqual(guestIp($s, "web", 0), "10.0.2.15");
    testing.assertEqual(waitForIp($s, "web", 0, 5000), "10.0.2.15");
    def started as time.Time init time.now();
    try {
        waitForIp($s, "web", 0, 300);
        missed("no ip");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: web reported no IP address for interface 0 within 300 ms (are the Guest Additions running?)");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 3000);
    try {
        guestIp($s, "web", 36);
        missed("36");
    } catch (e) {
        testing.assertContains($e.message, "the guest interface must be 0 to 35");
    }
    def calls as string init work(stopFake($f));
    testing.assertContains($calls, "property=/VirtualBox/GuestInfo/Net/0/V4/IP");
}

func testWaitForIpBoundsEachRequest() {
    def answers as map of string to string init baseAnswers();
    # Answers 250 ms after the 500 ms wait is over; the deferred release
    # queues behind it, so the call returns at about 750 ms.
    $answers["IMachine_getGuestPropertyValue"] = "!sleep 750";
    def f as Fake init startFake($answers);
    def started as time.Time init time.now();
    try {
        waitForIp(fakeSession($f), "web", 0, 500);
        missed("stalled");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: web reported no IP address for interface 0 within 500 ms (the last request did not answer)");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 1000);
    stopFake($f);
}
