# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualboxws - white-box tests for the core topic, and the fake web service
# every topic's tests share. Spliced into virtualboxws_test.j via include.

# references the fake hands out
def const VBOX_REF as string init "00000000000000a1-0000000000000001";
def const SESSION_REF as string init "00000000000000a1-0000000000000002";
def const MACHINE_REF as string init "00000000000000a1-0000000000000003";
def const PROGRESS_REF as string init "00000000000000a1-0000000000000004";
def const CONSOLE_REF as string init "00000000000000a1-0000000000000005";
def const MUTABLE_REF as string init "00000000000000a1-0000000000000006";
def const OTHER_REF as string init "00000000000000a1-0000000000000007";
def const ERRINFO_REF as string init "00000000000000a1-0000000000000008";

# OBJECT_NOT_FOUND as the signed 32-bit decimal vboxwebsrv sends
def const NOT_FOUND as string init "-2135228415";

/**
 * A running fake web service.
 *
 * @field srv {httpd.Server} the server
 * @field url {string} its URL
 * @field t {task of list of string} the task serving it; its result is every request seen
 */
def struct Fake {
    srv as httpd.Server,
    url as string,
    t as task of list of string
};

/**
 * Mark a call that should have thrown.
 *
 * @param what {string} what got through
 * @throws {Error} always, with `kind` `"missed"`
 */
func missed(what as string) {
    throw Error{kind: "missed", message: $what};
}

/**
 * Start a fake web service. Each answer is looked up by the method, most
 * specific first: `method@<_this>#<n>` (the n-th call of the method on that
 * object), `method@<_this>`, `method#<n>`, `method`. An answer is lines of
 * `name=value` (the reply's elements, in order; `""` for an empty reply), or
 * `!fault <code> <text>` (a RuntimeFault with that decimal result code),
 * `!invalid` (an InvalidObjectFault), `!bare <text>` (a fault without
 * detail), `!raw <status> <body>`, `!sleep <ms>` (then an empty reply). A
 * method with no answer gets an E_FAIL fault.
 *
 * @param answers {map of string to string} the answers
 * @return {Fake} the service
 */
func startFake(answers as map of string to string) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of string init spawn {
        return serveSoap($srv, $answers);
    };
    return Fake{srv: $srv, url: "http://" + httpd.address($srv) + "/", t: $t};
}

/**
 * Stop a fake and return what it saw.
 *
 * @param f {Fake} the service
 * @return {list of string} each request as `method|name=value|...`
 */
func stopFake(f as Fake) {
    httpd.shutdown($f.srv);
    return task.wait($f.t);
}

/**
 * A session on a fake, as `logon` would return it for VirtualBox 7.1.4.
 *
 * @param f {Fake} the service
 * @return {Session} the session
 */
func fakeSession(f as Fake) {
    return Session{config: endpoint($f.url), vbox: VBOX_REF, version: "7.1.4", major: 7, minor: 1};
}

/**
 * Serve requests until the server shuts down.
 *
 * @param srv {httpd.Server} the server
 * @param answers {map of string to string} the answers
 * @return {list of string} each request as `method|name=value|...`
 */
func serveSoap(srv as httpd.Server, answers as map of string to string) {
    def seen as list of string init [];
    def counts as map of string to int init {};
    while (true) {
        def req as httpd.Request;
        try {
            $req = httpd.accept($srv);
        } catch (e) {
            return $seen;
        }
        def body as string init convert.stringFromBytes("utf-8", httpd.body($req));
        def parts as list of string init summary($body);
        def method as string init $parts[0];
        def this as string init "";
        for (def p in $parts) {
            if (strings.startsWith($p, "_this=")) {
                $this = strings.substring($p, 6);
            }
        }
        if (httpd.header($req, "SOAPAction") != "\"\"" or
            not strings.startsWith(httpd.header($req, "Content-Type"), "text/xml")) {
            $parts[] = "!headers";
        }
        $seen[] = strings.join($parts, "|");
        def n as int init 1;
        if (maps.has($counts, $method)) {
            $n = $counts[$method] + 1;
        }
        $counts[$method] = $n;
        def spec as string init "!fault -2147467259 no answer scripted for " + $method;
        for (def key in [
            $method + "@" + $this + "#" + convert.toString($n),
            $method + "@" + $this,
            $method + "#" + convert.toString($n),
            $method
        ]) {
            if (maps.has($answers, $key)) {
                $spec = $answers[$key];
                break;
            }
        }
        answerSpec($req, $method, $spec);
    }
    return $seen;
}

/**
 * A request's method and parameters.
 *
 * @param body {string} the SOAP envelope
 * @return {list of string} the method, then `name=value` per parameter; `!notsoap` if it is not an envelope with one call in VirtualBox's namespace
 */
func summary(body as string) {
    def doc as xml.Value init xml.decode($body);
    def ns as map of string to string init {"s": SOAP_NS};
    def calls as list of xml.Value init xml.children(xml.get($doc, "s:Body", $ns));
    if (len($calls) != 1 or xml.namespace($calls[0]) != VBOX_NS) {
        return ["!notsoap"];
    }
    def out as list of string init [xml.localName($calls[0])];
    for (def c in xml.children($calls[0])) {
        if (xml.namespace($c) != "") {
            $out[] = "!qualified";
        }
        $out[] = xml.localName($c) + "=" + xml.text($c);
    }
    return $out;
}

/**
 * Answer a request from a spec.
 *
 * @param req {httpd.Request} the request
 * @param method {string} its method
 * @param spec {string} the answer, as `startFake` describes
 */
func answerSpec(req as httpd.Request, method as string, spec as string) {
    httpd.setHeader($req, "Content-Type", "text/xml; charset=utf-8");
    if (strings.startsWith($spec, "!raw ")) {
        def rest as string init strings.substring($spec, 5);
        def sp as int init strings.indexOf($rest, " ");
        httpd.respond(
            $req,
            convert.toInt(strings.substring($rest, 0, $sp)),
            strings.substring($rest, $sp + 1));
        return;
    }
    if (strings.startsWith($spec, "!sleep ")) {
        time.sleep(time.fromMilliseconds(convert.toInt(strings.substring($spec, 7))));
        $spec = "";
    }
    def env as string init "<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"" + SOAP_NS + "\" xmlns:vbox=\"" +
        VBOX_NS +
        "\"><SOAP-ENV:Body>";
    def end as string init "</SOAP-ENV:Body></SOAP-ENV:Envelope>";
    if (strings.startsWith($spec, "!fault ")) {
        def rest as string init strings.substring($spec, 7);
        def sp as int init strings.indexOf($rest, " ");
        def code as string init strings.substring($rest, 0, $sp);
        def text as string init strings.substring($rest, $sp + 1);
        httpd.respond(
            $req,
            500,
            $env + "<SOAP-ENV:Fault><faultcode>SOAP-ENV:Client</faultcode><faultstring>" +
                escaped("VirtualBox error: apirc=0x80bb0001 " + $text + " (0x80bb0001)") +
                "</faultstring><detail><vbox:RuntimeFault><resultCode>" + $code +
                "</resultCode><returnval>" +
                ERRINFO_REF + "</returnval></vbox:RuntimeFault></detail></SOAP-ENV:Fault>" + $end);
        return;
    }
    if ($spec == "!invalid") {
        httpd.respond(
            $req,
            500,
            $env + "<SOAP-ENV:Fault><faultcode>SOAP-ENV:Client</faultcode><faultstring>" +
                "VirtualBox error: Invalid managed object reference \"" + VBOX_REF +
                "\"</faultstring><detail>" +
                "<vbox:InvalidObjectFault><badObjectID>" + VBOX_REF +
                "</badObjectID></vbox:InvalidObjectFault>" +
                "</detail></SOAP-ENV:Fault>" + $end);
        return;
    }
    if (strings.startsWith($spec, "!bare ")) {
        httpd.respond(
            $req,
            500,
            $env + "<SOAP-ENV:Fault><faultcode>SOAP-ENV:Server</faultcode><faultstring>" +
                escaped(strings.substring($spec, 6)) + "</faultstring></SOAP-ENV:Fault>" + $end);
        return;
    }
    def inner as string init "";
    for (def line in strings.split($spec, "\n")) {
        if ($line == "") {
            continue;
        }
        def eq as int init strings.indexOf($line, "=");
        def name as string init strings.substring($line, 0, $eq);
        $inner = $inner + "<" + $name + ">" + escaped(strings.substring($line, $eq + 1)) + "</" +
            $name + ">";
    }
    httpd.respond(
        $req,
        200,
        $env + "<vbox:" + $method + "Response>" + $inner + "</vbox:" + $method + "Response>" +
            $end);
}

/**
 * Text escaped for XML.
 *
 * @param s {string} the text
 * @return {string} the escaped text
 */
func escaped(s as string) {
    return strings.replace(
        strings.replace(strings.replace($s, "&", "&amp;"), "<", "&lt;"),
        ">",
        "&gt;");
}

/**
 * The answers every machine operation needs: the machine, a session object,
 * a session machine, a console, and a progress that is done.
 *
 * @return {map of string to string} the answers
 */
func baseAnswers() {
    return {
        "IVirtualBox_findMachine": "returnval=" + MACHINE_REF,
        "IWebsessionManager_getSessionObject": "returnval=" + SESSION_REF,
        "IMachine_lockMachine": "",
        "ISession_unlockMachine": "",
        "ISession_getMachine": "returnval=" + MUTABLE_REF,
        "ISession_getConsole": "returnval=" + CONSOLE_REF,
        "IManagedObjectRef_release": "",
        "IProgress_getCompleted": "returnval=true",
        "IProgress_getResultCode": "returnval=0",
        "IProgress_waitForCompletion": ""
    };
}

/**
 * The requests that are not releases, joined by `;`.
 *
 * @param seen {list of string} the requests
 * @return {string} the others
 */
func work(seen as list of string) {
    def out as list of string init [];
    for (def r in $seen) {
        if (not strings.startsWith($r, "IManagedObjectRef_release")) {
            $out[] = $r;
        }
    }
    return strings.join($out, ";");
}

/**
 * The references released, sorted.
 *
 * @param seen {list of string} the requests
 * @return {string} the references, joined by `,`
 */
func released(seen as list of string) {
    def out as list of string init [];
    for (def r in $seen) {
        if (strings.startsWith($r, "IManagedObjectRef_release|_this=")) {
            $out[] = strings.substring($r, len("IManagedObjectRef_release|_this="));
        }
    }
    return strings.join(lists.sort($out), ",");
}

func testEndpointChecksTheUrl() {
    testing.assertEqual(endpoint("https://vmhost:18083/").url, "https://vmhost:18083/");
    testing.assertEqual(endpoint(DEFAULT_URL).timeoutMs, DEFAULT_TIMEOUT_MS);
    testing.assertEqual(endpoint("http://127.0.0.1:18083/").maxBytes, DEFAULT_MAX_BYTES);
    for (def bad in [
        "ftp://vmhost/",
        "https://",
        "https://admin:pw@vmhost/",
        "https://vmhost/?x=1",
        "https://vmhost/#top",
        "https://vm host/",
        "vmhost:18083",
        "https://vmhost:port/"
    ]) {
        try {
            endpoint($bad);
            missed($bad);
        } catch (e) {
            testing.assertEqual($e.kind, "virtualboxws");
        }
    }
    try {
        endpoint("http://vmhost:18083/");
        missed("plain http");
    } catch (e) {
        testing.assertContains(
            $e.message,
            "would send the password in clear: use https, or allow it with withPlainHttp");
    }
    def c as Config init endpoint("https://vmhost:18083/");
    $c.url = "http://vmhost:18083/";
    $c = withPlainHttp($c);
    checkUrl($c);
}

func testWithFunctionsCheckTheirValues() {
    def c as Config init endpoint(DEFAULT_URL);
    testing.assertEqual(withTimeout($c, 5000).timeoutMs, 5000);
    testing.assertEqual(withLongTimeout($c, 9000).longTimeoutMs, 9000);
    testing.assertEqual(withMaxBytes($c, 65536).maxBytes, 65536);
    testing.assertTrue(withTls($c, http.TlsOptions{skipVerify: true}).tls.skipVerify);
    for (def ms in [999, 86400001]) {
        try {
            withTimeout($c, $ms);
            missed("timeout");
        } catch (e) {
            testing.assertContains($e.message, "the timeout must be 1000 to 86400000");
        }
        try {
            withLongTimeout($c, $ms);
            missed("long timeout");
        } catch (e) {
            testing.assertContains($e.message, "the long timeout must be");
        }
    }
    try {
        withMaxBytes($c, 1024);
        missed("cap");
    } catch (e) {
        testing.assertContains($e.message, "the reply cap must be 65536 to 67108864");
    }
}

func testLogonChecksTheVersion() {
    def f as Fake init startFake({
        "IWebsessionManager_logon": "returnval=" + VBOX_REF,
        "IVirtualBox_getVersion": "returnval=7.0.20_Ubuntu"
    });
    def s as Session init logon(endpoint($f.url), "ada", "s3cret <&>");
    def seen as list of string init stopFake($f);
    testing.assertEqual($s.vbox, VBOX_REF);
    testing.assertEqual($s.version, "7.0.20_Ubuntu");
    testing.assertEqual($s.major, 7);
    testing.assertEqual($s.minor, 0);
    testing.assertEqual(
        strings.join($seen, ";"),
        "IWebsessionManager_logon|username=ada|password=s3cret <&>;IVirtualBox_getVersion|_this=" +
            VBOX_REF);
}

func testLogonRefusals() {
    def f as Fake init startFake({"IWebsessionManager_logon": "!bare Authentication failed"});
    try {
        logon(endpoint($f.url), "ada", "wrong");
        missed("refused");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: logon refused for \"ada\": Authentication failed");
        testing.assertEqual($e.reason, "fault");
    }
    stopFake($f);
    $f = startFake({
        "IWebsessionManager_logon": "returnval=" + VBOX_REF,
        "IVirtualBox_getVersion": "returnval=6.1.50",
        "IWebsessionManager_logoff": ""
    });
    try {
        logon(endpoint($f.url), "ada", "pw");
        missed("6.1");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: VirtualBox 6.1.50 is too old; the deck needs VirtualBox 7 or newer");
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual($seen[2], "IWebsessionManager_logoff|refIVirtualBox=" + VBOX_REF);
    $f = startFake({"IWebsessionManager_logon": "returnval=not-a-ref"});
    try {
        logon(endpoint($f.url), "ada", "pw");
        missed("no ref");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: logon: the service returned no object reference: \"not-a-ref\"");
    }
    stopFake($f);
    try {
        logon(endpoint($f.url), "ada", "pw");
        missed("closed");
    } catch (e) {
        testing.assertContains(
            $e.message,
            "virtualboxws: logon: cannot reach \"" + $f.url + "\": ");
    }
    try {
        logon(endpoint($f.url), "ada\n", "pw");
        missed("newline");
    } catch (e) {
        testing.assertEqual($e.message, "virtualboxws: the user holds a control character");
    }
}

func testLogoffToleratesAnEndedSession() {
    def f as Fake init startFake({
        "IWebsessionManager_logoff#1": "",
        "IWebsessionManager_logoff#2": "!invalid",
        "IWebsessionManager_logoff#3": "!fault -2147467259 broken"
    });
    def s as Session init fakeSession($f);
    logoff($s);
    logoff($s);
    try {
        logoff($s);
        missed("broken");
    } catch (e) {
        testing.assertEqual($e.message, "virtualboxws: logoff: broken (E_FAIL)");
    }
    testing.assertEqual(len(stopFake($f)), 3);
}

func testFaultsCarryTextAndCode() {
    def f as Fake init startFake({
        "IVirtualBox_findMachine": "!fault " + NOT_FOUND +
            " Could not find a registered machine named 'ghost'"
    });
    try {
        info(fakeSession($f), "ghost");
        missed("ghost");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: findMachine ghost: Could not find a registered machine named 'ghost' (VBOX_E_OBJECT_NOT_FOUND)");
        testing.assertEqual(errorCode($e), "VBOX_E_OBJECT_NOT_FOUND");
        # a VirtualboxwsError: the reason, the code and the HTTP status as fields
        testing.assertEqual($e.reason, "fault");
        testing.assertEqual($e.code, "VBOX_E_OBJECT_NOT_FOUND");
        testing.assertTrue($e.status > 0);
    }
    stopFake($f);
}

func testCodeNames() {
    testing.assertEqual(codeName(NOT_FOUND), "VBOX_E_OBJECT_NOT_FOUND");
    testing.assertEqual(codeName("-2135228397"), "VBOX_E_RECORDING_ERROR");
    testing.assertEqual(codeName("-2135228396"), "0x80BB0014");
    testing.assertEqual(codeName("-2147467259"), "E_FAIL");
    testing.assertEqual(codeName("-2147024809"), "E_INVALIDARG");
    testing.assertEqual(codeName("2159738881"), "VBOX_E_OBJECT_NOT_FOUND");
    testing.assertEqual(codeName("-2135228416"), "0x80BB0000");
    testing.assertEqual(codeName("12"), "0x0000000C");
    testing.assertEqual(codeName("nope"), "");
}

func testRepliesThatAreNotSoap() {
    def f as Fake init startFake({
        "IVirtualBox_getVersion#1": "!raw 200 <html><body>hi</body></html>",
        "IVirtualBox_getVersion#2": "!raw 502 Bad Gateway",
        "IVirtualBox_getVersion#3": '!raw 200 {"a": 1}',
        "IVirtualBox_getVersion#4": "returnval=x"
    });
    def s as Session init fakeSession($f);
    def expect as list of string init [
        "virtualboxws: IVirtualBox_getVersion: the reply is not a SOAP envelope (HTTP 200)",
        "virtualboxws: IVirtualBox_getVersion: HTTP 502 Bad Gateway",
        "virtualboxws: IVirtualBox_getVersion: the reply is not XML: "
    ];
    for (def msg in $expect) {
        try {
            call($s, "IVirtualBox_getVersion", {"_this": [VBOX_REF]});
            missed($msg);
        } catch (e) {
            testing.assertContains($e.message, $msg);
        }
    }
    testing.assertEqual(
        call($s, "IVirtualBox_getVersion", {"_this": [VBOX_REF]})["returnval"][0],
        "x");
    def seen as list of string init stopFake($f);
    testing.assertFalse(strings.contains(strings.join($seen, ";"), "!"));
}

func testAReplyForAnotherMethodIsRefused() {
    def body as string init "<s:Envelope xmlns:s=\"" + SOAP_NS + "\" xmlns:v=\"" + VBOX_NS +
        "\"><s:Body><v:IMachine_getNameResponse/></s:Body></s:Envelope>";
    try {
        reply(
            http.Response{status: 200, statusText: "OK", headers: {}, body: $body},
            "IMachine_getId",
            "getId");
        missed("other method");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: getId: the reply is \"IMachine_getNameResponse\", not IMachine_getIdResponse");
    }
}

func testARequestPastItsDeadline() {
    def f as Fake init startFake({"IVirtualBox_getVersion": "!sleep 3000"});
    def s as Session init fakeSession($f);
    $s.config = withTimeout($s.config, 1000);
    def started as time.Time init time.now();
    try {
        call($s, "IVirtualBox_getVersion", {"_this": [VBOX_REF]});
        missed("slow");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: IVirtualBox_getVersion: no answer from \"" + $f.url +
                "\" within 1000 ms");
        testing.assertEqual($e.reason, "timeout");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    stopFake($f);
}

func testAReplyOverTheCap() {
    def f as Fake init startFake({
        "IVirtualBox_getVersion": "returnval=" + strings.repeat("x", 70000)
    });
    def s as Session init fakeSession($f);
    $s.config = withMaxBytes($s.config, 65536);
    try {
        call($s, "IVirtualBox_getVersion", {"_this": [VBOX_REF]});
        missed("big");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: IVirtualBox_getVersion: the reply is over 65536 bytes");
        testing.assertEqual($e.kind, "limit");
    }
    stopFake($f);
}

func testCallChecksNamesAndPassesArrays() {
    def f as Fake init startFake({
        "IMachine_setExtraData": "",
        "IAppliance_getMachines": "returnval=a\nreturnval=b"
    });
    def s as Session init fakeSession($f);
    call($s, "IMachine_setExtraData", {"_this": [MACHINE_REF], "key": ["k"], "value": ["<v & w>"]});
    def r as map of string to list of string init call(
        $s,
        "IAppliance_getMachines",
        {"_this": [OTHER_REF], "options": ["KeepAllMACs", "ImportToVDI"]});
    testing.assertEqual(strings.join($r["returnval"], ","), "a,b");
    for (def bad in ["getName", "IMachine.getName", "IMachine_get Name", "I_x"]) {
        try {
            call($s, $bad, {});
            missed($bad);
        } catch (e) {
            testing.assertContains($e.message, "the method must be Interface_method");
        }
    }
    try {
        call($s, "IMachine_getName", {"a b": ["x"]});
        missed("param");
    } catch (e) {
        testing.assertContains($e.message, "a parameter name must be an XML name");
    }
    try {
        call($s, "IMachine_getName", {"_this": ["a\u0001b"]});
        missed("control");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: IMachine_getName: a parameter holds a character XML cannot carry");
    }
    testing.assertEqual(
        strings.join(stopFake($f), ";"),
        "IMachine_setExtraData|_this=" + MACHINE_REF +
            "|key=k|value=<v & w>;IAppliance_getMachines|_this=" +
            OTHER_REF + "|options=KeepAllMACs|options=ImportToVDI");
}

func testReleaseRef() {
    def f as Fake init startFake({"IManagedObjectRef_release": ""});
    def s as Session init fakeSession($f);
    releaseRef($s, OTHER_REF);
    try {
        releaseRef($s, "x");
        missed("x");
    } catch (e) {
        testing.assertContains($e.message, "no object reference");
    }
    testing.assertEqual(released(stopFake($f)), OTHER_REF);
}

func testWaitForPollsAndReportsTheError() {
    def answers as map of string to string init baseAnswers();
    $answers["IProgress_getCompleted#1"] = "returnval=false";
    $answers["IProgress_getCompleted#2"] = "returnval=false";
    $answers["IProgress_getResultCode"] = "returnval=" + NOT_FOUND;
    $answers["IProgress_getErrorInfo"] = "returnval=" + ERRINFO_REF;
    $answers["IVirtualBoxErrorInfo_getText"] = "returnval=The disk is gone";
    def f as Fake init startFake($answers);
    try {
        waitFor(fakeSession($f), PROGRESS_REF, 60000, "clone x");
        missed("failed progress");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: clone x: The disk is gone (VBOX_E_OBJECT_NOT_FOUND)");
    }
    def seen as list of string init stopFake($f);
    testing.assertEqual(
        work($seen),
        "IProgress_getCompleted|_this=" + PROGRESS_REF + ";IProgress_waitForCompletion|_this=" +
            PROGRESS_REF +
            "|timeout=1000;IProgress_getCompleted|_this=" + PROGRESS_REF +
            ";IProgress_waitForCompletion|_this=" +
            PROGRESS_REF + "|timeout=1000;IProgress_getCompleted|_this=" + PROGRESS_REF +
            ";IProgress_getResultCode|_this=" + PROGRESS_REF + ";IProgress_getErrorInfo|_this=" +
            PROGRESS_REF +
            ";IVirtualBoxErrorInfo_getText|_this=" + ERRINFO_REF);
    testing.assertEqual(released($seen), PROGRESS_REF + "," + ERRINFO_REF);
}

func testWaitForCancelsAtTheDeadline() {
    def answers as map of string to string init baseAnswers();
    $answers["IProgress_getCompleted"] = "returnval=false";
    $answers["IProgress_waitForCompletion"] = "!sleep 300";
    $answers["IProgress_cancel"] = "";
    def f as Fake init startFake($answers);
    def started as time.Time init time.now();
    try {
        waitFor(fakeSession($f), PROGRESS_REF, 500, "import a.ova");
        missed("slow progress");
    } catch (e) {
        testing.assertEqual(
            $e.message,
            "virtualboxws: import a.ova: not done after 500 ms, cancelled");
    }
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $started)) < 2500);
    def seen as list of string init stopFake($f);
    testing.assertContains(work($seen), "IProgress_cancel|_this=" + PROGRESS_REF);
    testing.assertEqual(released($seen), PROGRESS_REF);
}

func testShownCleans() {
    testing.assertEqual(shown("a\u0001b‮c"), "\"a?b?c\"");
    testing.assertEqual(len(shown(strings.repeat("x", 300))), 205);
}
