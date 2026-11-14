# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

# virtualboxws - core: the endpoint, the web session, the SOAP exchange, faults
# and their codes, object references, progress objects, and `call`. Spliced
# into virtualboxws.j via include.

/** The web service's address when it runs on this machine with its defaults. */
export def const DEFAULT_URL as string init "http://localhost:18083/";

/** How long an ordinary request may take, in milliseconds: one minute. */
export def const DEFAULT_TIMEOUT_MS as int init 60000;

/** How long a start, power-off, snapshot, clone, import or export may take, in milliseconds: one hour. */
export def const DEFAULT_LONG_TIMEOUT_MS as int init 3600000;

/** The largest reply read, in bytes: 1 MiB, ten times a big host's machine list. */
export def const DEFAULT_MAX_BYTES as int init 1048576;

/** The oldest VirtualBox major version `logon` accepts. */
export def const MIN_MAJOR as int init 7;

# the namespaces of the SOAP 1.1 envelope and of VirtualBox's messages
def const SOAP_NS as string init "http://schemas.xmlsoap.org/soap/envelope/";
def const VBOX_NS as string init "http://www.virtualbox.org/";

# a managed object reference: the web session's id and the object's, in hex
def const REF as string init '^[0-9a-f]{16}-[0-9a-f]{16}$';

# control characters, which no argument holds
def const CONTROL as string init '[\x00-\x1f\x7f-\x9f]';

# what an error message never shows: control characters and the bidi controls
# that reorder a terminal line
def const UNSHOWN as string init '[\x00-\x1f\x7f-\x9f\x{200e}\x{200f}\x{202a}-\x{202e}\x{2066}-\x{2069}]';

# the hosts plain http is allowed to without `withPlainHttp`
def const LOOPBACK as list of string init ["127.0.0.1", "localhost", "[::1]"];

# how long one IProgress_waitForCompletion asks the server to wait, in ms
def const PROGRESS_STEP_MS as int init 1000;

# the longest argument the deck passes on
def const MAX_ARG as int init 4096;

# VirtualBox's own result codes, by their low 16 bits under 0x80BB0000
def const VBOX_CODES as list of string init [
    "",
    "VBOX_E_OBJECT_NOT_FOUND",
    "VBOX_E_INVALID_VM_STATE",
    "VBOX_E_VM_ERROR",
    "VBOX_E_FILE_ERROR",
    "VBOX_E_IPRT_ERROR",
    "VBOX_E_PDM_ERROR",
    "VBOX_E_INVALID_OBJECT_STATE",
    "VBOX_E_HOST_ERROR",
    "VBOX_E_NOT_SUPPORTED",
    "VBOX_E_XML_ERROR",
    "VBOX_E_INVALID_SESSION_STATE",
    "VBOX_E_OBJECT_IN_USE",
    "VBOX_E_PASSWORD_INCORRECT",
    "VBOX_E_MAXIMUM_REACHED",
    "VBOX_E_GSTCTL_GUEST_ERROR",
    "VBOX_E_TIMEOUT",
    "VBOX_E_DND_ERROR",
    "VBOX_E_PLATFORM_ARCH_NOT_SUPPORTED",
    "VBOX_E_RECORDING_ERROR"
];

# the generic COM result codes VirtualBox returns, as hex and name
def const COM_CODES as map of string to string init {
    "0x80004001": "E_NOTIMPL",
    "0x80004002": "E_NOINTERFACE",
    "0x80004003": "E_POINTER",
    "0x80004004": "E_ABORT",
    "0x80004005": "E_FAIL",
    "0x80070005": "E_ACCESSDENIED",
    "0x8007000E": "E_OUTOFMEMORY",
    "0x80070057": "E_INVALIDARG",
    "0x8000FFFF": "E_UNEXPECTED"
};

/**
 * How to reach the web service. Build it with `endpoint` and change it with
 * the `with*` functions.
 *
 * @field url {string} the service's URL, such as `https://vmhost:18083/`
 * @field tls {http.TlsOptions} certificate checks for an `https` URL
 * @field allowPlainHttp {bool} whether a plain `http` URL to another machine is allowed (the password then crosses the network in clear)
 * @field timeoutMs {int} how long an ordinary request may take
 * @field longTimeoutMs {int} how long a long operation may take
 * @field maxBytes {int} the largest reply read
 */
export def struct Config {
    url as string,
    tls as http.TlsOptions,
    allowPlainHttp as bool,
    timeoutMs as int,
    longTimeoutMs as int,
    maxBytes as int
};

/**
 * A web session, from `logon`. Every other call takes one; `logoff` ends it.
 * The service ends a session nobody used for 5 minutes (`vboxwebsrv
 * --timeout`).
 *
 * @field config {Config} how the service is reached
 * @field vbox {string} the session's `IVirtualBox` reference
 * @field version {string} VirtualBox's version, such as `7.1.4`
 * @field major {int} its major version
 * @field minor {int} its minor version
 */
export def struct Session {
    config as Config,
    vbox as string,
    version as string,
    major as int,
    minor as int
};

/**
 * A failed call. Every error of kind `"virtualboxws"` is one, so its fields
 * are safe to read once the kind matches. (A cancelled task stays kind
 * `"cancelled"`.)
 *
 * @field kind {string} always `"virtualboxws"`
 * @field message {string} `virtualboxws: ` and what went wrong
 * @field reason {string} `"fault"` (the service answered with a SOAP fault), `"http"` (an HTTP error without a fault), `"timeout"` (no answer within the deadline, or a long operation not done by it), `"unreachable"` (no connection or no complete reply), `"reply"` (a reply that is not the expected SOAP), `"operation"` (a long operation such as a clone or an import failed; `code` is its result code), or `""` for any other failure (a check before the call, a refused logon's follow-up checks)
 * @field code {string} the fault's code: a `VBOX_E_*` or COM `E_*` name, `0x` and eight hex digits, or `INVALID_OBJECT` for a reference the service no longer knows; `""` when there is none
 * @field status {int} the HTTP status of the reply, 0 when there was none
 */
export def struct VirtualboxwsError {
    kind as string,
    message as string,
    reason as string,
    code as string,
    status as int
};

/**
 * Throw a virtualboxws error.
 *
 * @param message {string} what went wrong, without the `virtualboxws: ` prefix
 * @throws {VirtualboxwsError} kind "virtualboxws", always
 */
func fail(message as string) {
    failWith($message, "", "", 0);
}

/**
 * Throw a virtualboxws error with its reason, code and HTTP status.
 *
 * @param message {string} what went wrong, without the `virtualboxws: ` prefix
 * @param reason {string} see `VirtualboxwsError`
 * @param code {string} the fault's code, `""` for none
 * @param status {int} the HTTP status, 0 for none
 * @throws {VirtualboxwsError} kind "virtualboxws", always
 */
func failWith(message as string, reason as string, code as string, status as int) {
    throw VirtualboxwsError{
        kind: "virtualboxws",
        message: "virtualboxws: " + $message,
        reason: $reason,
        code: $code,
        status: $status
    };
}

/**
 * Text quoted for an error message: at most 200 characters, control and
 * bidi characters as `?`.
 *
 * @param s {string} the text
 * @return {string} the text in double quotes
 */
func shown(s as string) {
    return "\"" + cleaned($s, 200) + "\"";
}

/**
 * Text cut to a length, with control and bidi characters as `?`.
 *
 * @param s {string} the text
 * @param most {int} the longest result, before the `...`
 * @return {string} the cleaned text
 */
func cleaned(s as string, most as int) {
    def t as string init $s;
    if (len($t) > $most) {
        $t = strings.substring($t, 0, $most) + "...";
    }
    return regex.replace(UNSHOWN, $t, "?");
}

# --- configuration ---------------------------------------------------------

/**
 * The web service at a URL, with the default deadlines and reply cap. Plain
 * `http` is accepted for this machine only; see `withPlainHttp`.
 *
 * @param url {string} the service's URL: `https://host:18083/`, or `http://localhost:18083/`
 * @return {Config} the configuration
 * @throws {VirtualboxwsError} kind "virtualboxws" if the URL is not http(s) with a host, holds a login part, a query or a fragment, or is plain http to another machine
 * @example
 *   def c as virtualboxws.Config init virtualboxws.endpoint("https://vmhost:18083/");
 */
export func endpoint(url as string) {
    def c as Config init Config{
        url: $url,
        tls: http.TlsOptions{skipVerify: false},
        allowPlainHttp: false,
        timeoutMs: DEFAULT_TIMEOUT_MS,
        longTimeoutMs: DEFAULT_LONG_TIMEOUT_MS,
        maxBytes: DEFAULT_MAX_BYTES
    };
    checkUrl($c);
    return $c;
}

/**
 * The configuration with certificate options for an `https` URL: a private
 * CA or a pinned self-signed certificate (`caCert`), or, on a trusted LAN
 * only, no check at all (`skipVerify`).
 *
 * @param c {Config} the configuration
 * @param tls {http.TlsOptions} the options
 * @return {Config} the changed copy
 */
export func withTls(c as Config, tls as http.TlsOptions) {
    def out as Config init $c;
    $out.tls = $tls;
    return $out;
}

/**
 * The configuration allowing a plain `http` URL to another machine.
 * `vboxwebsrv` speaks plain http unless it is given a certificate, but then
 * the password `logon` sends, and everything after it, crosses the network
 * in clear: use it on a network you trust, or put TLS in front.
 *
 * @param c {Config} the configuration
 * @return {Config} the changed copy
 */
export func withPlainHttp(c as Config) {
    def out as Config init $c;
    $out.allowPlainHttp = true;
    return $out;
}

/**
 * The configuration with another deadline for ordinary requests.
 *
 * @param c {Config} the configuration
 * @param ms {int} milliseconds, 1000 to 86400000
 * @return {Config} the changed copy
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is out of range
 */
export func withTimeout(c as Config, ms as int) {
    checkRange($ms, 1000, 86400000, "the timeout");
    def out as Config init $c;
    $out.timeoutMs = $ms;
    return $out;
}

/**
 * The configuration with another deadline for the long operations.
 *
 * @param c {Config} the configuration
 * @param ms {int} milliseconds, 1000 to 86400000
 * @return {Config} the changed copy
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is out of range
 */
export func withLongTimeout(c as Config, ms as int) {
    checkRange($ms, 1000, 86400000, "the long timeout");
    def out as Config init $c;
    $out.longTimeoutMs = $ms;
    return $out;
}

/**
 * The configuration with another cap on a reply's size.
 *
 * @param c {Config} the configuration
 * @param most {int} bytes, 65536 to 67108864
 * @return {Config} the changed copy
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is out of range
 */
export func withMaxBytes(c as Config, most as int) {
    checkRange($most, 65536, 67108864, "the reply cap");
    def out as Config init $c;
    $out.maxBytes = $most;
    return $out;
}

/**
 * Refuse a URL the deck should not send a password to.
 *
 * @param c {Config} the configuration
 * @throws {VirtualboxwsError} kind "virtualboxws" if the URL is unusable
 */
func checkUrl(c as Config) {
    def url as string init $c.url;
    if (regex.matches('[\x00-\x20\x7f-\x9f]', $url) or strings.contains($url, "#") or
        strings.contains($url, "?") or strings.contains(authority($url), "@")) {
        fail("the URL must be http(s)://host[:port]/path without spaces, login, query or fragment, got " +
            shown($url));
    }
    def u as uri.Uri;
    try {
        $u = uri.parse($url);
    } catch (e) {
        fail("the URL is not a URL: " + shown($url));
    }
    def scheme as string init strings.lower($u.scheme);
    if ($u.host == "" or not regex.matches('^[0-9]*$', $u.port) or
        ($scheme != "https" and $scheme != "http")) {
        fail("the URL must be http(s)://host[:port]/path, got " + shown($url));
    }
    if ($scheme == "http" and not $c.allowPlainHttp and
        not lists.contains(LOOPBACK, strings.lower($u.host))) {
        fail("plain http to " + shown($u.host) +
            " would send the password in clear: use https, or allow it with withPlainHttp");
    }
}

/**
 * The part of an absolute URL between `://` and its path, query or fragment.
 *
 * @param url {string} the URL
 * @return {string} the authority, `""` without `://`
 */
func authority(url as string) {
    def at as int init strings.indexOf($url, "://");
    if ($at < 0) {
        return "";
    }
    def rest as string init strings.substring($url, $at + 3);
    for (def stop in ["/", "?", "#"]) {
        def k as int init strings.indexOf($rest, $stop);
        if ($k >= 0) {
            $rest = strings.substring($rest, 0, $k);
        }
    }
    return $rest;
}

# --- checks ----------------------------------------------------------------

/**
 * Refuse text that is empty, too long or holds a control character.
 *
 * @param value {string} the text
 * @param what {string} what it is, for the message
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is unusable
 */
func checkText(value as string, what as string) {
    if ($value == "") {
        fail($what + " is empty");
    }
    checkChars($value, $what);
}

/**
 * Refuse text that is too long or holds a control character; empty is fine.
 *
 * @param value {string} the text
 * @param what {string} what it is, for the message
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is unusable
 */
func checkChars(value as string, what as string) {
    if (len($value) > MAX_ARG) {
        fail($what + " is longer than " + convert.toString(MAX_ARG) + " characters");
    }
    if (regex.matches(CONTROL, $value)) {
        fail($what + " holds a control character");
    }
}

/**
 * Refuse a machine reference: a name or UUID, not empty, at most 255
 * characters, no control character.
 *
 * @param vm {string} the machine's name or UUID
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is unusable
 */
func checkVm(vm as string) {
    checkName($vm, "the machine");
}

/**
 * Refuse a name: not empty, at most 255 characters, no control character.
 *
 * @param name {string} the name
 * @param what {string} what it is, for the message
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is unusable
 */
func checkName(name as string, what as string) {
    checkText($name, $what);
    if (len($name) > 255) {
        fail($what + " is longer than 255 characters");
    }
}

/**
 * Refuse a number out of range.
 *
 * @param n {int} the number
 * @param low {int} the smallest accepted
 * @param high {int} the largest accepted
 * @param what {string} what it is, for the message
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is out of range
 */
func checkRange(n as int, low as int, high as int, what as string) {
    if ($n < $low or $n > $high) {
        fail($what + " must be " + convert.toString($low) + " to " + convert.toString($high) +
            ", got " +
            convert.toString($n));
    }
}

# --- the web session -------------------------------------------------------

/**
 * Log on to the web service and check VirtualBox's version. `vboxwebsrv`
 * checks the user and password with its authentication library (the host's
 * users through PAM by default; none when it is set to `null`).
 *
 * @param c {Config} the configuration
 * @param username {string} the user
 * @param password {string} the password
 * @return {Session} the session, for every other call
 * @throws {VirtualboxwsError} kind "virtualboxws" if the URL is refused, the service cannot be reached, refuses the logon, or runs VirtualBox older than 7
 * @example
 *   def s as virtualboxws.Session init virtualboxws.logon($c, "admin", os.getEnv("VBOX_PASSWORD"));
 */
export func logon(c as Config, username as string, password as string) {
    checkUrl($c);
    checkChars($username, "the user");
    checkChars($password, "the password");
    def r as map of string to list of string init {};
    try {
        $r = exchange(
            $c,
            "IWebsessionManager_logon",
            {"username": [$username], "password": [$password]},
            $c.timeoutMs,
            "logon");
    } catch (e) {
        # a fault or an HTTP error is the service refusing; the rest is transport
        if ($e.kind == "virtualboxws" and ($e.reason == "fault" or $e.reason == "http")) {
            failWith(
                "logon refused for " + shown($username) + ": " +
                    strings.substring($e.message, len("virtualboxws: logon: ")),
                $e.reason,
                $e.code,
                $e.status);
        }
        throw $e;
    }
    def s as Session init Session{
        config: $c,
        vbox: refOf($r, "logon"),
        version: "",
        major: 0,
        minor: 0
    };
    def version as string init "";
    try {
        $version = returned(callOn($s, "IVirtualBox_getVersion", $s.vbox, {}, "getVersion"));
    } catch (e) {
        logoffQuietly($s);
        throw $e;
    }
    def m as regex.Match init regex.find('^([0-9]+)\.([0-9]+)\.', $version);
    if ($m.start != 0) {
        logoffQuietly($s);
        fail("VirtualBox reported no version: " + shown($version));
    }
    $s.version = $version;
    $s.major = convert.toInt($m.groups[0]);
    $s.minor = convert.toInt($m.groups[1]);
    if ($s.major < MIN_MAJOR) {
        logoffQuietly($s);
        fail("VirtualBox " + $version + " is too old; the deck needs VirtualBox " +
            convert.toString(MIN_MAJOR) +
            " or newer");
    }
    return $s;
}

/**
 * End the web session; the service frees every object it held.
 *
 * @param s {Session} the session
 * @throws {VirtualboxwsError} kind "virtualboxws" if the service cannot be reached or refuses (a session it already ended is not an error)
 */
export func logoff(s as Session) {
    try {
        exchange(
            $s.config,
            "IWebsessionManager_logoff",
            {"refIVirtualBox": [$s.vbox]},
            $s.config.timeoutMs,
            "logoff");
    } catch (e) {
        if ($e.kind != "virtualboxws" or $e.code != "INVALID_OBJECT") {
            throw $e;
        }
    }
}

/**
 * `logoff`, ignoring any failure: for cleaning up after another error.
 *
 * @param s {Session} the session
 */
func logoffQuietly(s as Session) {
    try {
        logoff($s);
    } catch (e) {
        $s.vbox = "";
    }
}

# --- SOAP ------------------------------------------------------------------

/**
 * Call any web-service method the deck has no function for. The arguments
 * map each parameter name to its values, one value for a plain parameter and
 * any number for an array, in the order the WSDL gives them; `_this` is the
 * object the method belongs to. The result maps each element of the reply
 * (`returnval`, out parameters) to its values. References it returns are the
 * caller's to `release`.
 *
 * @param s {Session} the session
 * @param method {string} the method, as the WSDL names it: `IVirtualBox_getHomeFolder`, `IMachine_getMemorySize`
 * @param args {map of string to list of string} the parameters
 * @return {map of string to list of string} the reply's elements
 * @throws {VirtualboxwsError} kind "virtualboxws" if the method or a parameter name is malformed, or the call fails
 * @example
 *   def r as map of string to list of string init virtualboxws.call($s, "IVirtualBox_getHomeFolder",
 *       {"_this": [$s.vbox]});
 *   io.printf("%s\n", $r["returnval"][0]);
 */
export func call(s as Session, method as string, args as map of string to list of string) {
    if (not regex.matches('^I[A-Za-z0-9]{1,63}_[A-Za-z][A-Za-z0-9]{0,63}$', $method)) {
        fail("the method must be Interface_method, such as IMachine_getName, got " + shown($method));
    }
    for (def name in maps.keys($args)) {
        if (not regex.matches('^[A-Za-z_][A-Za-z0-9_]{0,63}$', $name)) {
            fail("a parameter name must be an XML name, got " + shown($name));
        }
    }
    return exchange($s.config, $method, $args, $s.config.timeoutMs, $method);
}

/**
 * Call a method on an object.
 *
 * @param s {Session} the session
 * @param method {string} the method
 * @param this {string} the object's reference
 * @param args {map of string to list of string} the other parameters
 * @param what {string} the operation, for error messages
 * @return {map of string to list of string} the reply's elements
 * @throws {VirtualboxwsError} kind "virtualboxws" if the call fails
 */
func callOn(
    s as Session,
    method as string,
    this as string,
    args as map of string to list of string,
    what as string) {
    def full as map of string to list of string init {"_this": [$this]};
    for (def k in maps.keys($args)) {
        $full[$k] = $args[$k];
    }
    return exchange($s.config, $method, $full, $s.config.timeoutMs, $what);
}

/**
 * Read an attribute of an object (`IMachine_getName`).
 *
 * @param s {Session} the session
 * @param iface {string} the interface, such as `IMachine`
 * @param name {string} the attribute, capitalised, such as `Name`
 * @param this {string} the object's reference
 * @param what {string} the operation, for error messages
 * @return {string} its value
 * @throws {VirtualboxwsError} kind "virtualboxws" if the call fails
 */
func attribute(s as Session, iface as string, name as string, this as string, what as string) {
    return returned(callOn($s, $iface + "_get" + $name, $this, {}, $what));
}

/**
 * Send one SOAP request and read the reply, within a deadline that covers
 * connecting, sending and reading.
 *
 * @param c {Config} the configuration
 * @param method {string} the method
 * @param args {map of string to list of string} the parameters
 * @param timeoutMs {int} the deadline
 * @param what {string} the operation, for error messages
 * @return {map of string to list of string} the reply's elements
 * @throws {VirtualboxwsError} kind "virtualboxws" if the service cannot be reached, answers too late or not SOAP, or returns a fault
 * @throws {Error} kind "limit" if the reply is over `maxBytes`
 */
func exchange(
    c as Config,
    method as string,
    args as map of string to list of string,
    timeoutMs as int,
    what as string) {
    def body as string init envelope($method, $args);
    def url as string init $c.url;
    def tls as http.TlsOptions init $c.tls;
    def maxBytes as int init $c.maxBytes;
    def t as task of http.Response init spawn {
        return http.requestWithTls(
            "POST",
            $url,
            {"Content-Type": "text/xml; charset=utf-8", "SOAPAction": "\"\""},
            $body,
            $timeoutMs,
            $maxBytes,
            $tls);
    };
    def r as http.Response;
    try {
        $r = task.waitTimeout($t, $timeoutMs);
    } catch (e) {
        # kind "cancelled" (jennifer after 0.25); the message is for older interpreters
        if ($e.kind == "cancelled" or $e.message == "task cancelled") {
            task.cancel($t);
            task.discard($t);
            throw $e;
        }
        if ($e.kind == "timeout") {
            # the overall deadline, or a read idle as long: both mean no answer in time.
            # Only task.waitTimeout's own timeout leaves the task running; the
            # runtime's message is the one way to tell it from http's.
            if (strings.contains($e.message, "task.waitTimeout")) {
                task.cancel($t);
                task.discard($t);
            }
            failWith(
                $what + ": no answer from " + shown($url) + " within " +
                    convert.toString($timeoutMs) + " ms",
                "timeout",
                "",
                0);
        }
        # A cap is kind "limit" (jennifer after 0.25: http, net); the message
        # match is for older interpreters and goes with the next floor raise.
        if ($e.kind == "limit" or strings.contains($e.message, "body exceeds ")) {
            throw Error{
                kind: "limit",
                message: "virtualboxws: " + $what + ": the reply is over " +
                    convert.toString($maxBytes) + " bytes"
            };
        }
        failWith(
            $what + ": cannot reach " + shown($url) + ": " + cleaned($e.message, 200),
            "unreachable",
            "",
            0);
    }
    return reply($r, $method, $what);
}

/**
 * The SOAP 1.1 envelope of a request: the method's element in VirtualBox's
 * namespace, each parameter an unqualified child, an array parameter one
 * child per value.
 *
 * @param method {string} the method
 * @param args {map of string to list of string} the parameters
 * @return {string} the envelope
 * @throws {VirtualboxwsError} kind "virtualboxws" if a value holds a character XML cannot carry
 */
func envelope(method as string, args as map of string to list of string) {
    def request as xml.Value init xml.elementNS(VBOX_NS, "vbox:" + $method);
    try {
        for (def name in maps.keys($args)) {
            for (def v in $args[$name]) {
                $request = xml.append($request, xml.setText(xml.elementNS("", $name), $v));
            }
        }
    } catch (e) {
        fail($method + ": a parameter holds a character XML cannot carry");
    }
    def bodyEl as xml.Value init xml.append(xml.elementNS(SOAP_NS, "soap:Body"), $request);
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
        xml.encode(xml.append(xml.elementNS(SOAP_NS, "soap:Envelope"), $bodyEl));
}

/**
 * The elements of a SOAP reply, or the error its fault describes.
 *
 * @param r {http.Response} the HTTP response
 * @param method {string} the method called
 * @param what {string} the operation, for error messages
 * @return {map of string to list of string} the reply's elements by name
 * @throws {VirtualboxwsError} kind "virtualboxws" for a fault, an HTTP error or a reply that is not the method's
 */
func reply(r as http.Response, method as string, what as string) {
    def doc as xml.Value;
    try {
        $doc = xml.decode($r.body);
    } catch (e) {
        if ($r.status != 200) {
            failWith(
                $what + ": HTTP " + convert.toString($r.status) + " " + cleaned($r.statusText, 80),
                "http",
                "",
                $r.status);
        }
        failWith(
            $what + ": the reply is not XML: " + cleaned($e.message, 120),
            "reply",
            "",
            $r.status);
    }
    def ns as map of string to string init {"s": SOAP_NS, "v": VBOX_NS};
    if (xml.namespace($doc) != SOAP_NS or xml.localName($doc) != "Envelope" or
        not xml.has($doc, "s:Body", $ns)) {
        failWith(
            $what + ": the reply is not a SOAP envelope (HTTP " + convert.toString($r.status) + ")",
            "reply",
            "",
            $r.status);
    }
    def found as list of xml.Value init xml.children(xml.get($doc, "s:Body", $ns));
    if (len($found) != 1) {
        failWith(
            $what + ": the reply's body holds " + convert.toString(len($found)) +
                " elements, not one",
            "reply",
            "",
            $r.status);
    }
    def top as xml.Value init $found[0];
    if (xml.namespace($top) == SOAP_NS and xml.localName($top) == "Fault") {
        failFault($top, $what, $r.status);
    }
    if ($r.status != 200) {
        failWith(
            $what + ": HTTP " + convert.toString($r.status) + " " + cleaned($r.statusText, 80),
            "http",
            "",
            $r.status);
    }
    if (xml.namespace($top) != VBOX_NS or xml.localName($top) != $method + "Response") {
        failWith(
            $what + ": the reply is " + shown(xml.localName($top)) + ", not " + $method + "Response",
            "reply",
            "",
            $r.status);
    }
    def out as map of string to list of string init {};
    for (def child in xml.children($top)) {
        def name as string init xml.localName($child);
        if (not maps.has($out, $name)) {
            $out[$name] = [];
        }
        $out[$name][] = xml.text($child);
    }
    return $out;
}

/**
 * Throw the error a SOAP fault describes: its text without VirtualBox's
 * `VirtualBox error: apirc=0x...` frame, and the code from its detail
 * (`RuntimeFault/resultCode`), named where it is known; an
 * `InvalidObjectFault` (an expired session, a released object) is
 * `INVALID_OBJECT`.
 *
 * @param fault {xml.Value} the `Fault` element
 * @param what {string} the operation
 * @param status {int} the HTTP status of the reply
 * @throws {VirtualboxwsError} kind "virtualboxws", always, with `reason` `"fault"`
 */
func failFault(fault as xml.Value, what as string, status as int) {
    def text as string init "";
    if (xml.has($fault, "faultstring")) {
        $text = xml.text(xml.get($fault, "faultstring"));
    }
    $text = regex.replace('^VirtualBox error: (apirc=0x[0-9a-fA-F]+ )?', strings.trim($text), "");
    $text = regex.replace(' \(0x[0-9a-fA-F]{8}\)$', $text, "");
    if ($text == "") {
        $text = "the service refused without a message";
    }
    def code as string init "";
    def ns as map of string to string init {"v": VBOX_NS};
    if (xml.has($fault, "detail/v:RuntimeFault/resultCode", $ns)) {
        $code = codeName(xml.text(xml.get($fault, "detail/v:RuntimeFault/resultCode", $ns)));
    } elseif (xml.has($fault, "detail/v:InvalidObjectFault", $ns)) {
        $code = "INVALID_OBJECT";
    }
    def tail as string init "";
    if ($code != "") {
        $tail = " (" + $code + ")";
    }
    failWith($what + ": " + cleaned($text, 300) + $tail, "fault", $code, $status);
}

/**
 * The name of a result code: `VBOX_E_*`, a COM `E_*`, else its hex.
 *
 * @param code {string} the code as a signed 32-bit decimal, such as `-2135228415`
 * @return {string} the name, or `0x` and eight hex digits, or `""` if it is no number
 */
func codeName(code as string) {
    def t as string init strings.trim($code);
    if (not regex.matches('^-?[0-9]{1,10}$', $t)) {
        return "";
    }
    def n as int init convert.toInt($t);
    if ($n < 0) {
        $n = $n + 4294967296;
    }
    if ($n > 2159738880 and $n < 2159738880 + len(VBOX_CODES)) {
        return VBOX_CODES[$n - 2159738880];
    }
    def hex as string init strings.upper(convert.toString($n, 16));
    while (len($hex) < 8) {
        $hex = "0" + $hex;
    }
    def key as string init "0x" + $hex;
    if (maps.has(COM_CODES, $key)) {
        return COM_CODES[$key];
    }
    return $key;
}

/**
 * The code of a virtualboxws error: a `VBOX_E_*` name, a COM `E_*` name, an
 * `0x` hex code VirtualBox gave without a known name, or `INVALID_OBJECT`
 * for a reference the service no longer knows (an expired session). It is
 * the error's `code` field; kept for code written before
 * `VirtualboxwsError`. The parameter is a `VirtualboxwsError`, so match the
 * kind before passing a caught error.
 *
 * @param e {VirtualboxwsError} a caught error of kind "virtualboxws"
 * @return {string} the code, `""` if it names none
 * @example
 *   try {
 *       virtualboxws.info($s, "web");
 *   } catch (e) {
 *       if ($e.kind == "virtualboxws" and $e.code == "VBOX_E_OBJECT_NOT_FOUND") {
 *           io.printf("no such machine\n");
 *       }
 *   }
 */
export func errorCode(e as VirtualboxwsError) {
    return $e.code;
}

/**
 * The single `returnval` of a reply.
 *
 * @param r {map of string to list of string} the reply
 * @return {string} its value, `""` if there is none
 */
func returned(r as map of string to list of string) {
    return first($r, "returnval");
}

/**
 * The first value of a reply element.
 *
 * @param r {map of string to list of string} the reply
 * @param name {string} the element
 * @return {string} its first value, `""` if there is none
 */
func first(r as map of string to list of string, name as string) {
    if (not maps.has($r, $name) or len($r[$name]) == 0) {
        return "";
    }
    return $r[$name][0];
}

/**
 * Every value of a reply element.
 *
 * @param r {map of string to list of string} the reply
 * @param name {string} the element
 * @return {list of string} its values, empty if there are none
 */
func all(r as map of string to list of string, name as string) {
    if (not maps.has($r, $name)) {
        return [];
    }
    return $r[$name];
}

/**
 * The object reference a reply returns.
 *
 * @param r {map of string to list of string} the reply
 * @param what {string} the operation, for the message
 * @return {string} the reference
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is not one
 */
func refOf(r as map of string to list of string, what as string) {
    def ref as string init returned($r);
    checkRef($ref, $what);
    return $ref;
}

/**
 * Refuse a value that is not a managed object reference.
 *
 * @param ref {string} the value
 * @param what {string} the operation, for the message
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is not one
 */
func checkRef(ref as string, what as string) {
    if (not regex.matches(REF, $ref)) {
        fail($what + ": the service returned no object reference: " + shown($ref));
    }
}

/**
 * Release an object reference the deck obtained; failures are ignored (the
 * session's end frees it anyway).
 *
 * @param s {Session} the session
 * @param ref {string} the reference, `""` for none
 */
func release(s as Session, ref as string) {
    if ($ref == "") {
        return;
    }
    try {
        callOn($s, "IManagedObjectRef_release", $ref, {}, "release");
    } catch (e) {
        $ref = "";
    }
}

/**
 * Release every reference in a list.
 *
 * @param s {Session} the session
 * @param refs {list of string} the references
 */
func releaseAll(s as Session, refs as list of string) {
    for (def ref in $refs) {
        release($s, $ref);
    }
}

/**
 * Release an object reference: `IManagedObjectRef_release`. Every function of
 * the deck releases what it obtains; this is for references from `call`.
 *
 * @param s {Session} the session
 * @param ref {string} the reference
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is not a reference or the service refuses
 */
export func releaseRef(s as Session, ref as string) {
    checkRef($ref, "release");
    callOn($s, "IManagedObjectRef_release", $ref, {}, "release");
}

# --- machines, sessions, progress ------------------------------------------

/**
 * A machine's reference, by name or UUID; the caller releases it.
 *
 * @param s {Session} the session
 * @param vm {string} the machine's name or UUID
 * @return {string} the reference
 * @throws {VirtualboxwsError} kind "virtualboxws" if the name is unusable or there is no such machine (`VBOX_E_OBJECT_NOT_FOUND`)
 */
func machine(s as Session, vm as string) {
    checkVm($vm);
    return refOf(
        callOn($s, "IVirtualBox_findMachine", $s.vbox, {"nameOrId": [$vm]}, "findMachine " + $vm),
        "findMachine " + $vm);
}

/**
 * A new `ISession` object, to lock a machine with; the caller releases it.
 *
 * @param s {Session} the session
 * @return {string} its reference
 * @throws {VirtualboxwsError} kind "virtualboxws" if the service refuses
 */
func newSession(s as Session) {
    return refOf(
        exchange(
            $s.config,
            "IWebsessionManager_getSessionObject",
            {"refIVirtualBox": [$s.vbox]},
            $s.config.timeoutMs,
            "getSessionObject"),
        "getSessionObject");
}

/**
 * Lock a machine for a session.
 *
 * @param s {Session} the session
 * @param machineRef {string} the machine
 * @param sessionRef {string} the `ISession`
 * @param lockType {string} `Shared` (a running machine) or `Write` (a stopped one, exclusively)
 * @param what {string} the operation, for error messages
 * @throws {VirtualboxwsError} kind "virtualboxws" if it is locked elsewhere or the service refuses
 */
func lock(
    s as Session,
    machineRef as string,
    sessionRef as string,
    lockType as string,
    what as string) {
    callOn(
        $s,
        "IMachine_lockMachine",
        $machineRef,
        {"session": [$sessionRef], "lockType": [$lockType]},
        $what);
}

/**
 * Unlock a session's machine and release the session; failures are
 * ignored, for cleanup.
 *
 * @param s {Session} the session
 * @param sessionRef {string} the `ISession`
 */
func unlockAndRelease(s as Session, sessionRef as string) {
    try {
        callOn($s, "ISession_unlockMachine", $sessionRef, {}, "unlockMachine");
    } catch (e) {
        $sessionRef = $sessionRef;
    }
    release($s, $sessionRef);
}

/**
 * Wait for an `IProgress` to complete, asking the service to wait a second
 * at a time, then release it. Past the deadline the operation is cancelled.
 *
 * @param s {Session} the session
 * @param progress {string} the progress object
 * @param timeoutMs {int} the deadline
 * @param what {string} the operation, for error messages
 * @throws {VirtualboxwsError} kind "virtualboxws" if the operation fails (with its error text and code) or runs past the deadline
 */
func waitFor(s as Session, progress as string, timeoutMs as int, what as string) {
    checkRef($progress, $what);
    defer release($s, $progress);
    def started as time.Time init time.now();
    while (attribute($s, "IProgress", "Completed", $progress, $what) != "true") {
        def left as int init $timeoutMs - time.milliseconds(time.sub(time.now(), $started));
        if ($left <= 0) {
            try {
                callOn($s, "IProgress_cancel", $progress, {}, $what);
            } catch (e) {
                $left = 0;
            }
            failWith(
                $what + ": not done after " + convert.toString($timeoutMs) + " ms, cancelled",
                "timeout",
                "",
                0);
        }
        def step as int init PROGRESS_STEP_MS;
        if ($left < $step) {
            $step = $left;
        }
        exchange(
            $s.config,
            "IProgress_waitForCompletion",
            {"_this": [$progress], "timeout": [convert.toString($step)]},
            $s.config.timeoutMs + $step,
            $what);
    }
    def code as string init attribute($s, "IProgress", "ResultCode", $progress, $what);
    if ($code == "0") {
        return;
    }
    def text as string init "";
    def info as string init "";
    try {
        $info = attribute($s, "IProgress", "ErrorInfo", $progress, $what);
        if (regex.matches(REF, $info)) {
            $text = attribute($s, "IVirtualBoxErrorInfo", "Text", $info, $what);
        }
    } catch (e) {
        $text = "";
    }
    release($s, $info);
    if ($text == "") {
        $text = "the operation failed";
    }
    def name as string init codeName($code);
    def tail as string init "";
    if ($name != "") {
        $tail = " (" + $name + ")";
    }
    failWith($what + ": " + cleaned($text, 300) + $tail, "operation", $name, 0);
}
