import std;
import os;
import src.version;
import src.checksum;

fn egg_dir(repository: const u8[:], egg: const u8[:], v: Version) -> u8[>..] {
    var path = str(repository, "/", egg, "/", release_of(v));
    if is_snapshot(v) { format(path, "/", SNAPSHOT_PREFIX); format_stamp(path, v.snapshot); }
    return path;
}

fn is_released(repository: const u8[:], egg: const u8[:], v: Version) -> bool {
    file_exists(str(egg_dir(repository, egg, release_of(v)), "/barn.pkg"))
}

fn is_sealed(repository: const u8[:], egg: const u8[:], v: Version) -> bool {
    file_exists(str(egg_dir(repository, egg, release_of(v)), "/", SUM_FILE))
}

fn each_version<F>(repository: const u8[:], egg: const u8[:]) {
    var listing: u8[>..] = [];
    list_dir(str(repository, "/", egg), listing);
    each_split(listing, '\n') {
        let v, ok = parse_version(it);
        if ok && is_release(v) { F(v); }
    };
}

fn newest_snapshot(repository: const u8[:], egg: const u8[:], v: Version) -> Version {
    var listing: u8[>..] = [];
    list_dir(egg_dir(repository, egg, release_of(v)), listing);
    var newest = release_of(v);
    each_split(listing, '\n') {
        if starts_with(it, SNAPSHOT_PREFIX) {
            let stamp, ok = parse_stamp(it[SNAPSHOT_PREFIX.len..]);
            if ok && stamp > newest.snapshot { newest.snapshot = stamp; }
        }
    };
    return newest;
}

fn has_snapshot(repository: const u8[:], egg: const u8[:], v: Version) -> bool {
    is_snapshot(newest_snapshot(repository, egg, v))
}

fn concrete_version(repository: const u8[:], egg: const u8[:], wanted: Version) -> Version {
    guard !is_snapshot(wanted) else { return wanted; }
    if is_release(wanted) && is_released(repository, egg, wanted) { return wanted; }
    let snapshot = newest_snapshot(repository, egg, wanted);
    if is_snapshot(snapshot) { return snapshot; }
    return wanted;
}

fn newest_release(repository: const u8[:], egg: const u8[:]) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(repository, egg) {
        if is_released(repository, egg, it) && (!found || is_newer(it, newest)) { newest = it; found = true; }
    };
    return newest, found;
}

fn newest_compatible_release(repository: const u8[:], egg: const u8[:], like: Version) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(repository, egg) {
        if compatible(it, like) && is_released(repository, egg, it) && (!found || is_newer(it, newest)) {
            newest = it;
            found = true;
        }
    };
    return newest, found;
}

fn newest_with_snapshot(repository: const u8[:], egg: const u8[:]) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(repository, egg) {
        if (!found || is_newer(it, newest)) && has_snapshot(repository, egg, it) { newest = it; found = true; }
    };
    return newest, found;
}
