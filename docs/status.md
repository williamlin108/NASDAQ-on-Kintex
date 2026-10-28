# Status

## Done and verified

- DPDK 25.11 + mlx5 PMD + rdma-core 61 installed; `ibv_devices` lists `mlx5_0`, `mlx5_1`.
- `itch-replay` skeleton builds with zero warnings; clangd and the Meson extension
  share `build/`.
- `~/.local/bin/dpdk-caps` created with `cap_net_admin,cap_net_raw,cap_ipc_lock=p`.
- Hugepages persistent: `/etc/sysctl.d/80-hugepages.conf` (`vm.nr_hugepages = 2048`).
- 2026-10-27: unprivileged run via `dpdk-run ... --in-memory` probes both ports:
  `port 0: mlx5_pci 1C:34:DA:72:C4:9E link down, max 1024 txq` (same for port 1).
  The `mlx5_net: No available register for sampler` lines are harmless (CX-4 Lx
  lacks flow-sampling registers).

## Pending

1. Cable port 0 ↔ port 1 (SFP28/SFP+ DAC) for loopback replay. Both ports are
   currently NO-CARRIER.
2. (Optional) `/dev/hugepages/rtemap_0`: a root-owned 2 MB leftover from one early
   `sudo` run without `--in-memory`. Clears on reboot or `sudo rm`.

## Not yet verified

- Link up / actual TX/RX (blocked on cable).

## Known gaps / notes

- Debugging: VS Code/gdb launches won't have the caps. Either run gdb under
  `dpdk-run` (e.g. a `miDebuggerPath` wrapper `dpdk-run gdb "$@"`) or debug with sudo.
  No `launch.json` yet.
- Project is not a git repo yet (`.gitignore` exists: `build/`, `.cache/`).
- NIC firmware is Dell-branded 14.32.2004; no update attempted.

## Next development steps

1. ITCH file reader: historical NASDAQ files are a stream of `[uint16 BE length][message]`
   records, usually gzipped. mmap the decompressed file.
2. Packetize into MoldUDP64 (session[10], seq u64 BE, count u16, then
   length-prefixed messages) inside Eth/IPv4/UDP, built in DPDK mbufs.
3. TX loop on port 0 with `rte_eth_tx_burst`; pacing modes: max-rate and
   original-timestamp (ITCH messages carry ns-since-midnight timestamps).
4. Verify on port 1 with `dpdk-testpmd` (rxonly) or a small RX counter, checking
   for MoldUDP64 sequence gaps.
