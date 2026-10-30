import std;
import src.version;

let OWNER_RULE = "lowercase letters, digits, - and _";
let NAME_RULE = "a lowercase letter, then lowercase letters, digits and _";

fn valid_owner(s: const u8[:]) -> bool {
    guard s.len > 0 && s.len <= 64 && s[0] != '-' && s[0] != '_' else { return false; }
    for c in s {
        guard (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' else { return false; }
    }
    return true;
}

fn valid_name(s: const u8[:]) -> bool {
    guard s.len > 0 && s.len <= 64 && s[0] >= 'a' && s[0] <= 'z' else { return false; }
    for c in s {
        guard (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_' else { return false; }
    }
    return true;
}

fn valid_egg(egg: const u8[:]) -> bool {
    let slash = find(egg, "/");
    return slash > 0 && valid_owner(egg[..slash]) && valid_name(egg[slash + 1..]);
}

fn short_name(egg: const u8[:]) -> const u8[:] { egg[find(egg, "/") + 1..] }

var case_warnings: u8[>..] = [];

fn has_upper(s: const u8[:]) -> bool {
    for c in s { if c >= 'A' && c <= 'Z' { return true; } }
    return false;
}

// s with its first count bytes lowercased, copied into out when that changes it; warns once per spelling.
fn lowercased(what: const u8[:], s: const u8[:], count: i64, out: u8[>..]&) -> const u8[:] {
    guard has_upper(s[..count]) else { return s; }
    let start = out.len;
    out.append(s);
    to_lower(out[start..start + count]);
    let lowered = out[start..];
    let warning = str("warning: ", what, " '", s[..count], "' is not lowercase: using '", lowered[..count], "'\n");
    if find(case_warnings, warning) < 0 {
        case_warnings.append(warning);
        write_stderr(warning);
    }
    return lowered;
}

// The owner of an owner/name spec lowercased; the name is left to fail validation.
fn lowercased_spec(spec: const u8[:], out: u8[>..]&) -> const u8[:] {
    let slash = find(spec, "/");
    guard slash >= 0 else { return spec; }
    return lowercased("owner", spec, slash, out);
}

fn name_suggestion(name: const u8[:]) -> u8[>..] {
    var suggestion: u8[>..] = [];
    for c in name { suggestion.push(if c == '-' { '_' } else if c >= 'A' && c <= 'Z' { c + 32 } else { c }); }
    return suggestion;
}

fn name_hint(name: const u8[:]) -> u8[>..] {
    let suggestion = name_suggestion(name);
    guard valid_name(suggestion) else { return str(""); }
    return str("; say '", suggestion, "'");
}

fn is_relative_path(path: const u8[:]) -> bool {
    path.len > 0 && path[0] != '/' && find(path, "\\") < 0 && find(path, ":") < 0 && find(path, "\"") < 0
}

fn valid_main(path: const u8[:]) -> bool {
    is_relative_path(path) && ends_with(path, ".goose") && path.len > 6 && find(path, "..") < 0
}

struct Dependency { name: const u8[:], version: Version, at: i64 = -1, end: i64 = -1 }

fn format(out: u8[>..]&, d: Dependency) { format(out, d.name, ":", d.version); }

struct Override { name: const u8[:], version: Version, path: const u8[:] }

fn is_local(o: Override) -> bool { o.path.len > 0 }

struct Manifest {
    egg: Dependency, main: const u8[:], first_dependency: i64, dependency_count: i64, first_override: i64,
    override_count: i64, dependencies_open: i64 = -1, dependencies_close: i64 = -1,
}

fn dependencies_end(m: Manifest) -> i64 { m.first_dependency + m.dependency_count }
fn overrides_end(m: Manifest) -> i64 { m.first_override + m.override_count }

fn parse_manifest(src: const u8[:], dependencies: Dependency[>..]&, overrides: Override[>..]&,
                  names: u8[>..]&) -> Manifest, u8[>..] {
    var pos = 0;
    var line = 1;
    var m = Manifest { first_dependency: dependencies.len, first_override: overrides.len, .. };
    var owner_span: i64[2] = [-1, -1];
    var name_span: i64[2] = [-1, -1];
    var version_span: i64[2] = [-1, -1];
    var string_start = 0;
    var string_end = 0;

    fn fail(what: const u8[:]) {
        return Manifest {..}, str("line ", line, ": ", what) from parse_manifest;
    }

    fn skip_space() {
        while pos < src.len {
            let c = src[pos];
            if c == '\n' { line++; pos++; }
            else if c == ' ' || c == '\t' || c == '\r' { pos++; }
            else if c == '/' && pos + 1 < src.len && src[pos + 1] == '/' {
                while pos < src.len && src[pos] != '\n' { pos++; }
            }
            else { break; }
        }
    }

    fn take(c: u8) -> bool {
        skip_space();
        if pos < src.len && src[pos] == c { pos++; return true; }
        return false;
    }

    fn expect(c: u8, what: const u8[:]) {
        guard take(c) else { fail(str("expected ", what)); }
    }

    fn is_key_char(c: u8) -> bool { (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' }

    fn key() -> const u8[:] {
        skip_space();
        let start = pos;
        while pos < src.len && is_key_char(src[pos]) { pos++; }
        guard pos > start else { fail("expected a key"); }
        return src[start..pos];
    }

    fn string() -> const u8[:] {
        expect('"', "a string");
        let start = pos;
        while pos < src.len && src[pos] != '"' && src[pos] != '\n' { pos++; }
        guard pos < src.len && src[pos] == '"' else { fail("unterminated string"); }
        pos++;
        string_start = start;
        string_end = pos - 1;
        return src[start..pos - 1];
    }

    fn version(s: const u8[:]) -> Version {
        guard find(s, "->") < 0 else { fail(str("'", s, "': ranges are not supported")); }
        let v, ok = parse_version(s);
        guard ok else { fail(str("bad version '", s, "'")); }
        return v;
    }

    fn egg_name(s: const u8[:]) -> const u8[:] {
        let slash = find(s, "/");
        guard slash >= 0 else { fail(str("bad egg '", s, "': expected owner/name")); }
        let egg = lowercased("owner", s, slash, names);
        guard valid_owner(egg[..slash]) else { fail(str("bad owner in '", s, "': use ", OWNER_RULE)); }
        let name = s[slash + 1..];
        guard valid_name(name) else { fail(str("bad name in '", s, "': use ", NAME_RULE, name_hint(name))); }
        return egg;
    }

    fn dependency(s: const u8[:]) -> Dependency {
        let colon = find(s, ":");
        guard colon >= 0 else { fail(str("'", egg_name(s), "' needs a version")); }
        return Dependency { name: egg_name(s[..colon]), version: version(s[colon + 1..]), at: string_start,
                            end: string_end };
    }

    fn override(s: const u8[:]) -> Override {
        let equals = find(s, "=");
        guard equals >= 0 else {
            let d = dependency(s);
            return Override { name: d.name, version: d.version, path: s[..0] };
        }
        guard is_relative_path(s[equals + 1..]) else { fail(str("bad override '", s, "'")); }
        return Override { name: egg_name(s[..equals]), path: s[equals + 1..], .. };
    }

    fn each_string<F>() {
        expect('[', "'['");
        loop {
            if take(']') { return; }
            F(string());
            if take(']') { return; }
            expect(',', "',' or ']'");
        }
    }

    fn take_once(k: const u8[:], span: i64[2]&) {
        guard span[0] < 0 else { fail(str(k, " is given twice")); }
        string();
        span[0] = string_start;
        span[1] = string_end;
    }

    fn take_dependencies() {
        guard m.dependencies_open < 0 else { fail("dependencies is given twice"); }
        skip_space();
        m.dependencies_open = pos;
        each_string() {
            let d = dependency(it);
            for i in m.first_dependency..dependencies.len {
                guard dependencies[i].name != d.name else { fail(str(d.name, " is in dependencies twice")); }
            }
            dependencies.push(d);
        };
        m.dependencies_close = pos - 1;
    }

    fn take_overrides() {
        each_string() {
            let o = override(it);
            for i in m.first_override..overrides.len {
                guard overrides[i].name != o.name else { fail(str(o.name, " is in overrides twice")); }
            }
            overrides.push(o);
        };
    }

    fn take_retired(k: const u8[:]) {
        each_string() {
            let message: u8[>..] = if k == "local" { str("local is not supported: use overrides") }
                                   else { str("dependencyManagement is not supported: use overrides") };
            fail(message);
        };
    }

    fn take_value(k: const u8[:]) {
        if k == "owner" {
            take_once(k, owner_span);
            var owner = str(src[owner_span[0]..owner_span[1]]);
            to_lower(owner);
            guard valid_owner(owner) else { fail(str("bad owner: use ", OWNER_RULE)); }
        } else if k == "name" {
            take_once(k, name_span);
            guard valid_name(src[name_span[0]..name_span[1]]) else { fail(str("bad name: use ", NAME_RULE)); }
        } else if k == "version" {
            take_once(k, version_span);
            m.egg.version = version(src[version_span[0]..version_span[1]]);
            guard is_release(m.egg.version) else { fail("version must be x.y.z"); }
        } else if k == "main" {
            guard m.main.len == 0 else { fail("main is given twice"); }
            let path = string();
            guard valid_main(path) else { fail(str("bad main '", path, "'")); }
            m.main = path;
        } else if k == "dependencies" {
            take_dependencies();
        } else if k == "overrides" {
            take_overrides();
        } else if k == "dependencyManagement" || k == "local" {
            take_retired(k);
        } else {
            fail(str("unknown key '", k, "'"));
        }
    }

    loop {
        skip_space();
        if pos >= src.len { break; }
        let k = key();
        expect('=', "'='");
        take_value(k);
        expect(';', "';'");
    }
    guard owner_span[0] >= 0 else { return Manifest {..}, str("missing owner = \"...\";"); }
    guard name_span[0] >= 0 else { return Manifest {..}, str("missing name = \"...\";"); }
    guard version_span[0] >= 0 else { return Manifest {..}, str("missing version = \"x.y.z\";"); }
    let given_owner = src[owner_span[0]..owner_span[1]];
    let owner = lowercased("owner", given_owner, given_owner.len, names);
    let start = names.len;
    format(names, owner, "/", src[name_span[0]..name_span[1]]);
    m.egg.name = names[start..];
    m.dependency_count = dependencies.len - m.first_dependency;
    m.override_count = overrides.len - m.first_override;
    return m, str("");
}
