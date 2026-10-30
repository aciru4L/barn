import std;

struct Version { major: i32, minor: i32, patch: i32, snapshot: i64 = 0 }

let NEWEST_SNAPSHOT = -1;
let SNAPSHOT_MARK = "_snapshot";
let SNAPSHOT_PREFIX = "_snapshot_";

fn is_release(v: Version) -> bool { v.snapshot == 0 }
fn is_snapshot(v: Version) -> bool { v.snapshot > 0 }
fn wants_newest_snapshot(v: Version) -> bool { v.snapshot == NEWEST_SNAPSHOT }

fn release_of(v: Version) -> Version { Version { major: v.major, minor: v.minor, patch: v.patch } }

fn format_stamp(out: u8[>..]&, stamp: i64) {
    let digits = str(stamp);
    format(out, digits[..8], "T", digits[8..], "Z");
}

fn format(out: u8[>..]&, v: Version) {
    format(out, v.major, ".", v.minor, ".", v.patch);
    if wants_newest_snapshot(v) { out.append(SNAPSHOT_MARK); }
    else if is_snapshot(v) { format(out, SNAPSHOT_PREFIX); format_stamp(out, v.snapshot); }
}

fn compare(a: Version, b: Version) -> i64 {
    if a.major != b.major { return a.major as i64 - b.major; }
    if a.minor != b.minor { return a.minor as i64 - b.minor; }
    if a.patch != b.patch { return a.patch as i64 - b.patch; }
    if a.snapshot == b.snapshot { return 0; }
    if is_release(a) { return 1; }
    if is_release(b) { return -1; }
    return a.snapshot - b.snapshot;
}

fn is_newer(a: Version, b: Version) -> bool { compare(a, b) > 0 }

fn compatible(a: Version, b: Version) -> bool {
    if a.major != b.major { return false; }
    if a.major > 0 { return true; }
    if a.minor != b.minor { return false; }
    return a.minor > 0 || a.patch == b.patch;
}

fn all_digits(s: const u8[:]) -> bool {
    for c in s { guard c >= '0' && c <= '9' else { return false; } }
    return s.len > 0;
}

fn parse_stamp(s: const u8[:]) -> i64, bool {
    guard s.len == 16 && s[8] == 'T' && s[15] == 'Z' && all_digits(s[..8]) && all_digits(s[9..15]) else {
        return 0, false;
    }
    let date, date_ok = parse_int(s[..8]);
    let time, time_ok = parse_int(s[9..15]);
    return date * 1000000 + time, date_ok && time_ok && date >= 10000101;
}

fn parse_snapshot_suffix(suffix: const u8[:]) -> i64, bool {
    if suffix.len == 0 { return NEWEST_SNAPSHOT, true; }
    guard suffix[0] == '_' else { return 0, false; }
    return parse_stamp(suffix[1..]);
}

fn parse_version(text: const u8[:]) -> Version, bool {
    var numbers = text;
    var snapshot = 0;
    let mark = find(text, SNAPSHOT_MARK);
    if mark >= 0 {
        numbers = text[..mark];
        let stamp, ok = parse_snapshot_suffix(text[mark + SNAPSHOT_MARK.len..]);
        guard ok else { return Version {..}, false; }
        snapshot = stamp;
    }
    let parts = split(numbers, '.');
    guard parts.len == 3 else { return Version {..}, false; }
    var values: i32[3] = [0, 0, 0];
    for part, i in parts {
        let n, ok = parse_int(part);
        guard ok && all_digits(part) && n < 1000000 else { return Version {..}, false; }
        values[i] = n as i32;
    }
    return Version { major: values[0], minor: values[1], patch: values[2], snapshot: snapshot }, true;
}

fn utc_stamp(nanoseconds: i64) -> i64 {
    let seconds = nanoseconds / 1000000000;
    let days = seconds / 86400;
    let of_day = seconds % 86400;
    let shifted = days + 719468;
    let era = shifted / 146097;
    let day_of_era = shifted - era * 146097;
    let year_of_era = (day_of_era - day_of_era / 1460 + day_of_era / 36524 - day_of_era / 146096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = if month <= 2 { year_of_era + era * 400 + 1 } else { year_of_era + era * 400 };
    let date = (year * 100 + month) * 100 + day;
    let time = of_day / 3600 * 10000 + of_day % 3600 / 60 * 100 + of_day % 60;
    return date * 1000000 + time;
}
