import std;
import os;
import src.version;
import src.manifest;

fn egg_folder(eggs: const u8[:], egg: const u8[:]) -> u8[>..] {
    if has_host(egg) { return str(eggs, "/", egg); }
    return str(eggs, "/", GITHUB, egg);
}

fn egg_dir(eggs: const u8[:], egg: const u8[:], v: Version) -> u8[>..] { str(egg_folder(eggs, egg), "/", v) }

fn is_released(eggs: const u8[:], egg: const u8[:], v: Version) -> bool {
    file_exists(str(egg_dir(eggs, egg, release_of(v)), "/barn.json"))
}

fn each_laid<F>(eggs: const u8[:], egg: const u8[:]) {
    var listing: u8[>..] = [];
    list_dir(egg_folder(eggs, egg), listing);
    each_split(listing, '\n') {
        let v, ok = parse_version(it);
        if ok && !wants_newest_snapshot(v) { F(v); }
    };
}

fn each_version<F>(eggs: const u8[:], egg: const u8[:]) { each_laid(eggs, egg) { F(release_of(it)); }; }

fn newest_snapshot(eggs: const u8[:], egg: const u8[:], v: Version) -> Version {
    var newest = release_of(v);
    each_laid(eggs, egg) {
        if is_snapshot(it) && release_of(it) == release_of(v) && (!is_snapshot(newest) || is_newer(it, newest)) {
            newest = it;
        }
    };
    return newest;
}

fn has_snapshot(eggs: const u8[:], egg: const u8[:], v: Version) -> bool {
    is_snapshot(newest_snapshot(eggs, egg, v))
}

fn concrete_version(eggs: const u8[:], egg: const u8[:], wanted: Version) -> Version {
    guard wants_newest_snapshot(wanted) else { return wanted; }
    let snapshot = newest_snapshot(eggs, egg, wanted);
    if is_snapshot(snapshot) { return snapshot; }
    return wanted;
}

fn newest_release(eggs: const u8[:], egg: const u8[:]) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(eggs, egg) {
        if is_released(eggs, egg, it) && (!found || is_newer(it, newest)) { newest = it; found = true; }
    };
    return newest, found;
}

fn newest_compatible_release(eggs: const u8[:], egg: const u8[:], like: Version) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(eggs, egg) {
        if compatible(it, like) && is_released(eggs, egg, it) && (!found || is_newer(it, newest)) {
            newest = it;
            found = true;
        }
    };
    return newest, found;
}

fn newest_with_snapshot(eggs: const u8[:], egg: const u8[:]) -> Version, bool {
    var newest = Version {..};
    var found = false;
    each_version(eggs, egg) {
        if (!found || is_newer(it, newest)) && has_snapshot(eggs, egg, it) { newest = it; found = true; }
    };
    return newest, found;
}
