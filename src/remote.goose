import std;
import os;
import json;
import base64;
import src.version;
import src.manifest;
import src.project;
import src.eggs;
import src.checksum;
import src.files;
import src.git;
import src.process;
import src.lay;
import src.release;
import src.package_edit;

let TAG_PREFIX = "refs/tags/v";
let PEELED = "^{}";

struct Network { fetches: bool = false, offline: bool = false, priority: i64 = 0, home: u8[>..] }

let PRIORITY_FROM_PACKAGE = 0;
let LOCAL_FIRST = 1;
let REMOTE_FIRST = 2;

var network = Network { home: [] };

struct Tag { version: Version, commit: const u8[:] }

fn config_path() -> u8[>..] { str(network.home, "/config.json") }

fn host_base(host: const u8[:]) -> u8[>..], u8[>..] {
    var text: u8[>..] = [];
    guard read_file(config_path(), text) else { return str("https://", host), str(""); }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, error = json::parse(text, doc, decoded);
    guard root else { return str(""), str(config_path(), ": ", error); }
    let url, has_url = json::as_string(json::member(json::member(json::member(root, "hosts"), host), "url"));
    guard has_url else { return str("https://", host), str(""); }
    return str(url), str("");
}

fn authorization(user: const u8[:], token: const u8[:]) -> u8[>..] {
    var encoded: u8[>..] = [];
    base64::encode(encoded, str(user, ":", token));
    return str("Authorization: Basic ", encoded);
}

fn given_config_count() -> i64 {
    var text: u8[>..] = [];
    guard env("GIT_CONFIG_COUNT", text) else { return 0; }
    let count, ok = parse_int(trim(text));
    return if ok && count > 0 { count } else { 0 };
}

fn pass_tokens() -> u8[>..] {
    var text: u8[>..] = [];
    guard read_file(config_path(), text) else { return str(""); }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, error = json::parse(text, doc, decoded);
    guard root else { return str(config_path(), ": ", error); }
    let hosts = json::member(root, "hosts");
    guard hosts else { return str(""); }
    var count = given_config_count();
    var problem: u8[>..] = [];
    json::each(hosts) { host =>
        let token_node = json::member(host, "token");
        let token, has_token = json::as_string(token_node);
        let user, has_user = json::as_string(json::member(host, "user"));
        let url, has_url = json::as_string(json::member(host, "url"));
        if token_node && !has_token && problem.len == 0 {
            format(problem, config_path(), ": hosts.", host.key, ".token must be a string");
        }
        if has_token && problem.len == 0 {
            let base: u8[>..] = if has_url { str(url) } else { str("https://", host.key) };
            let scope: const u8[:] = if ends_with(base, "/") { "" } else { "/" };
            set_env(str("GIT_CONFIG_KEY_", count), str("http.", base, scope, ".extraHeader"));
            let name: const u8[:] = if has_user { user } else { "x-access-token" };
            set_env(str("GIT_CONFIG_VALUE_", count), authorization(name, token));
            count++;
        }
    };
    guard problem.len == 0 else { return problem; }
    if count > given_config_count() { set_env("GIT_CONFIG_COUNT", str(count)); }
    return str("");
}

fn repo_url(repo: const u8[:]) -> u8[>..], u8[>..] {
    let slash = find(repo, "/");
    let host: const u8[:] = if has_host(repo) { repo[..slash] } else { "github.com" };
    let path: const u8[:] = if has_host(repo) { repo[slash + 1..] } else { repo };
    let base, failed = host_base(host);
    return str(base, "/", path), failed;
}

fn find_tag(tags: const Tag[:], v: Version) -> i64 {
    for t, i in tags { if t.version == v { return i; } }
    return -1;
}

fn add_tag(tags: Tag[>..]&, line: const u8[:]) {
    let tab = find(line, "\t");
    guard tab > 0 && starts_with(line[tab + 1..], TAG_PREFIX) else { return; }
    let commit = line[..tab];
    var name = line[tab + 1 + TAG_PREFIX.len..];
    let peeled = ends_with(name, PEELED);
    if peeled { name = name[..name.len - PEELED.len]; }
    let v, ok = parse_version(name);
    guard ok && is_release(v) else { return; }
    let i = find_tag(tags[..], v);
    if i < 0 { tags.push(Tag { version: v, commit: commit }); }
    else if peeled { tags[i].commit = commit; }
}

fn remote_tags(eggs: const u8[:], repo: const u8[:], tags: Tag[>..]&, text: u8[>..]&) -> u8[>..] {
    let url, failed = repo_url(repo);
    guard failed.len == 0 else { return failed; }
    let command: const u8[:][3] = ["ls-remote", "--tags", url[..]];
    guard run_git(eggs, eggs, command[..], text) == 0 else {
        return str("cannot list the tags of ", repo, " at ", url);
    }
    each_split(text, '\n') { add_tag(tags, it); };
    return str("");
}

fn check_fetched(p: Project, repo: const u8[:], v: Version) -> u8[>..] {
    let found = p.manifest.egg;
    guard found.name == repo else { return str("the repository of ", repo, " holds ", found.name); }
    guard found.version == release_of(v) else { return str(repo, " says version ", found.version, " at ", v); }
    let invalid = check_layable(p);
    guard invalid.len == 0 else { return str(repo, ":", v, " is not a valid egg: ", invalid); }
    return str("");
}

fn plain_entries(clone: const u8[:], names: (const u8[:])[>..]&, listing: u8[>..]&) {
    list_dir(clone, listing);
    each_split(listing, '\n') { file =>
        if ends_with(file, ".goose") && !is_dir(str(clone, "/", file)) {
            let name = file[..file.len - 6];
            var text: u8[>..] = [];
            read_file(str(clone, "/", file), text);
            if valid_name(name) && find(text, str("namespace ", name, ";")) >= 0 { names.push(name); }
        }
    };
}

fn plain_package(clone: const u8[:], repo: const u8[:], v: Version, text: u8[>..]&) -> u8[>..] {
    var names: (const u8[:])[>..] = [];
    var listing: u8[>..] = [];
    plain_entries(clone, names, listing);
    guard names.len == 1 else {
        return str(repo, ":", v, " has no barn.json, and no single <name>.goose at its top declares ",
                   "namespace <name>;: it needs a barn.json");
    }
    let parts = split(repo, '/');
    let manifest = Manifest { egg: Dependency { name: repo, version: v }, owner: parts[parts.len - 2], name: names[0],
                              repo: repo, .. };
    let none: Dependency[>..] = [];
    let no_overrides: Override[>..] = [];
    let no_excludes: (const u8[:])[>..] = [];
    text.append(package_text(manifest, none[..], no_overrides[..], no_excludes[..]));
    return str("");
}

fn stage_fetched(clone: const u8[:], stage: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    var text: u8[>..] = [];
    if !read_file(str(clone, "/barn.json"), text) {
        let missing = plain_package(clone, repo, tag.version, text);
        guard missing.len == 0 else { return missing; }
    }
    var problem: u8[>..] = [];
    let error = with_project_text(clone, text) { p =>
        problem.append(check_fetched(p, repo, tag.version));
        var sums: u8[>..] = [];
        if problem.len == 0 && !stage_egg(p, stage, sums) {
            problem.append(str("cannot copy ", repo, " into ", stage));
        }
    };
    guard error.len == 0 else { return str(repo, ":", tag.version, ": barn.json: ", error[find(error, ": ") + 2..]); }
    guard problem.len == 0 else { return problem; }
    let tag_name = if is_release(tag.version) { release_tag(tag.version) } else { str("") };
    guard write_file(str(stage, "/", ORIGIN_FILE), origin_text(repo, tag_name, tag.commit)) else {
        return str("cannot write ", stage, "/", ORIGIN_FILE);
    }
    return str("");
}

fn clone_path(eggs: const u8[:], repo: const u8[:]) -> u8[>..] {
    let folder = egg_folder(eggs, repo);
    if !is_dir(folder) { make_dirs(folder); }
    return str(folder, "/.fetching-", time_ns(), "-", random_seed());
}

fn store_clone(eggs: const u8[:], repo: const u8[:], clone: const u8[:], tag: Tag, url: const u8[:]) -> u8[>..] {
    let stage = str(clone, "-egg");
    let problem = stage_fetched(clone, stage, repo, tag);
    delete_tree(clone);
    guard problem.len == 0 else { delete_tree(stage); return problem; }
    let target = egg_dir(eggs, repo, tag.version);
    if !rename_file(stage, target) { delete_tree(stage); }
    guard is_dir(target) else { return str("cannot move ", repo, ":", tag.version, " into ", target); }
    print("fetched ", repo, ":", tag.version, " from ", url);
    return str("");
}

fn fetch_tag(eggs: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    let clone = clone_path(eggs, repo);
    let url, _ = repo_url(repo);
    let name = release_tag(tag.version);
    let command: const u8[:][8] = ["clone", "-q", "--depth", "1", "--branch", name[..], url[..], clone[..]];
    var out: u8[>..] = [];
    guard run_git(eggs, eggs, command[..], out) == 0 else {
        delete_tree(clone);
        return str("cannot fetch ", repo, ":", tag.version, " from ", url);
    }
    return store_clone(eggs, repo, clone, tag, url);
}

fn fetch_release(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline && is_release(v) else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "\n"));
        return str("");
    }
    let i = find_tag(tags[..], v);
    guard i >= 0 else { return str(""); }
    return fetch_tag(eggs, repo, tags[i]);
}

fn recorded_commit(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    var text: u8[>..] = [];
    guard read_file(str(egg_dir(eggs, repo, v), "/", ORIGIN_FILE), text) else { return str(""); }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, _ = json::parse(text, doc, decoded);
    let commit, _ = json::as_string(json::member(root, "commit"));
    return str(commit);
}

fn moved_tag(eggs: const u8[:], repo: const u8[:], tag: Tag) -> u8[>..] {
    guard is_released(eggs, repo, tag.version) else { return str(""); }
    let recorded = recorded_commit(eggs, repo, tag.version);
    guard recorded.len > 0 && recorded != tag.commit else { return str(""); }
    return str("the tag v", tag.version, " of ", repo, " now points at ", tag.commit, ", not ", recorded,
               ": a release must never change");
}

fn add_known(versions: Version[>..]&, v: Version) {
    for known in versions { if known == v { return; } }
    versions.push(v);
}

fn known_releases(eggs: const u8[:], repo: const u8[:], versions: Version[>..]&) -> u8[>..] {
    each_version(eggs, repo) { if is_released(eggs, repo, it) { add_known(versions, it); } };
    guard network.fetches && !network.offline else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "; using the releases in ~/.barn/eggs\n"));
        return str("");
    }
    for tag in tags {
        let moved = moved_tag(eggs, repo, tag);
        guard moved.len == 0 else { return moved; }
        add_known(versions, tag.version);
    }
    return str("");
}

fn newest_known(versions: const Version[:], like: Version, compatible_only: bool) -> Version, bool {
    var newest = Version {..};
    var found = false;
    for v in versions {
        if (!compatible_only || compatible(v, like)) && (!found || is_newer(v, newest)) {
            newest = v;
            found = true;
        }
    }
    return newest, found;
}

fn asks_repository_first(m: Manifest) -> bool {
    guard network.priority == PRIORITY_FROM_PACKAGE else { return network.priority == REMOTE_FIRST; }
    return m.remote_first;
}

fn check_with_repository(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline && is_release(v) else { return str(""); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else {
        write_stderr(str("warning: ", failed, "; using the release in ~/.barn/eggs\n"));
        return str("");
    }
    let i = find_tag(tags[..], v);
    guard i >= 0 else { return str(""); }
    return moved_tag(eggs, repo, tags[i]);
}

fn apply_setting(setting: const u8[:]) -> u8[>..] {
    guard setting == "local_priority=true" || setting == "local_priority=false" else {
        return str("--set supports local_priority=true and local_priority=false, not '", setting, "'");
    }
    network.priority = if setting == "local_priority=true" { LOCAL_FIRST } else { REMOTE_FIRST };
    return str("");
}

fn has_origin_record(eggs: const u8[:], repo: const u8[:], v: Version) -> bool {
    file_exists(str(egg_dir(eggs, repo, v), "/", ORIGIN_FILE))
}

fn fetch_again(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline else { return str("cannot fetch ", repo, ":", v, " again offline"); }
    var text: u8[>..] = [];
    var tags: Tag[>..] = [];
    let failed = remote_tags(eggs, repo, tags, text);
    guard failed.len == 0 else { return failed; }
    let i = find_tag(tags[..], v);
    guard i >= 0 else { return str("the repository of ", repo, " no longer has v", v); }
    let moved = moved_tag(eggs, repo, tags[i]);
    guard moved.len == 0 else { return moved; }
    guard delete_tree(egg_dir(eggs, repo, v)) else { return str("cannot remove ", egg_dir(eggs, repo, v)); }
    return fetch_tag(eggs, repo, tags[i]);
}

struct Snapshot { version: Version, unreachable: bool = false, message: u8[>..] }

fn git_line(clone: const u8[:], eggs: const u8[:], command: const u8[:][:]) -> u8[>..] {
    var out: u8[>..] = [];
    guard run_git(clone, eggs, command, out) == 0 else { return str(""); }
    return str(trim(out));
}

fn version_at(clone: const u8[:], eggs: const u8[:], commit: const u8[:]) -> Version, bool {
    let file = str(commit, ":barn.json");
    let command: const u8[:][2] = ["show", file[..]];
    var text: u8[>..] = [];
    guard run_git(clone, eggs, command[..], text) == 0 else { return Version {..}, false; }
    var doc: json::Node[>..] = [];
    var decoded: u8[>..] = [];
    let root, _ = json::parse(text, doc, decoded);
    let given, has_version = json::as_string(json::member(root, "version"));
    guard has_version else { return Version {..}, false; }
    let v, ok = parse_version(given);
    return v, ok && is_release(v);
}

fn commit_stamp(clone: const u8[:], eggs: const u8[:], commit: const u8[:]) -> i64 {
    let command: const u8[:][4] = ["log", "-1", "--format=%ct", commit];
    let seconds, ok = parse_int(git_line(clone, eggs, command[..]));
    guard ok else { return 0; }
    return utc_stamp(seconds * 1000000000);
}

fn newest_commit_of(clone: const u8[:], eggs: const u8[:], release: Version) -> u8[>..] {
    let command: const u8[:][6] = ["log", "--first-parent", "--format=%H", "HEAD", "--", "barn.json"];
    var listing: u8[>..] = [];
    guard run_git(clone, eggs, command[..], listing) == 0 else { return str(""); }
    let changes = split(trim(listing), '\n');
    for change, k in changes {
        let v, ok = version_at(clone, eggs, change);
        if ok && v == release {
            let newest: u8[>..] = if k == 0 { str("HEAD") } else { str(changes[k - 1], "^") };
            let resolve_command: const u8[:][2] = ["rev-parse", newest[..]];
            return git_line(clone, eggs, resolve_command[..]);
        }
    }
    return str("");
}

fn exact_commit(clone: const u8[:], eggs: const u8[:], wanted: Version) -> u8[>..] {
    var hash: u8[>..] = [];
    format_hash(hash, wanted.hash);
    let reference = str(hash, "^{commit}");
    let command: const u8[:][4] = ["rev-parse", "--verify", "-q", reference[..]];
    let commit = git_line(clone, eggs, command[..]);
    guard commit.len > 0 && commit_stamp(clone, eggs, commit) == wanted.snapshot else { return str(""); }
    let v, ok = version_at(clone, eggs, commit);
    guard ok && v == release_of(wanted) else { return str(""); }
    return commit;
}

fn snapshot_of(clone: const u8[:], eggs: const u8[:], release: Version, commit: const u8[:]) -> Version {
    var snapshot = release_of(release);
    snapshot.snapshot = commit_stamp(clone, eggs, commit);
    let hash, _ = parse_hash(commit[..HASH_DIGITS]);
    snapshot.hash = hash;
    return snapshot;
}

fn fetch_snapshot(eggs: const u8[:], repo: const u8[:], wanted: Version) -> Snapshot {
    var result = Snapshot { version: wanted, message: [] };
    let url, failed = repo_url(repo);
    guard failed.len == 0 else { result.message.append(failed); return result; }
    let clone = clone_path(eggs, repo);
    let command: const u8[:][5] = ["clone", "-q", "--no-checkout", url[..], clone[..]];
    var out: u8[>..] = [];
    guard run_git(eggs, eggs, command[..], out) == 0 else {
        delete_tree(clone);
        result.unreachable = true;
        format(result.message, "cannot fetch the snapshots of ", repo, " from ", url);
        return result;
    }
    let commit = if is_snapshot(wanted) { exact_commit(clone, eggs, wanted) }
                 else { newest_commit_of(clone, eggs, release_of(wanted)) };
    guard commit.len > 0 else { delete_tree(clone); return result; }
    let snapshot = snapshot_of(clone, eggs, wanted, commit);
    result.version = snapshot;
    guard !is_dir(egg_dir(eggs, repo, snapshot)) else { delete_tree(clone); return result; }
    let checkout: const u8[:][3] = ["checkout", "-q", commit[..]];
    var ignored: u8[>..] = [];
    guard run_git(clone, eggs, checkout[..], ignored) == 0 else {
        delete_tree(clone);
        format(result.message, "cannot check out ", commit, " of ", repo);
        return result;
    }
    result.message.append(store_clone(eggs, repo, clone, Tag { version: snapshot, commit: commit }, url));
    return result;
}

fn newest_laid_snapshot(eggs: const u8[:], repo: const u8[:], v: Version) -> Version {
    var newest = release_of(v);
    each_laid(eggs, repo) {
        let candidate = is_snapshot(it) && release_of(it) == release_of(v) && !has_origin_record(eggs, repo, it);
        if candidate && (!is_snapshot(newest) || is_newer(it, newest)) {
            newest = it;
        }
    };
    return newest;
}

fn chosen_version(eggs: const u8[:], repo: const u8[:], wanted: Version, remote_first: bool) -> Version, u8[>..] {
    guard wants_newest_snapshot(wanted) else { return wanted, str(""); }
    let laid = newest_laid_snapshot(eggs, repo, wanted);
    guard remote_first || !is_snapshot(laid) else { return laid, str(""); }
    guard network.fetches && !network.offline else { return concrete_version(eggs, repo, wanted), str(""); }
    let found = fetch_snapshot(eggs, repo, wanted);
    guard found.unreachable || found.message.len == 0 else { return wanted, str(found.message); }
    guard is_snapshot(found.version) else {
        let local = concrete_version(eggs, repo, wanted);
        if found.unreachable && is_snapshot(local) {
            write_stderr(str("warning: ", found.message, "; using ", repo, ":", local, ", which may be stale\n"));
        } else if found.unreachable { write_stderr(str("warning: ", found.message, "\n")); }
        return local, str("");
    }
    return found.version, str("");
}

fn fetch_exact_snapshot(eggs: const u8[:], repo: const u8[:], v: Version) -> u8[>..] {
    guard network.fetches && !network.offline && is_snapshot(v) else { return str(""); }
    let found = fetch_snapshot(eggs, repo, v);
    guard !found.unreachable else {
        write_stderr(str("warning: ", found.message, "\n"));
        return str("");
    }
    return str(found.message);
}
