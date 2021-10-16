pragma solidity >=0.6.0 <0.7.0;
//SPDX-License-Identifier: MIT

//import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.6/VRFConsumerBase.sol";

interface CETHInterface {
    function balanceOf(address owner) external view returns (uint256);

    function mint() external payable; // For ETH

    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    function repayBorrow() external payable; // For ETH

    function borrowBalanceCurrent(address account) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);
}

contract YourCollectible is ERC721, VRFConsumerBase {
    using Counters for Counters.Counter;

    // Immutables
    uint256 public immutable endingBlockNum;
    CETHInterface public immutable cETH;
    uint256 internal immutable ChainlinkFee;
    bytes32 internal immutable ChainlinkKeyHash;

    // Storage
    mapping(uint256 => address) public tickets;
    mapping(address => bool) public depositExist;

    bool public winnerSelected;
    uint256 public randomResult;
    uint256 public winningTicket;

    // Tracks lottery ticket ID
    Counters.Counter private ticketIds;

    // Tracks ERC721 token ID
    Counters.Counter private tokenIds;

    event Deposit(address from, uint256 amount);
    event Withdraw(address to, uint256 amount);

    constructor(
        uint256 _endingBlockNum,
        address _ChainlinkVRFCoordinator,
        address _ChainlinkToken,
        uint256 _ChainlinkFee,
        bytes32 _ChainlinkKeyHash,
        CETHInterface _cETH
    )
        public
        VRFConsumerBase(_ChainlinkVRFCoordinator, _ChainlinkToken)
        ERC721("YourCollectible", "YCB")
    {
        // Initialize ummutables
        endingBlockNum = _endingBlockNum;
        ChainlinkFee = _ChainlinkFee;
        ChainlinkKeyHash = _ChainlinkKeyHash;
        cETH = _cETH;

        // Set ERC721 base URI
        _setBaseURI("https://ipfs.io/ipfs/");
    }

    // Chainlink randomness functions \\
    function getRandomNumber() public returns (bytes32 requestId) {
        require(
            LINK.balanceOf(address(this)) >= ChainlinkFee,
            "Not enough LINK"
        );
        return requestRandomness(ChainlinkKeyHash, ChainlinkFee);
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;
    }

    function deposit() public payable {
        require(block.number < endingBlockNum, "Already expired");
        require(!depositExist[msg.sender], "User already deposit");
        require(msg.value == 1 ether, "Only 1 ETH deposit");

        uint256 ticketAmount = getTicketAmount();
        cETH.mint{value: msg.value}();

        for (uint256 i = 0; i < ticketAmount; i++) {
            ticketIds.increment();
            tickets[ticketIds.current()] = msg.sender;
        }

        depositExist[msg.sender] = true;
        emit Deposit(msg.sender, msg.value);
    }

    function getTicketAmount() public view returns (uint256) {
        // For each day before lottery closes, you get an extra ticket
        // Minimum number of ticket is 1
        return ((endingBlockNum - block.number) / 3000) + 1;
    }

    function selectWinningTicket() public {
        require(block.number > endingBlockNum, "Game not ended yet");
        require(!winnerSelected, "Winner already selected");
        winnerSelected = true;

        // Request random number from chainlink
        getRandomNumber();

        winningTicket = uint256((randomResult % ticketIds.current()) + 1);
    }

    // Allows winner to claim ***Token URI fed in from the front end when clicking the button****
    function claimWinningNFT(string memory tokenURI) public returns (uint256) {
        require(tickets[winningTicket] == msg.sender, ":( you did not win)");

        // Redeem cETH for the whole contract
        uint256 cETHBalance = cETH.balanceOf(address(this));
        cETH.approve(address(cETH), cETHBalance);
        require(cETH.redeemUnderlying(cETHBalance) == 0, "cETH redeem fails");

        // Mint winner's NFT
        tokenIds.increment();
        uint256 id = tokenIds.current();
        _mint(msg.sender, id);
        _setTokenURI(id, tokenURI);
    }

    function withdraw() public returns (uint256) {
        require(block.number > endingBlockNum, "Game not ended yet");
        require(winnerSelected, "Winner has not been selected");
        depositExist[msg.sender] = false;
        msg.sender.transfer(1 ether);
        emit Withdraw(msg.sender, 1 ether);
    }
}