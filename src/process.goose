import std;

extern "barn_run_program" fn run_program(arguments: const u8[:]) -> i64;

fn run_program(arguments: const u8[:][:]) -> i64 {
    var joined: u8[>..] = [];
    for a in arguments { format(joined, a, "\0"); }
    return run_program(joined);
}
