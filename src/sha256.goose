import std;

let K: u32[64] = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

fn rotr(x: u32, n: u32) -> u32 { (x >> n) | (x << (32 - n)) }

struct Sha256 { h: u32[8], buf: u8[64], fill: i64, total: u64 }

fn sha256() -> Sha256 {
    Sha256 { h: [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19],
             buf: [0; 64], fill: 0, total: 0 }
}

fn compress(s: Sha256&) {
    var w: u32[64] = [0; 64];
    for i in 16 {
        w[i] = (s.buf[4 * i] as u32 << 24) | (s.buf[4 * i + 1] as u32 << 16) |
               (s.buf[4 * i + 2] as u32 << 8) | s.buf[4 * i + 3];
    }
    for i in 16..64 {
        let s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        let s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    var a = s.h[0]; var b = s.h[1]; var c = s.h[2]; var d = s.h[3];
    var e = s.h[4]; var f = s.h[5]; var g = s.h[6]; var h = s.h[7];
    for i in 64 {
        let t1 = h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i];
        let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c));
        h = g; g = f; f = e; e = d + t1;
        d = c; c = b; b = a; a = t1 + t2;
    }
    s.h[0] += a; s.h[1] += b; s.h[2] += c; s.h[3] += d;
    s.h[4] += e; s.h[5] += f; s.h[6] += g; s.h[7] += h;
}

fn update(s: Sha256&, data: const u8[:]) {
    for c in data {
        s.buf[s.fill] = c;
        s.fill++;
        if s.fill == 64 { compress(s); s.fill = 0; }
    }
    s.total += data.len as u64;
}

fn finish(s: Sha256&, out: u8[>..]&) {
    let bits = s.total * 8;
    var tail: u8[..72] = [];
    tail.push(0x80);
    while (s.fill + tail.len) % 64 != 56 { tail.push(0); }
    for i in 8 { tail.push((bits >> (56 - 8 * i as u64)) as! u8); }
    let total = s.total;
    update(s, tail);
    s.total = total;
    let hex = "0123456789abcdef";
    for word in s.h {
        for i in 8 { out.push(hex[((word >> (28 - 4 * i as u32)) & 15) as i64]); }
    }
}
