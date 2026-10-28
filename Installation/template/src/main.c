#include <stdio.h>
#include <stdlib.h>

#include <rte_eal.h>
#include <rte_ethdev.h>

int main(int argc, char **argv)
{
	int ret = rte_eal_init(argc, argv);
	if (ret < 0)
		rte_exit(EXIT_FAILURE, "EAL init failed\n");

	uint16_t port;
	RTE_ETH_FOREACH_DEV(port) {
		struct rte_eth_dev_info info;
		struct rte_ether_addr mac;
		struct rte_eth_link link;

		if (rte_eth_dev_info_get(port, &info) != 0 ||
		    rte_eth_macaddr_get(port, &mac) != 0 ||
		    rte_eth_link_get_nowait(port, &link) < 0)
			continue;
		printf("port %u: %s " RTE_ETHER_ADDR_PRT_FMT " link %s, max %u txq\n",
		       port, info.driver_name, RTE_ETHER_ADDR_BYTES(&mac),
		       link.link_status ? "up" : "down", info.max_tx_queues);
	}

	rte_eal_cleanup();
	return 0;
}
