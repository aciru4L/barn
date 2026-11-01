import std;
import os;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.remote;
import src.package_edit;
import src.install;
import src.copies;
import src.uses;

fn change_and_install(dir: const u8[:], eggs: const u8[:], original: const u8[:], updated: const u8[:],
                      force: bool, done: const u8[:]) -> u8[>..] {
    let path = package_path(dir);
    guard write_file(path, updated) else { return str("cannot write ", path); }
    let error = install(dir, eggs, force);
    guard error.len == 0 else {
        guard write_file(path, original) else { return str(error, "\ncannot restore ", path); }
        return str(error, "\nbarn.json unchanged");
    }
    print(done);
    return str("");
}

fn missing_release(eggs: const u8[:], egg: const u8[:]) -> u8[>..] {
    let found, has_snapshots = newest_with_snapshot(eggs, egg);
    guard has_snapshots else { return str(egg, " not found"); }
    var newest = found;
    newest.snapshot = NEWEST_SNAPSHOT;
    return str(egg, " has no release; ", egg, ":", newest, " adds its newest snapshot");
}

fn add_to_project(p: Project, egg: const u8[:], v: Version, done: u8[>..]&) -> u8[>..] {
    let index = find_dependency(p, egg);
    guard index >= 0 && p.dependencies[index].name == egg else {
        format(done, "\nadded ", egg, ":", v);
        return insert_dependency(p, Dependency { name: egg, version: v });
    }
    let d = p.dependencies[index];
    guard d.version != v else {
        format(done, "\n", egg, ":", v, " unchanged");
        return str(p.text);
    }
    format(done, "\n", egg, ": ", d.version, " -> ", v);
    if !compatible(d.version, v) { done.append(" (incompatible)"); }
    return replace_dependency(p, d, v);
}

fn add(dir: const u8[:], eggs: const u8[:], specs: const u8[:][:], force: bool) -> u8[>..] {
    var original: u8[>..] = [];
    guard read_file(package_path(dir), original) else { return str("no barn.json in ", dir); }
    var current = str(original);
    var done: u8[>..] = [];
    for spec in specs {
        let colon = find(spec, ":");
        let egg = without_github(if colon < 0 { spec } else { spec[..colon] });
        let problem = repo_problem(egg);
        guard problem.len == 0 else { return problem; }
        var v = Version {..};
        if colon >= 0 {
            let parsed, ok = parse_version(spec[colon + 1..]);
            guard ok else { return str("bad version in '", spec, "'"); }
            v = parsed;
        } else {
            var releases: Version[>..] = [];
            let failed = known_releases(eggs, egg, releases);
            guard failed.len == 0 else { return failed; }
            let found, released = newest_known(releases[..], Version {..}, false);
            guard released else { return missing_release(eggs, egg); }
            v = found;
        }
        var next: u8[>..] = [];
        let error = with_project_text(dir, current) {
            guard egg != it.manifest.egg.name else { return str(egg, " is the project itself"); }
            next.append(add_to_project(it, egg, v, done));
        };
        guard error.len == 0 else { return error; }
        current.clear();
        current.append(next);
    }
    guard current != original else { print(done[1..]); return str(""); }
    return change_and_install(dir, eggs, original, current, force, done[1..]);
}

fn warn_about_lost_uses(dir: const u8[:], package: const u8[:], before: const u8[:][:]) {
    var text: u8[>..] = [];
    var after: (const u8[:])[>..] = [];
    installed_names(dir, after, text);
    var lost: (const u8[:])[>..] = [];
    for name in before { if !contains(after[..], name) { lost.push(name); } }
    var uses: u8[>..] = [];
    var count = 0;
    with_project_text(dir, package) {
        var folders: (const u8[:])[>..] = [];
        local_folders(it, folders);
        count = uses_of(dir, lost, folders, uses);
    };
    if count > 0 { write_stderr(str("warning: no longer in .barn/, but used:", uses, "\n")); }
}

fn remove(dir: const u8[:], eggs: const u8[:], specs: const u8[:][:], force: bool) -> u8[>..] {
    var original: u8[>..] = [];
    guard read_file(package_path(dir), original) else { return str("no barn.json in ", dir); }
    var current = str(original);
    var installed_text: u8[>..] = [];
    var before: (const u8[:])[>..] = [];
    installed_names(dir, before, installed_text);
    var done: u8[>..] = [];
    for spec in specs {
        var next: u8[>..] = [];
        let error = with_project_text(dir, current) {
            let index = find_dependency(it, spec);
            guard index >= 0 else { return str("barn.json has no dependency ", spec); }
            format(done, "\nremoved ", it.dependencies[index]);
            next.append(remove_dependency(it, it.dependencies[index]));
        };
        guard error.len == 0 else { return error; }
        current.clear();
        current.append(next);
    }
    let error = change_and_install(dir, eggs, original, current, force, done[1..]);
    guard error.len == 0 else { return error; }
    warn_about_lost_uses(dir, current, before[..]);
    return str("");
}

fn upgrade_project(p: Project, eggs: const u8[:], specs: const u8[:][:], updated: u8[>..]&, done: u8[>..]&,
                   available: u8[>..]&) -> u8[>..] {
    var wanted: bool[>..] = [];
    for _ in p.dependencies.len { wanted.push(specs.len == 0); }
    for spec in specs {
        let index = find_dependency(p, spec);
        guard index >= 0 else { return str("barn.json has no dependency ", spec); }
        wanted[index] = true;
    }
    var dependencies: Dependency[>..] = [];
    for d, i in p.dependencies {
        var kept = d;
        if wanted[i] {
            var releases: Version[>..] = [];
            let failed = known_releases(eggs, d.name, releases);
            guard failed.len == 0 else { return failed; }
            let compatible_release, has_compatible = newest_known(releases[..], d.version, true);
            if has_compatible && is_newer(compatible_release, d.version) {
                format(done, "\n", d.name, ": ", d.version, " -> ", compatible_release);
                kept.version = compatible_release;
            }
            let newest, has_newest = newest_known(releases[..], d.version, false);
            if has_newest && !compatible(newest, d.version) && is_newer(newest, d.version) {
                format(available, "\n", d.name, ":", newest, " available (incompatible)");
            }
        }
        dependencies.push(kept);
    }
    updated.append(with_dependencies(p, dependencies[..]));
    return str("");
}

fn upgrade(dir: const u8[:], eggs: const u8[:], specs: const u8[:][:], force: bool) -> u8[>..] {
    var original: u8[>..] = [];
    guard read_file(package_path(dir), original) else { return str("no barn.json in ", dir); }
    var updated: u8[>..] = [];
    var done: u8[>..] = [];
    var available: u8[>..] = [];
    var failed: u8[>..] = [];
    let error = with_project_text(dir, original) {
        failed.append(upgrade_project(it, eggs, specs, updated, done, available));
    };
    guard error.len == 0 else { return error; }
    guard failed.len == 0 else { return failed; }
    guard done.len > 0 else { print("up to date", available); return str(""); }
    return change_and_install(dir, eggs, original, updated, force, str(done[1..], available));
}
