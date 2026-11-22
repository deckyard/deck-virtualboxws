# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.27.0

# virtualboxws - white-box tests for the machines topic. Spliced into
# virtualboxws_test.j via include.

func testVmsReadsEveryMachineAndReleasesIt() {
    def answers as map of string to string init baseAnswers();
    $answers["IVirtualBox_getMachines"] = "returnval=" + MACHINE_REF + "\nreturnval=" + OTHER_REF;
    $answers["IMachine_getId@" + MACHINE_REF] = "returnval=4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c";
    $answers["IMachine_getId@" + OTHER_REF] = "returnval=0f9e8d7c-6b5a-4f3e-8d2c-1b0a9f8e7d6c";
    $answers["IMachine_getAccessible@" + MACHINE_REF] = "returnval=true";
    $answers["IMachine_getAccessible@" + OTHER_REF] = "returnval=false";
    $answers["IMachine_getName@" + MACHINE_REF] = "returnval=web";
    def f as Fake init startFake($answers);
    def found as list of Vm init vms(fakeSession($f));
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($found), 2);
    testing.assertEqual($found[0].name, "web");
    testing.assertEqual($found[0].uuid, "4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    testing.assertEqual($found[1].name, "<inaccessible>");
    testing.assertEqual(released($seen), MACHINE_REF + "," + OTHER_REF);
}

func testRunningVmsFiltersByState() {
    def answers as map of string to string init baseAnswers();
    $answers["IVirtualBox_getMachines"] = "returnval=" + MACHINE_REF + "\nreturnval=" + OTHER_REF;
    $answers["IMachine_getAccessible"] = "returnval=true";
    $answers["IMachine_getState@" + MACHINE_REF] = "returnval=Paused";
    $answers["IMachine_getState@" + OTHER_REF] = "returnval=PoweredOff";
    $answers["IMachine_getId"] = "returnval=4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c";
    $answers["IMachine_getName"] = "returnval=web";
    def f as Fake init startFake($answers);
    def found as list of Vm init runningVms(fakeSession($f));
    stopFake($f);
    testing.assertEqual(len($found), 1);
    testing.assertEqual($found[0].name, "web");
}

func testHasVm() {
    def answers as map of string to string init baseAnswers();
    $answers["IVirtualBox_findMachine#2"] = "!fault " + NOT_FOUND +
        " Could not find a registered machine named 'db'";
    $answers["IVirtualBox_findMachine#3"] = "!fault -2147467259 broken";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    testing.assertTrue(hasVm($s, "web"));
    testing.assertFalse(hasVm($s, "db"));
    try {
        hasVm($s, "x");
        missed("broken");
    } catch (e) {
        testing.assertEqual(errorCode($e), "E_FAIL");
    }
    testing.assertEqual(released(stopFake($f)), MACHINE_REF);
}

func testInfoReadsTheMachine() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getName"] = "returnval=web";
    $answers["IMachine_getId"] = "returnval=4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c";
    $answers["IMachine_getOSTypeId"] = "returnval=Ubuntu_64";
    $answers["IMachine_getState"] = "returnval=PoweredOff";
    $answers["IMachine_getMemorySize"] = "returnval=2048";
    $answers["IMachine_getCPUCount"] = "returnval=2";
    $answers["IMachine_getDescription"] = "returnval=line one";
    $answers["IMachine_getSettingsFilePath"] = "returnval=/srv/vms/web/web.vbox";
    $answers["IMachine_getSessionState"] = "returnval=Unlocked";
    $answers["IMachine_getSnapshotCount"] = "returnval=3";
    $answers["IMachine_getCurrentSnapshot"] = "returnval=" + OTHER_REF;
    $answers["ISnapshot_getName"] = "returnval=patched";
    def f as Fake init startFake($answers);
    def i as VmInfo init info(fakeSession($f), "web");
    def seen as list of string init stopFake($f);
    testing.assertEqual($i.name, "web");
    testing.assertEqual($i.uuid, "4e5c3b6a-1f2d-4c8e-9a7b-0d1e2f3a4b5c");
    testing.assertEqual($i.osType, "Ubuntu_64");
    testing.assertEqual($i.state, "poweroff");
    testing.assertEqual($i.memoryMb, 2048);
    testing.assertEqual($i.cpus, 2);
    testing.assertEqual($i.description, "line one");
    testing.assertEqual($i.configFile, "/srv/vms/web/web.vbox");
    testing.assertEqual($i.sessionState, "Unlocked");
    testing.assertEqual($i.currentSnapshot, "patched");
    testing.assertEqual($i.snapshotCount, 3);
    testing.assertEqual($seen[0], "IVirtualBox_findMachine|_this=" + VBOX_REF + "|nameOrId=web");
    testing.assertEqual(released($seen), MACHINE_REF + "," + OTHER_REF);
}

func testStateNames() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getState#1"] = "returnval=Stuck";
    $answers["IMachine_getState#2"] = "returnval=AbortedSaved";
    $answers["IMachine_getState#3"] = "returnval=SomethingNew";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    testing.assertEqual(state($s, "web"), "gurumeditation");
    testing.assertEqual(state($s, "web"), "aborted-saved");
    testing.assertEqual(state($s, "web"), "somethingnew");
    stopFake($f);
    testing.assertEqual(whole("x"), 0);
}

func testStartLaunchesAndUnlocks() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_launchVMProcess"] = "returnval=" + PROGRESS_REF;
    def f as Fake init startFake($answers);
    start(fakeSession($f), "web");
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        work($seen),
        "IVirtualBox_findMachine|_this=" + VBOX_REF + "|nameOrId=web;" +
            "IWebsessionManager_getSessionObject|refIVirtualBox=" + VBOX_REF + ";" +
            "IMachine_launchVMProcess|_this=" + MACHINE_REF + "|session=" + SESSION_REF +
            "|name=headless;" +
            "IProgress_getCompleted|_this=" + PROGRESS_REF + ";IProgress_getResultCode|_this=" +
            PROGRESS_REF + ";" +
            "ISession_unlockMachine|_this=" + SESSION_REF);
    testing.assertEqual(released($seen), SESSION_REF + "," + MACHINE_REF + "," + PROGRESS_REF);
    try {
        startWith(fakeSession($f), "web", "sdl");
        missed("sdl");
    } catch (e) {
        testing.assertContains($e.message, "the start mode must be one of headless, gui, separate");
    }
}

func testConsoleVerbs() {
    def answers as map of string to string init baseAnswers();
    $answers["IConsole_powerDown"] = "returnval=" + PROGRESS_REF;
    for (def m in ["powerButton", "pause", "resume", "reset"]) {
        $answers["IConsole_" + $m] = "";
    }
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    powerOff($s, "web");
    acpiShutdown($s, "web");
    pause($s, "web");
    resume($s, "web");
    reset($s, "web");
    def seen as list of string init stopFake($f);
    def calls as string init work($seen);
    testing.assertContains(
        $calls,
        "IMachine_lockMachine|_this=" + MACHINE_REF + "|session=" + SESSION_REF +
            "|lockType=Shared;ISession_getConsole|_this=" + SESSION_REF +
            ";IConsole_powerDown|_this=" +
            CONSOLE_REF + ";IProgress_getCompleted");
    for (def m in ["powerButton", "pause", "resume", "reset"]) {
        testing.assertContains($calls, "IConsole_" + $m + "|_this=" + CONSOLE_REF);
    }
    testing.assertEqual(strings.count($calls, "ISession_unlockMachine"), 5);
    testing.assertEqual(
        strings.count(strings.join($seen, ";"), "IManagedObjectRef_release|_this=" + CONSOLE_REF),
        5);
}

func testAFailedConsoleCallStillUnlocksAndReleases() {
    def answers as map of string to string init baseAnswers();
    $answers["IConsole_pause"] = "!fault -2135228409 The machine is not running";
    def f as Fake init startFake($answers);
    try {
        pause(fakeSession($f), "web");
        missed("not running");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: pause web: The machine is not running (VBOX_E_INVALID_OBJECT_STATE)");
    }
    def seen as list of string init stopFake($f);
    testing.assertContains(work($seen), "ISession_unlockMachine|_this=" + SESSION_REF);
    testing.assertEqual(released($seen), SESSION_REF + "," + MACHINE_REF + "," + CONSOLE_REF);
}

func testSaveState() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_saveState"] = "returnval=" + PROGRESS_REF;
    def f as Fake init startFake($answers);
    saveState(fakeSession($f), "web");
    def seen as list of string init stopFake($f);
    testing.assertContains(
        work($seen),
        "ISession_getMachine|_this=" + SESSION_REF + ";IMachine_saveState|_this=" +
            MUTABLE_REF);
    testing.assertEqual(
        released($seen),
        SESSION_REF + "," + MACHINE_REF + "," + PROGRESS_REF + "," + MUTABLE_REF);
}
