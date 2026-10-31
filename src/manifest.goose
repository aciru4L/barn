import std;
import json;
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

var warned_owner_text: u8[>..] = [];
var warned_owners: (const u8[:])[>..] = [];

fn has_upper(s: const u8[:]) -> bool {
    for c in s { if c >= 'A' && c <= 'Z' { return true; } }
    return false;
}

fn warn_once_about_owner(given: const u8[:], lowered: const u8[:]) {
    guard !contains(warned_owners[..], given) else { return; }
    let start = warned_owner_text.len;
    warned_owner_text.append(given);
    warned_owners.push(warned_owner_text[start..]);
    write_stderr(str("warning: owner '", given, "' is not lowercase: using '", lowered, "'\n"));
}

fn lowercase_owner(s: const u8[:], owner_length: i64, out: u8[>..]&) -> const u8[:] {
    guard has_upper(s[..owner_length]) else { return s; }
    let start = out.len;
    out.append(s);
    to_lower(out[start..start + owner_length]);
    let lowered = out[start..];
    warn_once_about_owner(s[..owner_length], lowered[..owner_length]);
    return lowered;
}

fn lowercase_spec_owner(spec: const u8[:], out: u8[>..]&) -> const u8[:] {
    let slash = find(spec, "/");
    guard slash >= 0 else { return spec; }
    return lowercase_owner(spec, slash, out);
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

fn valid_root_file(path: const u8[:]) -> bool {
    is_relative_path(path) && ends_with(path, ".goose") && path.len > 6 && find(path, "..") < 0
}


fn is_folder_path(text: const u8[:]) -> bool { starts_with(text, "./") || starts_with(text, "../") }

struct Dependency { name: const u8[:], version: Version }

fn format(out: u8[>..]&, d: Dependency) { format(out, d.name, ":", d.version); }

struct Override { name: const u8[:], version: Version, path: const u8[:] }

fn is_local(o: Override) -> bool { o.path.len > 0 }

struct Manifest {
    egg: Dependency, main: const u8[:], test: const u8[:], first_dependency: i64, dependency_count: i64,
    first_override: i64, override_count: i64,
}

fn dependencies_end(m: Manifest) -> i64 { m.first_dependency + m.dependency_count }
fn overrides_end(m: Manifest) -> i64 { m.first_override + m.override_count }

fn line_at(text: const u8[:], at: i64) -> i64 {
    var line = 1;
    for c in text[..min(at, text.len)] { if c == '\n' { line++; } }
    return line;
}

fn parse_manifest(src: const u8[:], dependencies: Dependency[>..]&, overrides: Override[>..]&,
                  names: u8[>..]&) -> Manifest, u8[>..] {
    var r = json::reader(src);
    var m = Manifest { first_dependency: dependencies.len, first_override: overrides.len, .. };
    var keys: (const u8[:])[>..] = [];
    var given_owner: const u8[:] = names[..0];
    var given_name: const u8[:] = names[..0];
    var has_version = false;
    var at = 0;

    fn fail(what: const u8[:]) {
        return Manifest {..}, str("line ", line_at(src, at), ": ", what) from parse_manifest;
    }

    fn fail_json() {
        at = r.error_at;
        fail(str(r.error, " (barn.json is strict JSON: no comments, no trailing commas)"));
    }

    fn check_json() {
        guard r.error.len == 0 else { fail_json(); }
    }

    fn keep(s: const u8[:]) -> const u8[:] {
        let start = names.len;
        names.append(s);
        return names[start..];
    }

    fn read_text(what: const u8[:]) -> const u8[:] {
        check_json();
        guard json::peek(r) == '"' else { fail(str(what, " must be a string")); }
        var scratch: u8[>..] = [];
        let value = json::read_string(r, scratch);
        check_json();
        return keep(value);
    }

    fn read_object<F>(k: const u8[:]) {
        check_json();
        guard json::peek(r) == '{' else { fail(str(k, " must be an object")); }
        json::each_member(r) { key =>
            check_json();
            at = r.pos;
            F(keep(key));
        };
        check_json();
    }

    fn read_version(s: const u8[:]) -> Version {
        guard find(s, "->") < 0 else { fail(str("'", s, "': ranges are not supported")); }
        let v, ok = parse_version(s);
        guard ok else { fail(str("bad version '", s, "'")); }
        return v;
    }

    fn egg_name(s: const u8[:]) -> const u8[:] {
        let slash = find(s, "/");
        guard slash >= 0 else { fail(str("bad egg '", s, "': expected owner/name")); }
        let egg = lowercase_owner(s, slash, names);
        guard valid_owner(egg[..slash]) else { fail(str("bad owner in '", s, "': use ", OWNER_RULE)); }
        let name = s[slash + 1..];
        guard valid_name(name) else { fail(str("bad name in '", s, "': use ", NAME_RULE, name_hint(name))); }
        return egg;
    }

    fn read_root_file(k: const u8[:]) -> const u8[:] {
        let path = read_text(k);
        guard valid_root_file(path) else { fail(str("bad ", k, " '", path, "'")); }
        return path;
    }

    fn take_dependencies() {
        read_object("dependencies") { key =>
            let name = egg_name(key);
            let d = Dependency { name: name, version: read_version(read_text(str("the version of ", name))) };
            for i in m.first_dependency..dependencies.len {
                guard dependencies[i].name != d.name else { fail(str(d.name, " is in dependencies twice")); }
            }
            dependencies.push(d);
        };
    }

    fn parse_override(name: const u8[:], value: const u8[:]) -> Override {
        let bad = str("bad override '", value, "': use a version, or a folder starting with ./ or ../");
        guard is_folder_path(value) else {
            guard find(value, "/") < 0 && find(value, "\\") < 0 else { fail(bad); }
            return Override { name: name, version: read_version(value), path: value[..0] };
        }
        guard is_relative_path(value) else { fail(bad); }
        return Override { name: name, path: value, .. };
    }

    fn take_overrides() {
        read_object("overrides") { key =>
            let name = egg_name(key);
            let o = parse_override(name, read_text(str("the override of ", name)));
            for i in m.first_override..overrides.len {
                guard overrides[i].name != o.name else { fail(str(o.name, " is in overrides twice")); }
            }
            overrides.push(o);
        };
    }

    fn take_value(k: const u8[:]) {
        if k == "owner" {
            given_owner = read_text(k);
            var owner = str(given_owner);
            to_lower(owner);
            guard valid_owner(owner) else { fail(str("bad owner: use ", OWNER_RULE)); }
        } else if k == "name" {
            given_name = read_text(k);
            guard valid_name(given_name) else { fail(str("bad name: use ", NAME_RULE)); }
        } else if k == "version" {
            m.egg.version = read_version(read_text(k));
            has_version = true;
            guard is_release(m.egg.version) else { fail("version must be x.y.z"); }
        } else if k == "main" {
            m.main = read_root_file(k);
        } else if k == "test" {
            m.test = read_root_file(k);
        } else if k == "dependencies" {
            take_dependencies();
        } else if k == "overrides" {
            take_overrides();
        } else {
            fail(str("unknown key '", k, "'"));
        }
    }

    guard json::peek(r) == '{' else { fail("expected a JSON object"); }
    read_object("barn.json") { k =>
        guard !contains(keys[..], k) else { fail(str(k, " is given twice")); }
        keys.push(k);
        take_value(k);
    };
    guard json::finish(r) else { fail_json(); }
    guard given_owner.len > 0 else { return Manifest {..}, str("missing \"owner\""); }
    guard given_name.len > 0 else { return Manifest {..}, str("missing \"name\""); }
    guard has_version else { return Manifest {..}, str("missing \"version\""); }
    let owner = lowercase_owner(given_owner, given_owner.len, names);
    let start = names.len;
    format(names, owner, "/", given_name);
    m.egg.name = names[start..];
    m.dependency_count = dependencies.len - m.first_dependency;
    m.override_count = overrides.len - m.first_override;
    return m, str("");
}
