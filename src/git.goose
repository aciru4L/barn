import std;
import os;
import src.process;

fn run_git(dir: const u8[:], scratch: const u8[:], command: const u8[:][:], out: u8[>..]&) -> i64 {
    let output = str(scratch, "/.barn-git-", time_ns(), "-", random_seed());
    var arguments: (const u8[:])[>..] = ["git", "-C", dir];
    for a in command { arguments.push(a); }
    let status = run_program_into(arguments[..], output);
    read_file(output, out);
    delete_file(output);
    return status;
}

fn git_succeeds(dir: const u8[:], scratch: const u8[:], command: const u8[:][:]) -> bool {
    var out: u8[>..] = [];
    return run_git(dir, scratch, command, out) == 0;
}
