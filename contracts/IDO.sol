// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);

    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface IERC721 {
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

contract IDO {

    // user in IDO
    struct User {
        bool participated; // deposit 100 USDT
        bool partner; // deposit 300 USDT
        bool collected; // get back partnerDeposit
        bool tokensTransfered; // user got his YH
        uint256 amountOfReferals; // number of referals
        address addressPartner; // address of user who added this user 
    }

    mapping (address => User) public user;
    uint256[] public idNFTs;

    IERC20 public USDT; // USDT address
    IERC20 public YH; // YH address
    IERC721 public NFT; // NFT contract address
    uint public constant userDeposit = 100 * 10**18; // 100 USDT in decimals
    uint public constant partnerDeposit = 300 * 10**18; // 300 USDT in decimals
    uint public constant firstReward = 5 * 10*188; // 5 USDT in decimals
    uint public constant secondReward = 3 * 10**18; // 3 USDT in decimals
    uint public constant amountYH = 10000 * 10**18; // bought amount in IDO
    uint256 public id; // counter for idNFTs
    uint256 public startTimeIDO; // timestamp of starting IDO
    uint256 public endTimeIDO; // timestamp of ending IDO
    address public owner; // owner
    bool public isIDOStarted;

    event AddedToWhitelist(address buyer);
    event NewUser(address user);
    event NewPartner(address partner);
    event TransferToPartner(address partner, uint amount);
    event DepositReturned(address partner);
    event TokensTransfered(address user, uint amount);

    constructor (
        IERC20 _USDT,
        IERC20 _YH,
        IERC721 _NFT,
        address _owner
        ) {

        USDT = _USDT;
        YH = _YH;
        NFT = _NFT;
        owner = _owner;
    }

    /// @notice only owner can withdraw deposits
    modifier onlyOwner() {
        require(owner == msg.sender, "You are not owner");
        _;
    }

    /// @notice only participated users can deposit 300 USDT (checking it)
    modifier onlyParicipated() {
        require(isParticipated(msg.sender), "You are not a member of IDO");
        _;
    }

    /// @notice only partners users can get NFT
    modifier onlyPartner() {
        require(isPartner(msg.sender), "You are not a partner");
        _;
    }

    /// @notice only collected users can get NFT
    modifier onlyCollected() {
        require(isCollected(msg.sender), "You are not a partner");
        _;
    }

    /// @notice starting IDO
    /// @param amountOfSeconds period of IDO in seconds (since point of time startTimeIDO)
    /// @param _idNFTs array of idNFTs
    function startIDO(uint256 amountOfSeconds, uint256[] memory _idNFTs) public onlyOwner {
        require(!isIDOStarted, "IDO already started");

        startTimeIDO = block.timestamp;
        isIDOStarted = true;
        endTimeIDO = startTimeIDO + amountOfSeconds;

        uint256 length = _idNFTs.length;
        for (uint256 i = 0; i < length;) {
            idNFTs.push(_idNFTs[i]);
            unchecked { ++i; }
        }
    }

    /// @notice let all users to participate in IDO
    /// @param _addressPartner address of partner (from referal url)
    function participate(address _addressPartner) public {
        address _msgSender = msg.sender;
        require(isIDOStarted, "Wait for IDO starting");
        require(block.timestamp < endTimeIDO, "IDO ended");
        require(!isParticipated(_msgSender), "You can participate only once");

        uint256 _userDeposit = userDeposit;
        // Check referal levels
        if (_addressPartner > address(0)) { // Check first referal level
            _userDeposit -= firstReward;
            ++user[_addressPartner].amountOfReferals;

            if (user[_addressPartner].amountOfReferals == 10 && user[_addressPartner].partner) {
                getBackDeposit(_addressPartner);
            }

            USDT.transferFrom(_msgSender, _addressPartner, firstReward);
            emit TransferToPartner(_addressPartner, firstReward);

            // Check second referal level
            address _secondPartner = getSecondPartner(_addressPartner);
            if (_secondPartner > address(0)) {
                _userDeposit -= secondReward;
                USDT.transferFrom(_msgSender, _secondPartner, secondReward);
                emit TransferToPartner(_secondPartner, secondReward);
            }
        }
        
        user[_msgSender].addressPartner = _addressPartner;
        user[_msgSender].participated = true;
        USDT.transferFrom(_msgSender, address(this), userDeposit);
        emit NewUser(_msgSender);
    }

    /// @notice let users to get NFT in IDO after participate
    function becomePartner() public onlyParicipated{
        address _msgSender = msg.sender;
        require(!isPartner(_msgSender), "You are already a partner");

        user[_msgSender].partner = true;
        USDT.transferFrom(_msgSender, address(this), partnerDeposit);
        emit NewPartner(_msgSender);
    }

    /// @notice transfering 300 USDT back and transfering NFT
    /// @param _userAddress address of partner for transfer
    function getBackDeposit(address _userAddress) private {
        require(!isCollected(_userAddress), "You got your deposit back");
        
        user[_userAddress].collected = true;
        USDT.transfer(_userAddress, partnerDeposit);
        NFT.safeTransferFrom(address(NFT), _userAddress, idNFTs[id]);
        require(id++ >= idNFTs.length, "Not enough idNFTs to transfer");
        ++id;
        emit DepositReturned(_userAddress);
    }

    /// @notice only owner can withdraw all USDT amount 
    function withdrawDeposits() public onlyOwner{
        require(block.timestamp > endTimeIDO, "IDO ended");
        USDT.transfer(owner, getBalanceUSDT());
    }

    /// @notice only participated users can get YH amount amount 
    function getYH() public onlyParicipated {
        address _msgSender = msg.sender;
        require(!isTokensTransfered(_msgSender), "You can get YH tokens once");
        require(getBalanseYH() >= amountYH, "Not enough YH balance");

        user[_msgSender].tokensTransfered = true;
        YH.transfer(_msgSender, amountYH);
        emit TokensTransfered(_msgSender, amountYH);
    }

    /// @notice check YH balance in this contract
    function getBalanseYH() public view returns(uint256) {
        return YH.balanceOf(address(this));
    }

    /// @notice check USDT balance in this contract
    function getBalanceUSDT() public view returns(uint256) {
        return USDT.balanceOf(address(this));
    }

    /// @notice get second level referal
    /// @param _addressPartner address of second referal
    function getSecondPartner(address _addressPartner) public view returns(address) {
        return user[_addressPartner].addressPartner;
    }

    /// @notice check if tokensTransfered
    /// @param _userAddress address of user
    function isTokensTransfered(address _userAddress) public view returns(bool) {
        return user[_userAddress].tokensTransfered;
    }

    /// @notice check if the user participated
    /// @param _userAddress address of user
    function isParticipated(address _userAddress) public view returns(bool) {
        return user[_userAddress].participated;
    }

    /// @notice сhecking if the user is a partner
    /// @param _userAddress address of user
    function isPartner(address _userAddress) public view returns(bool) {
        return user[_userAddress].partner;
    }

    /// @notice сhecking if the user collect his deposit
    /// @param _userAddress address of user
    function isCollected(address _userAddress) public view returns(bool) {
        return user[_userAddress].collected;
    }

    function getUser(address _userAddress)
        public
        view
        returns (
            bool, 
            bool,
            bool,
            bool,
            uint256,
            address
        )
    {
        User memory getUser = user[_userAddress];
        return (
            getUser.participated,
            getUser.partner,
            getUser.collected,
            getUser.tokensTransfered,
            getUser.amountOfReferals,
            getUser.addressPartner
        );
    }

}
