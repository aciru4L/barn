import std;
import os;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.resolve;
import src.files;
import src.checksum;
import src.copies;
import src.uses;
import src.remote;

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

fn import_lines(b: Build, root: const u8[:]) -> u8[>..] {
    let up = path_to_project(root);
    var lines: u8[>..] = [];
    for node in b.used[1..] {
        let name = b.nodes[node].name;
        let folder = local_path(b, node);
        let inner = b.nodes[node].source;
        let package: u8[>..] = if inner == "." { str(folder) } else { str(folder, "/", inner) };
        let source: u8[>..] = if folder.len == 0 { str(up, ".barn/", name) }
                              else if starts_with(folder, "../") && up == "./" { str(package) }
                              else { str(up, package) };
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

    update(main_file(p), p.manifest.main.len > 0, false);
    update(test_file(p), p.manifest.test.len > 0, false);
    return note, str("");
}

fn install_build(p: Project, b: Build, eggs: const u8[:], force: bool) -> u8[>..] {
    let barn_dir = str(p.dir, "/.barn");
    var report: u8[>..] = [];
    var installed_text: u8[>..] = [];
    var known: (const u8[:])[>..] = [];
    var kept: (const u8[:])[>..] = [];
    var copies: i64[>..] = [];
    var stale: (const u8[:])[>..] = [];
    var problems: u8[>..] = [];
    var overridable = false;
    var installed: (const u8[:])[>..] = [];
    installed_names(p.dir, installed, installed_text);
    for name in installed { known.push(name); }

    fn describe_changed(n: Node, coordinate: const u8[:], laid: const u8[:], sums: const u8[:]) {
        format(problems, "\n  ", coordinate, ": changed in the eggs folder since it was stored:");
        describe_changes(laid, sums, "", problems);
        if has_origin_record(eggs, n.egg, n.version) { overridable = true; }
        else { format(problems, "\n  delete ", egg_dir(eggs, n.egg, n.version), " and lay it again"); }
    }

    fn check_laid(n: Node, coordinate: const u8[:], from: const u8[:], sums: u8[>..]&) {
        var laid: u8[>..] = [];
        guard read_sums(from, laid) else {
            format(problems, "\n  ", coordinate, ": no ", SUM_FILE, " in the eggs folder");
            return;
        }
        guard laid != sums else { return; }
        guard force && has_origin_record(eggs, n.egg, n.version) else {
            describe_changed(n, coordinate, laid, sums);
            return;
        }
        let failed = fetch_again(eggs, n.egg, n.version);
        guard failed.len == 0 else { format(problems, "\n  ", coordinate, ": ", failed); return; }
        sums.clear();
        file_sums(from, sums);
    }

    fn check_edited(name: const u8[:]) {
        let copy = copy_path(p.dir, name);
        guard is_dir(copy) && !force else { return; }
        let detail, edited = edited_detail(eggs, copy, str(".barn/", name));
        guard edited else { return; }
        format(problems, "\n  .barn/", name, " was edited", if detail.len > 0 { ":" } else { "" }, detail);
        overridable = true;
    }

    fn is_current(name: const u8[:], egg: const u8[:], v: Version, sums: const u8[:]) -> bool {
        let copy = copy_path(p.dir, name);
        var text: u8[>..] = [];
        let record = read_record(copy, text);
        guard record.ok && record.egg == egg && record.version == v else { return false; }
        var current: u8[>..] = [];
        return file_sums(copy, current) && current == sums;
    }

    fn plan_laid(node: i64, name: const u8[:], coordinate: const u8[:]) {
        let n = b.nodes[node];
        let from = egg_dir(eggs, n.egg, n.version);
        var sums: u8[>..] = [];
        file_sums(from, sums);
        check_laid(n, coordinate, from, sums);
        kept.push(name);
        format(report, "\n  ", coordinate);
        guard !is_current(name, n.egg, n.version, sums) else { return; }
        check_edited(name);
        copies.push(node);
    }

    fn plan_eggs() {
        for node in b.used[1..] {
            let n = b.nodes[node];
            let name = n.name;
            let coordinate = str(n.egg, ":", n.version);
            known.push(name);
            if local_path(b, node).len > 0 { format(report, "\n  ", coordinate, "  (", local_path(b, node), ")"); }
            else { plan_laid(node, name, coordinate); }
        }
    }

    fn plan_stale_copies() {
        for name in installed {
            if !contains(kept, name) {
                check_edited(name);
                stale.push(name);
            }
        }
    }

    fn update_copies() {
        guard make_dirs(barn_dir) || is_dir(barn_dir) else {
            return str("cannot create ", barn_dir) from install_build;
        }
        for name in stale {
            guard delete_tree(copy_path(p.dir, name)) else {
                return str("cannot remove .barn/", name) from install_build;
            }
        }
        for node in copies {
            let n = b.nodes[node];
            let to = copy_path(p.dir, n.name);
            guard delete_tree(to) && copy_tree(egg_dir(eggs, n.egg, n.version), to) &&
                  delete_tree(str(to, "/", SUM_FILE)) && write_record(to, n.egg, n.version) else {
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
    let count = b.used.len - 1;
    print("installed ", count, if count == 1 { " egg" } else { " eggs" }, note, report);
    return str("");
}

fn install(dir: const u8[:], eggs: const u8[:], force: bool) -> u8[>..] {
    return with_project(dir) { p => return resolve(p.dir, eggs) { return install_build(p, it, eggs, force); }; };
}

fn verify(dir: const u8[:], eggs: const u8[:]) -> u8[>..] {
    return resolve(dir, eggs) { b =>
        var check = check_copies(b, dir, eggs);
        let problems = copy_problems(check);
        guard problems.len == 0 else { return problems; }
        print("verified ", check.count, if check.count == 1 { " egg" } else { " eggs" });
        return str("");
    };
}
