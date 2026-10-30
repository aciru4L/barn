import std;
import os;
import src.version;
import src.manifest;
import src.project;
import src.repository;
import src.checksum;
import src.files;

fn check_layable(p: Project) -> u8[>..] {
    let name = short_name(p.manifest.egg.name);
    var entry: u8[>..] = [];
    guard read_file(str(p.dir, "/src/", name, ".goose"), entry) else { return str("no src/", name, ".goose"); }
    guard find(entry, str("namespace ", name, ";")) >= 0 else {
        return str("src/", name, ".goose needs namespace ", name, ";");
    }
    for reserved in ["barn.pkg", SUM_FILE] {
        guard !file_exists(str(p.dir, "/src/", reserved)) else { return str("src/", reserved, " is not allowed"); }
    }
    var listing: u8[>..] = [];
    list_dir(str(p.dir, "/src"), listing);
    var reserved_folder: u8[>..] = [];
    each_split(listing, '\n') {
        if starts_with(it, SNAPSHOT_PREFIX) && reserved_folder.len == 0 { reserved_folder.append(it); }
    };
    guard reserved_folder.len == 0 else { return str("src/", reserved_folder, " is not allowed"); }
    return str("");
}

fn stage_egg(p: Project, stage: const u8[:], sums: u8[>..]&) -> bool {
    let staged = copy_tree(str(p.dir, "/src"), stage) && write_file(str(stage, "/barn.pkg"), p.text) &&
                 file_sums(stage, sums) && write_file(str(stage, "/", SUM_FILE), sums);
    if !staged { delete_tree(stage); }
    return staged;
}

fn move_release_files(claim: const u8[:], base: const u8[:]) -> bool {
    var leftovers: u8[>..] = [];
    list_dir(base, leftovers);
    each_split(leftovers, '\n') { if it.len > 0 && !left_out(it) { delete_tree(str(base, "/", it)); } };
    var entries: u8[>..] = [];
    list_dir(claim, entries);
    var moved = true;
    each_split(entries, '\n') {
        if it.len > 0 && it != SUM_FILE && !rename_file(str(claim, "/", it), str(base, "/", it)) { moved = false; }
    };
    return moved && rename_file(str(claim, "/", SUM_FILE), str(base, "/", SUM_FILE));
}

fn release_staged(p: Project, repository: const u8[:], stage: const u8[:], base: const u8[:]) -> u8[>..] {
    let egg = p.manifest.egg;
    let claim = str(base, "/.releasing");
    guard rename_file(stage, claim) else {
        delete_tree(stage);
        return str("another barn lay --release of ", egg, " is under way, or one stopped midway: ",
                   "if none is running, delete ", claim);
    }
    guard !is_sealed(repository, egg.name, egg.version) else {
        delete_tree(claim);
        return str(egg, " is already released");
    }
    let moved = move_release_files(claim, base);
    delete_tree(claim);
    guard moved else { return str("cannot move the release into ", base); }
    return str("");
}

fn snapshot_staged(p: Project, repository: const u8[:], stage: const u8[:]) -> u8[>..], Version {
    var snapshot = p.manifest.egg.version;
    snapshot.snapshot = utc_stamp(time_ns());
    guard rename_file(stage, egg_dir(repository, p.manifest.egg.name, snapshot)) else {
        delete_tree(stage);
        return str(p.manifest.egg.name, ":", snapshot, " already exists: lay again"), snapshot;
    }
    return str(""), snapshot;
}

fn lay_project(p: Project, repository: const u8[:], release: bool) -> u8[>..] {
    let invalid = check_layable(p);
    guard invalid.len == 0 else { return invalid; }
    return lay_checked(p, repository, release);
}

fn lay_checked(p: Project, repository: const u8[:], release: bool) -> u8[>..] {
    let egg = p.manifest.egg;
    guard !release || !is_sealed(repository, egg.name, egg.version) else { return str(egg, " is already released"); }
    let base = egg_dir(repository, egg.name, egg.version);
    guard make_dirs(base) else { return str("cannot create ", base); }
    let stage = str(base, "/.laying-", time_ns(), "-", random_seed());
    var sums: u8[>..] = [];
    guard stage_egg(p, stage, sums) else { return str("cannot copy the egg into ", stage); }
    guard !release else {
        let failed = release_staged(p, repository, stage, base);
        guard failed.len == 0 else { return failed; }
        print("released ", egg, "  ", sums_hash(sums));
        return str("");
    }
    let failed, snapshot = snapshot_staged(p, repository, stage);
    guard failed.len == 0 else { return failed; }
    print("laid ", egg.name, ":", snapshot, "  ", sums_hash(sums));
    return str("");
}

fn lay(dir: const u8[:], repository: const u8[:], release: bool) -> u8[>..] {
    return with_project(dir) { return lay_project(it, repository, release); };
}
