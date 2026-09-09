//! Process and host counters, read straight out of /proc.
//!
//! Lua cannot reach any of this: the sandbox has no `io` and jails `file.*` to
//! garrysmod/. The bridge used to sample it over ssh, picking the srcds pid with
//! `pgrep | head -n1`, which could pick the wrong one on a host running several
//! servers. /proc/self is always this process.

use std::sync::Mutex;
use std::time::Instant;

/// The counters a sample is derived from. Deltas need two of them.
struct Counters {
    at: Instant,
    cpu_ticks: u64,
    rx: u64,
    tx: u64,
}

pub struct Sample {
    /// percent of one core used by this process since the previous sample
    pub cpu: f64,
    /// resident bytes
    pub mem_used: u64,
    /// host memory, the ceiling for mem_used
    pub mem_max: u64,
    /// host bytes/s in and out, all interfaces except loopback
    pub net_rx: f64,
    pub net_tx: f64,
}

static PREVIOUS: Mutex<Option<Counters>> = Mutex::new(None);

fn clock_ticks() -> f64 {
    let hz = unsafe { libc::sysconf(libc::_SC_CLK_TCK) };
    if hz > 0 {
        hz as f64
    } else {
        100.0
    }
}

/// utime + stime out of /proc/self/stat. The comm field is parenthesised and
/// may itself contain spaces and brackets, so everything up to the last ')' is
/// skipped rather than split on.
fn cpu_ticks(stat: &str) -> Option<u64> {
    let rest = &stat[stat.rfind(')')? + 1..];
    let fields: Vec<&str> = rest.split_whitespace().collect();
    // the first field after comm is `state`, which is field 3, so utime (14)
    // and stime (15) sit at offsets 11 and 12
    Some(fields.get(11)?.parse::<u64>().ok()? + fields.get(12)?.parse::<u64>().ok()?)
}

/// Value of a `Key:  1234 kB` line, in bytes.
fn kb_field(text: &str, key: &str) -> Option<u64> {
    text.lines()
        .find(|line| line.starts_with(key))?
        .split_whitespace()
        .nth(1)?
        .parse::<u64>()
        .ok()
        .map(|kb| kb * 1024)
}

/// Summed rx/tx bytes over every interface but loopback.
fn net_totals(dev: &str) -> (u64, u64) {
    let (mut rx, mut tx) = (0u64, 0u64);
    // two header lines, then "iface: rx_bytes ... tx_bytes ..."
    for line in dev.lines().skip(2) {
        let Some((name, counters)) = line.split_once(':') else {
            continue;
        };
        if name.trim() == "lo" {
            continue;
        }
        let fields: Vec<&str> = counters.split_whitespace().collect();
        rx += fields.first().and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
        tx += fields.get(8).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
    }
    (rx, tx)
}

/// Reads the counters and turns them into rates against the previous call.
/// The first call has nothing to compare against, so its rates are zero.
pub fn sample() -> std::io::Result<Sample> {
    let stat = std::fs::read_to_string("/proc/self/stat")?;
    let status = std::fs::read_to_string("/proc/self/status")?;
    let meminfo = std::fs::read_to_string("/proc/meminfo")?;
    let netdev = std::fs::read_to_string("/proc/net/dev")?;

    let (rx, tx) = net_totals(&netdev);
    let now = Counters {
        at: Instant::now(),
        cpu_ticks: cpu_ticks(&stat).unwrap_or(0),
        rx,
        tx,
    };

    let mut guard = PREVIOUS.lock().unwrap_or_else(|e| e.into_inner());
    let (mut cpu, mut net_rx, mut net_tx) = (0.0, 0.0, 0.0);

    if let Some(previous) = guard.as_ref() {
        let dt = now.at.duration_since(previous.at).as_secs_f64();
        if dt > 0.0 {
            // counters only ever climb, but a wrap or a reset would read as a
            // huge negative, so saturate instead of trusting the subtraction
            cpu = (now.cpu_ticks.saturating_sub(previous.cpu_ticks) as f64 / clock_ticks() / dt)
                * 100.0;
            net_rx = now.rx.saturating_sub(previous.rx) as f64 / dt;
            net_tx = now.tx.saturating_sub(previous.tx) as f64 / dt;
        }
    }

    let sample = Sample {
        cpu: (cpu * 10.0).round() / 10.0,
        mem_used: kb_field(&status, "VmRSS:").unwrap_or(0),
        mem_max: kb_field(&meminfo, "MemTotal:").unwrap_or(0),
        net_rx: net_rx.round(),
        net_tx: net_tx.round(),
    };
    *guard = Some(now);
    Ok(sample)
}

/// Drops the baseline so the next sample starts fresh.
pub fn reset() {
    *PREVIOUS.lock().unwrap_or_else(|e| e.into_inner()) = None;
}

#[cfg(test)]
mod tests {
    use super::*;

    /// utime is field 14 and stime field 15, but comm (field 2) is attacker
    /// controlled in practice: it can hold spaces and brackets.
    #[test]
    fn cpu_ticks_survives_a_hostile_comm() {
        let tail = "0 ".repeat(10);
        let stat = format!("123 (srcds_linux (x) 1) S {tail}1000 500 9 9");
        assert_eq!(cpu_ticks(&stat), Some(1500));
    }

    #[test]
    fn cpu_ticks_handles_a_plain_comm() {
        let tail = "0 ".repeat(10);
        let stat = format!("1 (init) S {tail}7 3 0 0");
        assert_eq!(cpu_ticks(&stat), Some(10));
    }

    #[test]
    fn kb_fields_are_converted_to_bytes() {
        let status = "Name:\tsrcds_linux\nVmPeak:\t 900 kB\nVmRSS:\t  1024 kB\n";
        assert_eq!(kb_field(status, "VmRSS:"), Some(1024 * 1024));
        // VmPeak must not be matched by a VmRSS lookup, nor the reverse
        assert_eq!(kb_field(status, "MemTotal:"), None);
    }

    #[test]
    fn net_totals_sum_every_interface_but_loopback() {
        let dev = "Inter-|   Receive     |  Transmit\n\
                   face |bytes packets errs drop fifo frame compressed multicast|bytes packets errs drop fifo colls carrier compressed\n\
                   \x20   lo: 999 1 0 0 0 0 0 0 999 1 0 0 0 0 0 0\n\
                   \x20 eth0: 5000 50 0 0 0 0 0 0 7000 70 0 0 0 0 0 0\n\
                   \x20 eth1: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n";
        assert_eq!(net_totals(dev), (6000, 9000));
    }

    /// The first sample has no baseline, so rates must read zero rather than
    /// spiking off the process's whole lifetime.
    #[test]
    fn first_sample_reports_no_rates() {
        reset();
        let first = sample().expect("/proc should be readable");
        assert_eq!(first.cpu, 0.0);
        assert_eq!(first.net_rx, 0.0);
        assert_eq!(first.net_tx, 0.0);
        assert!(first.mem_used > 0, "VmRSS should be non-zero");
        assert!(first.mem_max > first.mem_used, "MemTotal should exceed RSS");
    }

    #[test]
    fn second_sample_produces_a_plausible_cpu_reading() {
        reset();
        sample().unwrap();
        let spin = std::time::Instant::now();
        while spin.elapsed() < std::time::Duration::from_millis(120) {
            std::hint::black_box(fibonacci(20));
        }
        let second = sample().unwrap();
        assert!(second.cpu > 0.0, "busy loop should show cpu, got {}", second.cpu);
        assert!(second.cpu <= 400.0, "cpu implausibly high: {}", second.cpu);
    }

    fn fibonacci(n: u64) -> u64 {
        if n < 2 { n } else { fibonacci(n - 1) + fibonacci(n - 2) }
    }
}

#[cfg(test)]
mod crosscheck {
    /// Not an assertion, a readout for diagnosing a real server.
    /// `cargo test --release -- --ignored --nocapture`
    #[test]
    #[ignore = "readout, not an assertion"]
    fn print_a_sample() {
        super::reset();
        super::sample().unwrap();
        std::thread::sleep(std::time::Duration::from_millis(300));
        let s = super::sample().unwrap();
        let meminfo = std::fs::read_to_string("/proc/meminfo").unwrap();
        let memtotal_kb: u64 = meminfo
            .lines()
            .find(|l| l.starts_with("MemTotal:"))
            .unwrap()
            .split_whitespace()
            .nth(1)
            .unwrap()
            .parse()
            .unwrap();
        println!("  cpu     {:.1} %", s.cpu);
        println!("  memUsed {} bytes ({:.1} MiB)", s.mem_used, s.mem_used as f64 / 1048576.0);
        println!("  memMax  {} bytes ({:.1} GiB)", s.mem_max, s.mem_max as f64 / 1073741824.0);
        println!("  /proc/meminfo MemTotal = {} kB -> {} bytes", memtotal_kb, memtotal_kb * 1024);
        println!("  match: {}", s.mem_max == memtotal_kb * 1024);
        println!("  netRx   {:.0} B/s", s.net_rx);
        println!("  netTx   {:.0} B/s", s.net_tx);
    }
}
