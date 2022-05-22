// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SmartLottery is Ownable, ReentrancyGuard, VRFConsumerBaseV2, Pausable {
    using SafeMath for uint256;

    struct Ticket {
        address payable buyer;
        uint8 number;
        uint16 serial;
        uint date;
        bool winner;
        bool alwaysWinner;
    }

    VRFCoordinatorV2Interface private immutable COORDINATOR;
    AggregatorV3Interface private immutable priceFeed;

    bytes32 private immutable keyHash;
    uint32 private constant callbackGasLimit = 100_000;
    uint16 private constant requestConfirmations = 20;
    uint32 private constant numWords =  2;

    uint256 public s_requestId;
    uint64 public s_subscriptionId;

    mapping(address => Ticket[]) public game;
    address[] public players;
    uint8 private immutable MAX_TICKETS_PLAYER;
    uint8 private immutable INTERVAL_DAYS;
    uint8 private immutable POLYGON_DECIMALS;
    uint8 private immutable TICKET_PRICE;
    uint256 public lockTime;
    bool private allowBuy;

    error InvalidAddress();
    error NotAllowBuyMore();
    error TicketAlreadyBought(uint8 number, uint16 serial);
    error NotAllowBuy();
    error NotEnoughFunds(int256 requested, int256 available);
    error TimeLockError(uint256 blocTimestamp, uint256 lockTime);
    error NotPickWinnerYet();
    error NotWinnerSelectedError();

    event BoughtTicket(address indexed buyer, uint8 number, uint16 serial, uint date);
    event PickedWinner(uint8 number, uint16 serial, uint date);
    event TheresNoWinner(uint8 number, uint16 serial, uint date);

    constructor(
        uint8 _maxTicketsPlayer, 
        address _vrfCoordinator,
        address _proxyFeed,
        bytes32 _keyHash, 
        uint8 _intervalDays, 
        uint8 _ticketPrice
    ) VRFConsumerBaseV2(_vrfCoordinator) {
        MAX_TICKETS_PLAYER = _maxTicketsPlayer;
        COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinator);
        priceFeed = AggregatorV3Interface(_proxyFeed);

        keyHash = _keyHash;
        lockTime = block.timestamp + (_intervalDays * 24 hours);
        INTERVAL_DAYS = _intervalDays;
        allowBuy = true;
        TICKET_PRICE = _ticketPrice;
        POLYGON_DECIMALS = 18;

        createNewSubscription();
    }

    receive() external payable {}

    function buyTicket(uint8 number, uint16 serial, bool _alwaysWinner) payable public nonReentrant whenNotPaused {
        if (!allowBuy)
            revert NotAllowBuy();
        
        int256 ticketAmount = getTicketPrice(getLatestTokenPrice());
        int256 ticketPay = int256(msg.value);
        if (ticketPay == 0 || ticketPay < ticketAmount)
            revert NotEnoughFunds(ticketAmount, ticketPay);
                
        address player = msg.sender;
        uint8 totalTicketsBy = getTotalTicketsByUser(player);

        if (totalTicketsBy >= MAX_TICKETS_PLAYER)
            revert NotAllowBuyMore();

        if (isTicketBought(number, serial))
            revert TicketAlreadyBought(number, serial);

        Ticket[] storage tickets = game[player];
        tickets.push(Ticket(payable(player), number, serial, block.timestamp, false, _alwaysWinner));

        if (!isPlayerAdded(player))
            players.push(player);

        emit BoughtTicket(
            tickets[totalTicketsBy].buyer, 
            tickets[totalTicketsBy].number, 
            tickets[totalTicketsBy].serial, 
            tickets[totalTicketsBy].date
        );
    }

    function pickWinner() public onlyOwner nonReentrant whenNotPaused {
        if (block.timestamp > lockTime)
            revert TimeLockError(block.timestamp, lockTime);

        allowBuy = false;
        requestRandomWords();
    }

    function payWinner() public onlyOwner nonReentrant whenNotPaused {
        if (block.timestamp < lockTime)
            revert TimeLockError(block.timestamp, lockTime);

        address winner = getAddressForWinner();
        uint256 totalAmount = TICKET_PRICE * players.length;
        uint256 winnerAmount = getPot();

        if (winner != address(0)) 
            payable(winner).transfer(winnerAmount);
        
        payable(owner()).transfer(totalAmount.sub(winnerAmount));

        reset();

        lockTime = block.timestamp + (INTERVAL_DAYS * 24 hours);
    }

    function getPot() view public returns (uint256) {
        uint256 totalAmount = TICKET_PRICE * players.length;
        return totalAmount.div(100).mul(10);
    }

    // section of private methods
    function getTotalTicketsByUser(address player) view private returns (uint8) {
        if (player == address(0))
            revert InvalidAddress();

        Ticket[] memory tickets = game[player];

        return uint8(tickets.length);
    }

    // Create a new subscription when the contract is initially deployed.
    function createNewSubscription() private {
        // Create a subscription with a new subscription ID.
        address[] memory consumers = new address[](1);
        consumers[0] = address(this);
        s_subscriptionId = COORDINATOR.createSubscription();
        // Add this contract as a consumer of its own subscription.
        COORDINATOR.addConsumer(s_subscriptionId, consumers[0]);
    }

    function requestRandomWords() private whenNotPaused {
        // Will revert if subscription is not set and funded.
        s_requestId = COORDINATOR.requestRandomWords(
            keyHash,
            s_subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
    }

    function getLatestTokenPrice() view private returns (int256) {
        (
            /*uint80 roundID*/,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        int256 result;

        if (decimals == 18)
            result = price;
        else if (decimals < POLYGON_DECIMALS)
            result = price * int256(10 ** uint256(POLYGON_DECIMALS - decimals));

        else
            result = price * int256(10 ** uint256(decimals - POLYGON_DECIMALS));

        return result;
    }

    function getTicketPrice(int256 tokenPrice) view private returns (int256) {
        int256 result;
        int256 tmpPrice = int8(TICKET_PRICE);
        int256 ticketPrice = tmpPrice * 1 ether;

        if ((tokenPrice / 1 ether) > 1)
            result = (tokenPrice / ticketPrice) * 10 ** 18;

        else
            result = (ticketPrice * tokenPrice) / 10 ** 18;

        return result;
    }

    function getAddressForWinner() view private returns (address) {
        for (uint index = 0; index < players.length; increment(index)){
            Ticket[] memory tickets = game[players[index]];

            for (uint8 ticketIndex = 0; ticketIndex < tickets.length; increment(ticketIndex)) {
                Ticket memory ticket = tickets[ticketIndex];

                if (ticket.winner)
                    return players[index];
            }
        }

        return address(0);
    }

    function isAlwaysWinner() view private returns (bool) {
        uint256 alwaysWinner = 0;
        uint256 couldBeAWinner = 0;

        for (uint index = 0; index < players.length; increment(index)){
            Ticket[] memory tickets = game[players[index]];

            for (uint8 ticketIndex = 0; ticketIndex < tickets.length; increment(ticketIndex)) {
                Ticket memory ticket = tickets[ticketIndex];

                if (ticket.alwaysWinner)
                    alwaysWinner += 1;

                else
                    couldBeAWinner += 1;
            }
        }

        return alwaysWinner > couldBeAWinner;
    }

    function handleAlwaysWinner(uint256[] memory randomWords) private returns (Ticket memory) {
        uint160 indexPlayerWinner = uint160(randomWords[0] % players.length);
        uint160 indexTicketWinner = 0;
        address playerWinner = players[indexPlayerWinner];
        
        if (game[playerWinner].length > 1) 
            indexTicketWinner = uint160(randomWords[1] % game[playerWinner].length);

        game[playerWinner][indexTicketWinner].winner = true;

        return game[playerWinner][indexTicketWinner];
    }

    function handleCouldBeAWinner(uint8 number, uint16 serial) private returns (Ticket memory) {
        bool winner = false;
        Ticket memory ticketWinner;

        for (uint index = 0; index < players.length; increment(index)){
            if (winner)
                break;

            Ticket[] storage tickets = game[players[index]];

            for (uint8 ticketIndex = 0; ticketIndex < tickets.length; increment(ticketIndex)) {
                Ticket storage ticket = tickets[ticketIndex];

                if (ticket.number == number && ticket.serial == serial) {
                    ticket.winner = true;
                    winner = true;

                    ticketWinner = ticket;

                    break;
                }
            }
        }

        return ticketWinner;
    }

    // section of internal methods
    function isTicketBought(uint8 _number, uint16 _serial) view internal returns (bool) {
        for (uint index = 0; index < players.length; increment(index)) {
            Ticket[] memory tickets = game[players[index]];

            for (uint8 ticketIndex = 0; ticketIndex < tickets.length; increment(ticketIndex)) {
                Ticket memory ticket = tickets[ticketIndex];

                if (ticket.number == _number && ticket.serial == _serial)
                    return true;
            }
        }

        return false;
    }

    function isPlayerAdded(address _player) view internal returns (bool) {
        for (uint index = 0; index < players.length; increment(index)) {
            if (players[index] == _player)
                return true;
        }

        return false;
    }

    function reset() internal {
        for (uint index = 0; index < players.length; increment(index)) {
            delete game[players[index]];
        }

        delete players;
        allowBuy = true;
    }

    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        Ticket memory ticketWinner;

        if (isAlwaysWinner()) {
            ticketWinner = handleAlwaysWinner(randomWords);

            emit PickedWinner(ticketWinner.number, ticketWinner.serial, block.timestamp);

        } else {
            uint8 number = uint8(randomWords[0] % 99);
            uint16 serial = uint16(randomWords[1] % 999);
            
            ticketWinner = handleCouldBeAWinner(number, serial);

            if (ticketWinner.winner)
                emit PickedWinner(ticketWinner.number, ticketWinner.serial, block.timestamp);

            else
                emit TheresNoWinner(number, serial, block.timestamp);
        }
    }

    function increment(uint i) internal pure returns (uint) {
        unchecked { return i + 1;}
    }
}