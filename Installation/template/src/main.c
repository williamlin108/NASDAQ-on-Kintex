/*
 * DPDK starter program: starts DPDK, prints one summary line per network port, exits.
 * Build and run with ./run; DPDK and program arguments come from eal.conf.
 */
#include <stdio.h>
#include <stdlib.h>

#include <rte_eal.h>
#include <rte_ethdev.h>

/* Print one line with a port's driver, MAC address, link state and TX queue count. */
static void print_port_summary(uint16_t port)
{
	struct rte_eth_dev_info info;
	struct rte_ether_addr mac;
	struct rte_eth_link link;

	if (rte_eth_dev_info_get(port, &info) != 0 ||
	    rte_eth_macaddr_get(port, &mac) != 0 ||
	    rte_eth_link_get_nowait(port, &link) < 0) {
		printf("port %u: could not read port details\n", port);
		return;
	}
	printf("port %u: %s " RTE_ETHER_ADDR_PRT_FMT " link %s, max %u txq\n",
	       port, info.driver_name, RTE_ETHER_ADDR_BYTES(&mac),
	       link.link_status ? "up" : "down", info.max_tx_queues);
}

/* Print a summary line for every port DPDK opened (the -a ports in eal.conf). */
static void print_all_ports(void)
{
	uint16_t port;

	RTE_ETH_FOREACH_DEV(port)
		print_port_summary(port);
}

int main(int argc, char **argv)
{
	/* rte_eal_init consumes DPDK's own arguments; the program's own ones follow */
	int consumed = rte_eal_init(argc, argv);
	if (consumed < 0)
		rte_exit(EXIT_FAILURE, "EAL init failed\n");

	print_all_ports();

	rte_eal_cleanup();
	return 0;
}
