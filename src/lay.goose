import std;
import os;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.checksum;
import src.files;
import src.contents;

fn check_layable(p: Project) -> u8[>..] {
    let name = short_name(p.manifest.egg.name);
    guard is_dir(source_dir(p)) else { return str("the source folder ", source_of(p.manifest), " does not exist"); }
    let entry_file = entry_path(p);
    var entry: u8[>..] = [];
    guard read_file(str(p.dir, "/", entry_file), entry) else { return str("no ", entry_file); }
    guard find(entry, str("namespace ", name, ";")) >= 0 else {
        return str(entry_file, " needs namespace ", name, ";");
    }
    return str("");
}

fn stage_egg(p: Project, stage: const u8[:], sums: u8[>..]&) -> bool {
    let staged = copy_egg_files(p, stage) && write_file(str(stage, "/barn.json"), p.text) &&
                 file_sums(stage, sums) && write_file(str(stage, "/", SUM_FILE), sums);
    if !staged { delete_tree(stage); }
    return staged;
}

fn content_hash(sums: const u8[:]) -> i64 {
    let full = sums_hash(sums);
    let hash, _ = parse_hash(full[HASH_PREFIX.len..HASH_PREFIX.len + HASH_DIGITS]);
    return hash;
}

fn laid_snapshot(eggs: const u8[:], egg: const u8[:], release: Version, sums: const u8[:]) -> Version, bool {
    let hash = content_hash(sums);
    var found = Version {..};
    var is_laid = false;
    each_laid(eggs, egg) {
        if !is_laid && is_snapshot(it) && release_of(it) == release && it.hash == hash {
            var laid: u8[>..] = [];
            if read_sums(egg_dir(eggs, egg, it), laid) && laid == sums { found = it; is_laid = true; }
        }
    };
    return found, is_laid;
}

fn place_staged(stage: const u8[:], target: const u8[:], taken: const u8[:]) -> u8[>..] {
    guard !is_dir(target) else {
        delete_tree(stage);
        return str(taken);
    }
    guard rename_file(stage, target) else {
        delete_tree(stage);
        guard !is_dir(target) else { return str(taken); }
        return str("cannot move the egg into ", target);
    }
    return str("");
}

fn lay_release(p: Project, eggs: const u8[:], stage: const u8[:], sums: const u8[:]) -> u8[>..] {
    let egg = p.manifest.egg;
    let failed = place_staged(stage, egg_dir(eggs, egg.name, egg.version), str(egg, " is already released"));
    guard failed.len == 0 else { return failed; }
    print("released ", egg, "  ", sums_hash(sums));
    return str("");
}

fn lay_snapshot(p: Project, eggs: const u8[:], stage: const u8[:], sums: const u8[:]) -> u8[>..] {
    let egg = p.manifest.egg;
    let existing, is_laid = laid_snapshot(eggs, egg.name, egg.version, sums);
    guard !is_laid else {
        delete_tree(stage);
        print(egg.name, ":", existing, " is already laid");
        return str("");
    }
    var snapshot = egg.version;
    snapshot.snapshot = utc_stamp(time_ns());
    snapshot.hash = content_hash(sums);
    let taken = str(egg.name, ":", snapshot, " already exists: lay again");
    let failed = place_staged(stage, egg_dir(eggs, egg.name, snapshot), taken);
    guard failed.len == 0 else { return failed; }
    print("laid ", egg.name, ":", snapshot, "  ", sums_hash(sums));
    return str("");
}

fn lay_project(p: Project, eggs: const u8[:], release: bool) -> u8[>..] {
    let invalid = check_layable(p);
    guard invalid.len == 0 else { return invalid; }
    let egg = p.manifest.egg;
    guard !release || !is_released(eggs, egg.name, egg.version) else { return str(egg, " is already released"); }
    let folder = str(eggs, "/", egg.name);
    guard make_dirs(folder) || is_dir(folder) else { return str("cannot create ", folder); }
    let stage = str(folder, "/.laying-", time_ns(), "-", random_seed());
    var sums: u8[>..] = [];
    guard stage_egg(p, stage, sums) else { return str("cannot copy the egg into ", stage); }
    guard !release else { return lay_release(p, eggs, stage, sums); }
    return lay_snapshot(p, eggs, stage, sums);
}

fn lay(dir: const u8[:], eggs: const u8[:], release: bool) -> u8[>..] {
    return with_project(dir) { return lay_project(it, eggs, release); };
}
