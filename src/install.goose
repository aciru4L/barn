import std;
import os;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.resolve;
import src.files;
import src.checksum;
import src.lock;
import src.uses;

fn path_to_project(main: const u8[:]) -> u8[>..] {
    var depth = 0;
    for c in main { if c == '/' { depth++; } }
    var path: u8[>..] = [];
    if depth == 0 { path.append("./"); }
    for _ in depth { path.append("../"); }
    return path;
}

fn is_barn_import(line: const u8[:], known: const u8[:][:]) -> bool {
    let t = trim(line);
    let quote = find(t, " from \"");
    guard starts_with(t, "import ") && quote > 7 else { return false; }
    var source = t[quote + 7..];
    guard starts_with(source, "./") || starts_with(source, "../") else { return false; }
    if starts_with(source, "./") { source = source[2..]; }
    while starts_with(source, "../") { source = source[3..]; }
    return starts_with(source, ".barn/") || contains(known, trim(t[7..quote]));
}

fn sync_imports(text: const u8[:], imports: const u8[:], known: const u8[:][:], out: u8[>..]&) {
    let body = if ends_with(text, "\n") { text[..text.len - 1] } else { text };
    let lines = split(body, '\n');
    var had_imports = false;
    for line in lines { if is_barn_import(line, known) { had_imports = true; } }
    var placed = false;
    var drop_blank = false;
    for line in lines {
        let t = trim(line);
        if is_barn_import(line, known) {
            if !placed { out.append(imports); placed = true; drop_blank = imports.len == 0; }
            continue;
        }
        if drop_blank {
            drop_blank = false;
            if t.len == 0 { continue; }
        }
        if !had_imports && !placed && !starts_with(t, "//") {
            placed = true;
            if imports.len > 0 {
                if out.len > 0 { out.push('\n'); }
                out.append(imports);
                if t.len > 0 { out.push('\n'); }
            }
        }
        format(out, line, "\n");
    }
    if !placed { out.append(imports); }
}

fn is_edited(old: const Locked[:], name: const u8[:], hash: const u8[:]) -> bool {
    let i = find_locked(old, name);
    return i >= 0 && is_hash(old[i].hash) && old[i].hash != hash;
}

fn laid_sums(eggs: const u8[:], coordinate: const u8[:], out: u8[>..]&) {
    let colon = find(coordinate, ":");
    guard colon > 0 else { return; }
    let v, ok = parse_version(coordinate[colon + 1..]);
    if ok { read_sums(egg_dir(eggs, coordinate[..colon], v), out); }
}

fn import_lines(b: Build, root: const u8[:]) -> u8[>..] {
    let up = path_to_project(root);
    var lines: u8[>..] = [];
    for node in b.used[1..] {
        let name = short_name(b.nodes[node].egg);
        let folder = local_path(b, node);
        let source: u8[>..] = if folder.len == 0 { str(up, ".barn/", name) }
                              else if starts_with(folder, "../") && up == "./" { str(folder, "/src") }
                              else { str(up, folder, "/src") };
        format(lines, "import ", name, " from \"", source, "\";\n");
    }
    return lines;
}

fn update_root_files(p: Project, b: Build, known: const u8[:][:]) -> u8[>..], u8[>..] {
    var note: u8[>..] = [];

    fn update(root: const u8[:], is_given: bool, reports_missing: bool) {
        let path = str(p.dir, "/", root);
        var source: u8[>..] = [];
        guard read_file(path, source) else {
            guard !is_given else { return str(""), str("no ", path) from update_root_files; }
            if reports_missing { format(note, ", no ", root); }
            return;
        }
        var updated: u8[>..] = [];
        sync_imports(source, import_lines(b, root), known, updated);
        guard updated != source else { return; }
        guard write_file(path, updated) else { return str(""), str("cannot write ", path) from update_root_files; }
        format(note, ", ", root, " updated");
    }

    update(main_file(p), p.manifest.main.len > 0, true);
    update(test_file(p), p.manifest.test.len > 0, false);
    return note, str("");
}

fn write_lock(dir: const u8[:], lines: const u8[:]) -> u8[>..] {
    var text: u8[>..] = [];
    lock_text(lines, text);
    var current: u8[>..] = [];
    read_file(lock_path(dir), current);
    guard text != current else { return str(""); }
    guard write_file(lock_path(dir), text) else { return str("cannot write ", lock_path(dir)); }
    return str("");
}

fn install_build(p: Project, b: Build, old: const Locked[:], eggs: const u8[:], force: bool) -> u8[>..] {
    let barn_dir = str(p.dir, "/.barn");
    var lock_lines: u8[>..] = [];
    var report: u8[>..] = [];
    var known: (const u8[:])[>..] = [];
    var kept: (const u8[:])[>..] = [];
    var copies: i64[>..] = [];
    var listing: u8[>..] = [];
    var stale: (const u8[:])[>..] = [];
    var problems: u8[>..] = [];
    var overridable = false;
    for entry in old { known.push(entry.name); }

    fn plan_local(node: i64, name: const u8[:], coordinate: const u8[:]) {
        let folder = local_path(b, node);
        format(lock_lines, coordinate, " ", LOCAL_MARK, "\n");
        format(report, "\n  ", coordinate, "  (", folder, ")");
    }

    fn check_laid_copy(coordinate: const u8[:], name: const u8[:], from: const u8[:], sums: const u8[:],
                             hash: const u8[:], copy_sums: const u8[:]) {
        var laid: u8[>..] = [];
        let locked = find_locked(old, name);
        if !read_sums(from, laid) { format(problems, "\n  ", coordinate, ": no ", SUM_FILE, " in the eggs folder"); }
        else if laid != sums {
            format(problems, "\n  ", coordinate, ": changed in the eggs folder since barn lay:");
            describe_changes(laid, sums, "", problems);
        } else if !force && locked >= 0 && old[locked].coordinate == coordinate && is_hash(old[locked].hash) &&
                  old[locked].hash != hash {
            var detail: u8[>..] = [];
            describe_changes_since(copy_sums, old[locked].hash, sums, "", detail);
            format(problems, "\n  ", coordinate, ": the copy in the eggs folder differs from barn.lock",
                   if detail.len > 0 { ":" } else { "" }, detail);
            overridable = true;
        }
    }

    fn check_edited_copy(name: const u8[:], copy_hash: const u8[:], copy_sums: const u8[:]) {
        guard copy_hash.len > 0 && !force && is_edited(old, name, copy_hash) else { return; }
        let locked = old[find_locked(old, name)];
        var was: u8[>..] = [];
        laid_sums(eggs, locked.coordinate, was);
        var detail: u8[>..] = [];
        describe_changes_since(was, locked.hash, copy_sums, str(".barn/", name, "/"), detail);
        format(problems, "\n  .barn/", name, " was edited", if detail.len > 0 { ":" } else { "" }, detail);
        overridable = true;
    }

    fn plan_laid(node: i64, name: const u8[:], coordinate: const u8[:]) {
        let n = b.nodes[node];
        let from = egg_dir(eggs, n.egg, n.version);
        var sums: u8[>..] = [];
        file_sums(from, sums);
        let hash = sums_hash(sums);
        let copy = str(barn_dir, "/", name);
        var copy_sums: u8[>..] = [];
        let has_copy = is_dir(copy) && file_sums(copy, copy_sums);
        let copy_hash: u8[>..] = if has_copy { sums_hash(copy_sums) } else { str("") };
        check_laid_copy(coordinate, name, from, sums, hash, copy_sums);
        format(lock_lines, coordinate, " ", hash, "\n");
        kept.push(name);
        format(report, "\n  ", coordinate);
        if copy_hash != hash {
            check_edited_copy(name, copy_hash, copy_sums);
            copies.push(node);
        }
    }

    fn plan_eggs() {
        for node in b.used[1..] {
            let n = b.nodes[node];
            let name = short_name(n.egg);
            let coordinate = str(n.egg, ":", n.version);
            known.push(name);
            if local_path(b, node).len > 0 { plan_local(node, name, coordinate); }
            else { plan_laid(node, name, coordinate); }
        }
    }

    fn plan_stale_copies() {
        list_dir(barn_dir, listing);
        each_split(listing, '\n') { name =>
            if name.len > 0 && !contains(kept, name) {
                if !force && is_edited(old, name, egg_hash(str(barn_dir, "/", name))) {
                    format(problems, "\n  .barn/", name, " was edited");
                    overridable = true;
                }
                stale.push(name);
            }
        };
    }

    fn update_copies() {
        guard make_dirs(barn_dir) else { return str("cannot create ", barn_dir) from install_build; }
        for name in stale {
            guard delete_tree(str(barn_dir, "/", name)) else {
                return str("cannot remove .barn/", name) from install_build;
            }
        }
        for node in copies {
            let n = b.nodes[node];
            let to = str(barn_dir, "/", short_name(n.egg));
            guard delete_tree(to) && copy_tree(egg_dir(eggs, n.egg, n.version), to) &&
                  delete_tree(str(to, "/", SUM_FILE)) else {
                return str("cannot copy into ", to) from install_build;
            }
        }
    }

    plan_eggs();
    plan_stale_copies();
    guard problems.len == 0 else {
        return str("nothing was changed:", problems, if overridable { "\n--force overrides" } else { "" });
    }
    update_copies();
    let note, failed = update_root_files(p, b, known);
    guard failed.len == 0 else { return failed; }
    let lock_failed = write_lock(p.dir, lock_lines);
    guard lock_failed.len == 0 else { return lock_failed; }
    let count = b.used.len - 1;
    print("installed ", count, if count == 1 { " egg" } else { " eggs" }, note, report);
    return str("");
}

fn install_project(p: Project, eggs: const u8[:], force: bool) -> u8[>..] {
    var lock_source: u8[>..] = [];
    var old: Locked[>..] = [];
    read_lock(p.dir, lock_source, old);
    return resolve(p.dir, eggs) { return install_build(p, it, old, eggs, force); };
}

fn install(dir: const u8[:], eggs: const u8[:], force: bool) -> u8[>..] {
    return with_project(dir) { return install_project(it, eggs, force); };
}

fn check_copies(dir: const u8[:], eggs: const u8[:], entries: const Locked[:], problems: u8[>..]&) -> i64 {
    var count = 0;
    for entry in entries {
        if is_hash(entry.hash) {
            count++;
            let copy = str(dir, "/.barn/", entry.name);
            var sums: u8[>..] = [];
            if !is_dir(copy) || !file_sums(copy, sums) { format(problems, "\n  .barn/", entry.name, " is missing"); }
            else if sums_hash(sums) != entry.hash {
                var was: u8[>..] = [];
                laid_sums(eggs, entry.coordinate, was);
                var detail: u8[>..] = [];
                describe_changes_since(was, entry.hash, sums, str(".barn/", entry.name, "/"), detail);
                let colon = if detail.len > 0 { ":" } else { "" };
                format(problems, "\n  .barn/", entry.name, " was edited", colon, detail);
            }
        }
    }
    return count;
}

fn verify(dir: const u8[:], eggs: const u8[:]) -> u8[>..] {
    var lock_source: u8[>..] = [];
    var entries: Locked[>..] = [];
    guard read_lock(dir, lock_source, entries) else { return str("no barn.lock in ", dir); }
    var problems: u8[>..] = [];
    let count = check_copies(dir, eggs, entries, problems);
    guard problems.len == 0 else { return str(".barn/ differs from barn.lock:", problems); }
    print("verified ", count, if count == 1 { " egg" } else { " eggs" });
    return str("");
}
