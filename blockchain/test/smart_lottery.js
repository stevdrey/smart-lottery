require('dotenv')
  .config();

  const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
  } = require('@openzeppelin/test-helpers');
const Web3 = require('web3');

const SmartLottery = artifacts.require('SmartLottery');
const POLYGON_DECIMALS = 18;
const getTicketCost = (dollars, tokenPrice) => 
    tokenPrice < 1 
        ? dollars * tokenPrice 
        : dollars / tokenPrice;

contract('Smart Lottery Test', async ([owner, player1, palyer2, palyer3, player4]) => {
    let smartLottery;
    let web3 = new Web3(`http://127.0.0.1:8545`);
    
    let lastPrice;

    before(async ()=> {
        const aggregatorV3InterfaceABI = [{ "inputs": [], "name": "decimals", "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "description", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "uint80", "name": "_roundId", "type": "uint80" }], "name": "getRoundData", "outputs": [{ "internalType": "uint80", "name": "roundId", "type": "uint80" }, { "internalType": "int256", "name": "answer", "type": "int256" }, { "internalType": "uint256", "name": "startedAt", "type": "uint256" }, { "internalType": "uint256", "name": "updatedAt", "type": "uint256" }, { "internalType": "uint80", "name": "answeredInRound", "type": "uint80" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "latestRoundData", "outputs": [{ "internalType": "uint80", "name": "roundId", "type": "uint80" }, { "internalType": "int256", "name": "answer", "type": "int256" }, { "internalType": "uint256", "name": "startedAt", "type": "uint256" }, { "internalType": "uint256", "name": "updatedAt", "type": "uint256" }, { "internalType": "uint80", "name": "answeredInRound", "type": "uint80" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "version", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }];
        const priceFeed = new web3.eth.Contract(aggregatorV3InterfaceABI, process.env.AGGREGATOR_FEED_PROXY_TEST_ADDRESS);
        const resultPirceFeed = await priceFeed.methods.latestRoundData().call();
        const decimalFeed = await priceFeed.methods.decimals().call();

        smartLottery = await SmartLottery.deployed();
        lastPrice = (resultPirceFeed.answer * (10 ** (POLYGON_DECIMALS - decimalFeed))) / web3.utils.toWei('1', 'ether');
    });

    it('Should deploy smart contract properly', async () => {
        assert(smartLottery.address !== '');
    });

   it('Player can buy ticket', async () => {
        const ticketPrice = getTicketCost(10, lastPrice);
        const number = Math.floor(Math.random() * (99 - 1) + 1);
        const serial = Math.floor(Math.random() * (999 - 1) + 1)
        const result = await smartLottery.buyTicket(number, serial, false, {from: player1, value: web3.utils.toWei(`${ticketPrice}`, 'ether')});

        expectEvent(result, 'BoughtTicket', { buyer: player1 });
    });

    it('Shoud revert when ticket price is 0', async ()=> {
        const ticketPrice = new BN(0);
        const number = Math.floor(Math.random() * (99 - 1) + 1);
        const serial = Math.floor(Math.random() * (999 - 1) + 1)

        await expectRevert.unspecified(smartLottery.buyTicket(number, serial, false, {from: player1, value: ticketPrice}));
    });

    it('Shoud revert when ticket price is less than 10 dollars', async ()=> {
        const ticketPrice = getTicketCost(8, lastPrice);
        const number = Math.floor(Math.random() * (99 - 1) + 1);
        const serial = Math.floor(Math.random() * (999 - 1) + 1)

        await expectRevert.unspecified(smartLottery.buyTicket(number, serial, false, {from: player1, value: web3.utils.toWei(`${ticketPrice}`, 'ether')}));
    });

    it('Ticket can not buy twise', async () => {
        const ticketPrice = getTicketCost(10, lastPrice);
        const number = Math.floor(Math.random() * (99 - 1) + 1);
        const serial = Math.floor(Math.random() * (999 - 1) + 1)
        
        await smartLottery.buyTicket(number, serial, false, {from: player1, value: web3.utils.toWei(`${ticketPrice}`, 'ether')});
        await expectRevert.unspecified(smartLottery.buyTicket(number, serial, false, {from: palyer2, value: web3.utils.toWei(`${ticketPrice}`, 'ether')}));
    });
    
});