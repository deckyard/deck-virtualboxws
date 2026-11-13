# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualboxws - white-box tests for the snapshots topic. Spliced into
# virtualboxws_test.j via include.

# snapshot references for the tree test
def const SNAP_ROOT as string init "00000000000000a1-0000000000000011";
def const SNAP_A as string init "00000000000000a1-0000000000000012";
def const SNAP_B as string init "00000000000000a1-0000000000000013";
def const SNAP_CUR as string init "00000000000000a1-0000000000000014";

func testSnapshotsWalkTheTree() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getSnapshotCount"] = "returnval=3";
    $answers["IMachine_getCurrentSnapshot"] = "returnval=" + SNAP_CUR;
    $answers["ISnapshot_getId@" + SNAP_CUR] = "returnval=id-a";
    $answers["IMachine_findSnapshot"] = "returnval=" + SNAP_ROOT;
    $answers["ISnapshot_getId@" + SNAP_ROOT] = "returnval=id-root";
    $answers["ISnapshot_getName@" + SNAP_ROOT] = "returnval=installed";
    $answers["ISnapshot_getDescription@" + SNAP_ROOT] = "returnval=fresh";
    $answers["ISnapshot_getChildren@" + SNAP_ROOT] = "returnval=" + SNAP_A + "\nreturnval=" + SNAP_B;
    $answers["ISnapshot_getId@" + SNAP_A] = "returnval=id-a";
    $answers["ISnapshot_getName@" + SNAP_A] = "returnval=patched";
    $answers["ISnapshot_getDescription@" + SNAP_A] = "returnval=";
    $answers["ISnapshot_getChildren@" + SNAP_A] = "";
    $answers["ISnapshot_getId@" + SNAP_B] = "returnval=id-b";
    $answers["ISnapshot_getName@" + SNAP_B] = "returnval=branch";
    $answers["ISnapshot_getDescription@" + SNAP_B] = "returnval=";
    $answers["ISnapshot_getChildren@" + SNAP_B] = "";
    def f as Fake init startFake($answers);
    def found as list of Snapshot init snapshots(fakeSession($f), "web");
    def seen as list of string init stopFake($f);
    testing.assertEqual(len($found), 3);
    testing.assertEqual($found[0].name, "installed");
    testing.assertEqual($found[0].depth, 0);
    testing.assertEqual($found[0].description, "fresh");
    testing.assertFalse($found[0].current);
    testing.assertEqual($found[1].name, "patched");
    testing.assertEqual($found[1].depth, 1);
    testing.assertTrue($found[1].current);
    testing.assertEqual($found[2].name, "branch");
    testing.assertEqual($found[2].uuid, "id-b");
    testing.assertContains(
        work($seen),
        "IMachine_findSnapshot|_this=" + MACHINE_REF + "|nameOrId=");
    testing.assertEqual(
        released($seen),
        MACHINE_REF + "," + SNAP_ROOT + "," + SNAP_A + "," + SNAP_B + "," + SNAP_CUR);
}

func testNoSnapshots() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getSnapshotCount"] = "returnval=0";
    def f as Fake init startFake($answers);
    testing.assertEqual(len(snapshots(fakeSession($f), "web")), 0);
    stopFake($f);
}

func testTakeRestoreDeleteSnapshot() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_takeSnapshot"] = "id=d2e3f4a5-b6c7-4d8e-9f0a-1b2c3d4e5f6a\nreturnval=" +
        PROGRESS_REF;
    $answers["IMachine_findSnapshot"] = "returnval=" + OTHER_REF;
    $answers["IMachine_restoreSnapshot"] = "returnval=" + PROGRESS_REF;
    $answers["IMachine_deleteSnapshot"] = "returnval=" + PROGRESS_REF;
    $answers["ISnapshot_getId"] = "returnval=d2e3f4a5-b6c7-4d8e-9f0a-1b2c3d4e5f6a";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    testing.assertEqual(
        takeSnapshot($s, "web", "patched", "after <the> upgrade"),
        "d2e3f4a5-b6c7-4d8e-9f0a-1b2c3d4e5f6a");
    restoreSnapshot($s, "web", "installed");
    deleteSnapshot($s, "web", "patched");
    def calls as string init work(stopFake($f));
    testing.assertContains(
        $calls,
        "IMachine_takeSnapshot|_this=" + MUTABLE_REF +
            "|name=patched|description=after <the> upgrade|pause=true");
    testing.assertContains(
        $calls,
        "lockType=Write;ISession_getMachine|_this=" + SESSION_REF +
            ";IMachine_findSnapshot|_this=" + MUTABLE_REF +
            "|nameOrId=installed;IMachine_restoreSnapshot|_this=" +
            MUTABLE_REF + "|snapshot=" + OTHER_REF);
    testing.assertContains(
        $calls,
        "IMachine_deleteSnapshot|_this=" + MUTABLE_REF +
            "|id=d2e3f4a5-b6c7-4d8e-9f0a-1b2c3d4e5f6a");
    try {
        takeSnapshot($s, "web", "", "");
        missed("empty");
    } catch (e) {
        testing.assertContains($e.message, "the snapshot name is empty");
    }
}

func testCloneOn71PassesThePlatform() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_getPlatform"] = "returnval=" + OTHER_REF;
    $answers["IPlatform_getArchitecture"] = "returnval=x86";
    $answers["IMachine_getOSTypeId"] = "returnval=Ubuntu_64";
    $answers["IVirtualBox_createMachine"] = "returnval=" + MUTABLE_REF;
    $answers["IMachine_cloneTo"] = "returnval=" + PROGRESS_REF;
    $answers["IVirtualBox_registerMachine"] = "";
    $answers["IMachine_getId"] = "returnval=11111111-2222-4333-8444-555555555555";
    def f as Fake init startFake($answers);
    testing.assertEqual(
        clone(fakeSession($f), "template", "web2"),
        "11111111-2222-4333-8444-555555555555");
    def seen as list of string init stopFake($f);
    def calls as string init work($seen);
    testing.assertContains(
        $calls,
        "IVirtualBox_createMachine|_this=" + VBOX_REF +
            "|settingsFile=|name=web2|platform=x86|osTypeId=Ubuntu_64|flags=|cipher=|passwordId=|password=");
    testing.assertContains(
        $calls,
        "IMachine_cloneTo|_this=" + MACHINE_REF + "|target=" + MUTABLE_REF +
            "|mode=MachineState;");
    testing.assertContains(
        $calls,
        "IVirtualBox_registerMachine|_this=" + VBOX_REF + "|machine=" + MUTABLE_REF);
    testing.assertEqual(
        released($seen),
        MACHINE_REF + "," + PROGRESS_REF + "," + MUTABLE_REF + "," + OTHER_REF);
}

func testLinkedCloneOn70() {
    def answers as map of string to string init baseAnswers();
    $answers["IMachine_findSnapshot"] = "returnval=" + SNAP_A;
    $answers["ISnapshot_getMachine"] = "returnval=" + OTHER_REF;
    $answers["IMachine_getOSTypeId"] = "returnval=Debian_64";
    $answers["IVirtualBox_createMachine"] = "returnval=" + MUTABLE_REF;
    $answers["IMachine_cloneTo"] = "returnval=" + PROGRESS_REF;
    $answers["IVirtualBox_registerMachine"] = "";
    $answers["IMachine_getId"] = "returnval=11111111-2222-4333-8444-555555555555";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    $s.minor = 0;
    linkedClone($s, "template", "base", "ci-42");
    def calls as string init work(stopFake($f));
    testing.assertContains(
        $calls,
        "IVirtualBox_createMachine|_this=" + VBOX_REF +
            "|settingsFile=|name=ci-42|osTypeId=Debian_64|flags=");
    testing.assertFalse(strings.contains($calls, "getPlatform"));
    testing.assertContains(
        $calls,
        "IMachine_cloneTo|_this=" + OTHER_REF + "|target=" + MUTABLE_REF +
            "|mode=MachineState|options=Link");
}

func testImportRenamesTheFirstMachine() {
    def answers as map of string to string init baseAnswers();
    $answers["IVirtualBox_createAppliance"] = "returnval=" + OTHER_REF;
    $answers["IAppliance_read"] = "returnval=" + PROGRESS_REF;
    $answers["IAppliance_interpret"] = "";
    $answers["IAppliance_getVirtualSystemDescriptions"] = "returnval=" + MUTABLE_REF;
    $answers["IVirtualSystemDescription_getDescription"] = "types=OS\ntypes=Name\ntypes=CPU\nrefs=\nrefs=\nrefs=\nOVFValues=\nOVFValues=\nOVFValues=\n" +
        "VBoxValues=Debian_64\nVBoxValues=debian-12\nVBoxValues=2\n" +
        "extraConfigValues=\nextraConfigValues=\nextraConfigValues=";
    $answers["IVirtualSystemDescription_setFinalValues"] = "";
    $answers["IAppliance_importMachines"] = "returnval=" + PROGRESS_REF;
    $answers["IAppliance_getMachines"] = "returnval=11111111-2222-4333-8444-555555555555";
    def f as Fake init startFake($answers);
    def s as Session init fakeSession($f);
    def ids as list of string init importAs($s, "/srv/images/debian.ova", "build-1");
    testing.assertEqual(strings.join($ids, ","), "11111111-2222-4333-8444-555555555555");
    testing.assertEqual(len(importOva($s, "/srv/images/debian.OVF")), 1);
    def calls as string init work(stopFake($f));
    testing.assertContains(
        $calls,
        "IAppliance_read|_this=" + OTHER_REF + "|file=/srv/images/debian.ova");
    testing.assertContains(
        $calls,
        "IVirtualSystemDescription_setFinalValues|_this=" + MUTABLE_REF +
            "|enabled=true|enabled=true|enabled=true|VBoxValues=Debian_64|VBoxValues=build-1|VBoxValues=2|" +
            "extraConfigValues=|extraConfigValues=|extraConfigValues=");
    testing.assertEqual(strings.count($calls, "setFinalValues"), 1);
    for (def bad in ["/srv/images/debian.zip", ""]) {
        try {
            importOva($s, $bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualboxws");
        }
    }
}

func testExport() {
    def answers as map of string to string init baseAnswers();
    $answers["IVirtualBox_createAppliance"] = "returnval=" + OTHER_REF;
    $answers["IMachine_exportTo"] = "returnval=" + MUTABLE_REF;
    $answers["IAppliance_write"] = "returnval=" + PROGRESS_REF;
    def f as Fake init startFake($answers);
    exportOva(fakeSession($f), "web", "/srv/out/web.ova");
    def seen as list of string init stopFake($f);
    testing.assertContains(
        work($seen),
        "IMachine_exportTo|_this=" + MACHINE_REF + "|appliance=" + OTHER_REF +
            "|location=/srv/out/web.ova;IAppliance_write|_this=" + OTHER_REF +
            "|format=ovf-2.0|path=/srv/out/web.ova");
    testing.assertEqual(
        released($seen),
        MACHINE_REF + "," + PROGRESS_REF + "," + MUTABLE_REF + "," + OTHER_REF);
}
