import std;
import os;
import src.version;
import src.manifest;
import src.eggs;
import src.resolve;
import src.checksum;

struct Record { egg: const u8[:], version: Version, ok: bool }

struct CopyCheck { edited: bool = false, count: i64 = 0, problems: u8[>..] }

fn copy_path(dir: const u8[:], name: const u8[:]) -> u8[>..] { str(dir, "/.barn/", name) }

fn read_record(copy: const u8[:], text: u8[>..]&) -> Record {
    guard read_file(str(copy, "/", RECORD_FILE), text) else { return Record { egg: text[..0], ok: false, .. }; }
    let line = trim(text);
    let colon = find(line, ":");
    guard colon > 0 else { return Record { egg: text[..0], ok: false, .. }; }
    let v, ok = parse_version(line[colon + 1..]);
    return Record { egg: line[..colon], version: v, ok: ok && !wants_newest_snapshot(v) };
}

fn write_record(copy: const u8[:], egg: const u8[:], v: Version) -> bool {
    write_file(str(copy, "/", RECORD_FILE), str(egg, ":", v, "\n"))
}

fn edited_detail(eggs: const u8[:], copy: const u8[:], label: const u8[:]) -> u8[>..], bool {
    var text: u8[>..] = [];
    let record = read_record(copy, text);
    guard record.ok else { return str(""), true; }
    var laid: u8[>..] = [];
    guard read_sums(egg_dir(eggs, record.egg, record.version), laid) else { return str(""), false; }
    var current: u8[>..] = [];
    file_sums(copy, current);
    guard current != laid else { return str(""), false; }
    var detail: u8[>..] = [];
    describe_changes(laid, current, str(label, "/"), detail);
    return detail, true;
}

fn wants_any_snapshot(b: Build, node: i64) -> bool {
    for r in b.requests { if r.chosen == node && wants_newest_snapshot(r.wanted) { return true; } }
    return false;
}

fn accepts(b: Build, node: i64, record: Record) -> bool {
    let n = b.nodes[node];
    guard record.ok && record.egg == n.egg else { return false; }
    guard record.version != n.version else { return true; }
    return is_snapshot(record.version) && release_of(record.version) == release_of(n.version) &&
           wants_any_snapshot(b, node);
}

fn check_copy(b: Build, node: i64, dir: const u8[:], eggs: const u8[:], check: CopyCheck&) {
    let n = b.nodes[node];
    let name = n.name;
    let label = str(".barn/", name);
    let copy = copy_path(dir, name);
    check.count++;
    guard is_dir(copy) else { format(check.problems, "\n  ", label, " is missing"); return; }
    var text: u8[>..] = [];
    let record = read_record(copy, text);
    guard accepts(b, node, record) else {
        if record.ok { format(check.problems, "\n  ", label, " holds ", record.egg, ":", record.version); }
        else { format(check.problems, "\n  ", label, " was not installed by barn"); }
        format(check.problems, ", barn.json asks for ", n.egg, ":", n.version);
        return;
    }
    var laid: u8[>..] = [];
    guard read_sums(egg_dir(eggs, record.egg, record.version), laid) else {
        format(check.problems, "\n  ", record.egg, ":", record.version, " is not in the eggs folder");
        return;
    }
    let detail, edited = edited_detail(eggs, copy, label);
    guard !edited else {
        format(check.problems, "\n  ", label, " was edited", if detail.len > 0 { ":" } else { "" }, detail);
        check.edited = true;
    }
}

fn check_copies(b: Build, dir: const u8[:], eggs: const u8[:]) -> CopyCheck {
    var check = CopyCheck { problems: [] };
    for node in b.used[1..] { if local_path(b, node).len == 0 { check_copy(b, node, dir, eggs, check); } }
    return check;
}

fn copy_problems(check: CopyCheck&) -> u8[>..] {
    guard check.problems.len > 0 else { return str(""); }
    let fix: const u8[:] = if check.edited { "barn install --force restores it" } else { "barn install updates it" };
    return str(".barn/ differs from the eggs folder:", check.problems, "\n", fix);
}

fn installed_names(dir: const u8[:], out: (const u8[:])[>..]&, text: u8[>..]&) {
    list_dir(str(dir, "/.barn"), text);
    each_split(text, '\n') { if it.len > 0 && is_dir(copy_path(dir, it)) { out.push(it); } };
}
