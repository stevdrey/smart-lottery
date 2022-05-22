const SmartLottery = artifacts.require('SmartLottery');

module.exports = (deployer, network, accounts) => {
    const ticketPrice = 10;
    const maxTicketsPlayer = 3;

    let vrf_coordinator;
    let keyHash;
    let proxyFeed;
    let intervalDays;    

    if (network === 'mumbai' || network == 'development') {
        vrf_coordinator = '0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed';
        keyHash = '0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f';
        proxyFeed = process.env.AGGREGATOR_FEED_PROXY_TEST_ADDRESS;
        intervalDays = 1;
    }

    deployer.deploy(SmartLottery, maxTicketsPlayer, vrf_coordinator, proxyFeed, 
        keyHash, intervalDays, ticketPrice);
};