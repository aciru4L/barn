import std;
import os;

fn confirm(question: const u8[:]) -> bool {
    write_stdout(str(question, " [y/N] "));
    flush_stdout();
    var answer: u8[>..] = [];
    guard read_line(answer) else { print(""); return false; }
    let a = trim(answer);
    return a == "y" || a == "Y" || a == "yes" || a == "Yes" || a == "YES";
}
