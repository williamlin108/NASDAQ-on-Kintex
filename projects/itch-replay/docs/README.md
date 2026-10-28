# itch-replay

Replays historical NASDAQ TotalView-ITCH 5.0 files out of a ConnectX-4 Lx port with
DPDK, so they can be received on the other port (and later by other hardware).

How to build, run and debug it: [user guide](../../../docs/user-guide.md).
How the setup works: [how-it-works.md](../../../docs/how-it-works.md).

## Status (2026-10-28)

- `src/main.c` is a skeleton: starts DPDK and prints each port's driver, MAC and link
  state. Builds with no warnings; runs without sudo via `./run` and under F5.
- Both ports open (`mlx5_pci`), link down: no cable between Ethernet 1 and 2 yet.
- Not yet tested: link up and real packet send/receive.

## Next steps

1. **Connect port 0 ↔ port 1** with an SFP28/SFP+ direct-attach cable.
2. **ITCH file reader:** historical NASDAQ files are a stream of
   `[uint16 big-endian length][message]` records, usually gzipped. Decompress, then
   `mmap` the file (normal memory; it doesn't need to be in hugepages).
3. **Packetize into MoldUDP64:** session (10 bytes), sequence number (u64 BE), message
   count (u16), then length-prefixed messages, inside Ethernet/IPv4/UDP, built in DPDK
   mbufs.
4. **Send loop** on port 0 with `rte_eth_tx_burst`. Pacing modes: max rate, and
   original timing (ITCH messages carry nanoseconds-since-midnight timestamps).
5. **Check on port 1** with `dpdk-testpmd` (rxonly) or a small receive counter that
   checks for MoldUDP64 sequence gaps.

## Notes

- `eal.conf` uses both ports (`-a 85:00.0`, `-a 85:00.1`), 256 MB hugepages at
  startup, 1 GB max.
- NIC firmware is Dell-branded 14.32.2004; no update attempted.
