pragma solidity ^0.4.24;

import './KYC.sol';
import './SemiSafeMath.sol';
import '../node_modules/openzeppelin-solidity/contracts/token/ERC20/ERC20Basic.sol';
import '../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol';

contract Pool {
  using SafeMath for uint;

    struct ContributorData{
        uint lastContributionTime;
        uint grossContribution;
    }

    struct Params{
        bytes32 saleParticipateCalldata;
        bytes32 saleWithdrawCalldata;
        bytes32 poolDescription;
        address saleAddress; //address of token sale
        address tokenAddress; // address of erc20 token contract
        address kycAddress;
        address provider; //connectICO address for fees
        address creator; //pool creator address
        uint256 minContribution; //minimum amount expected from pool participants
        uint256 maxContribution; //maximum amount expected from pool participants 0: no limit
        uint256 minPoolGoal;  //minimum amount needed for the sale
        uint256 maxPoolAllocation; //maximum amount raisable by pool
        uint32 saleStartDate;
        uint32 saleEndDate;
        uint32 withdrawTimelock;
        uint16 providerFeeRate; // 1/1000
        uint16 creatorFeeRate; // 1/1000
        bool whitelistPool;
        bool strictlyTrustlessPool;
    }

    struct PoolStats{
        uint256 allGrossContributions;
        uint256 creatorStash;
        uint256 providerStash;
        bool tokensReceivedConfirmed;
        bool sentToSale;
        bool stopped;
    }

    address[] public contributorList; // possible to get on frontend?

    mapping(address => bool) public admins; //additional admins
    mapping(address => bool) public whitelist;
    mapping(bytes32 => bool) public kycCountryBlacklist; //key: https://en.wikipedia.org/wiki/ISO_3166-1_alpha-3

    mapping(address => ContributorData) public contributors;
    mapping(address => mapping(address => uint)) private payedOut; //(contributorAddress => (tokenAddress => amountPayedOut)) 0x0 tokenAddress: ETH

    mapping(address => uint) private totalPayedOut; //(tokenAddress => totalAmountPayedOut) 0x0 address: ETH

    uint8 private ETHEREUM_DECIMALS = 18;

    Params private params;

    PoolStats public poolStats;

    modifier onlyCreator{
        require(msg.sender == params.creator, "modifier onlyCreator: Error, tx was not initiated by creator address");
        _;
    }

    modifier onlyAdmin{
        require(admins[msg.sender], "modifier onlyAdmin: Error, tx was not initiated by admin address");
        _;
    }

    modifier onlyProvider{
        require(msg.sender == params.provider, "modifier onlyProvider: Error, tx was not initiated by provider address");
        _;
    }

    event adminsChange(address listItem, bool isActive); //added=true, removed=false
    event whitelistChange(address listItem, bool isActive); //added=true, removed=false
    event countryBlacklistChange(bytes32 listItem, bool isActive); //added=true, removed=false
    event contributed(address indexed contributor, uint amount);

    constructor (
        address[5] addresses,
        bytes32[3] bytes32s,
        uint[9] integers,
        bool[2] bools,
        address[] adminlist,
        address[] contributorWhitelist,
        bytes32[] countryBlacklist
     ) public {
        params.kycAddress = addresses[0];
        params.provider = addresses[1];
        params.creator = addresses[2];
        params.saleAddress = addresses[3];
        params.tokenAddress = addresses[4];
        params.saleParticipateCalldata = bytes32s[0];
        params.saleWithdrawCalldata = bytes32s[1];
        params.poolDescription = bytes32s[2];
        params.providerFeeRate = uint16(integers[0]);
        params.creatorFeeRate = uint16(integers[1]);
        params.saleStartDate = uint32(integers[2]);
        params.saleEndDate = uint32(integers[3]);
        params.minContribution = integers[4];
        params.maxContribution = integers[5];
        params.minPoolGoal = integers[6];
        params.maxPoolAllocation = integers[7];
        params.withdrawTimelock = uint32(integers[8]);
        params.whitelistPool = bools[0];
        params.strictlyTrustlessPool = bools[1];
        admins[params.creator] = true;
        addAdminPrivate(adminlist);
        addWhitelistPrivate(contributorWhitelist);
        addCountryBlacklistPrivate(countryBlacklist);
    }

    function addAdmin(address[] addressList) public onlyCreator {
        for(uint i = 0; i < addressList.length; i++) {
            require(KYC(params.kycAddress).checkKYC(addressList[i]), "addAdmin(address[] addressList): Error, address is not a KYC address");
            admins[addressList[i]] = true;
            emit adminsChange(addressList[i], true);
        }
    }

    function addAdminPrivate(address[] addressList) private {
        for(uint i = 0; i < addressList.length; i++) {
            require(KYC(params.kycAddress).checkKYC(addressList[i]), "addAdmin(address[] addressList): Error, address is not a KYC address");
            admins[addressList[i]] = true;
            emit adminsChange(addressList[i], true);
        }
    }

    function removeAdmin(address[] addressList) public onlyCreator {
      for(uint i = 0; i < addressList.length; i++) {
        admins[addressList[i]] = false;
        emit adminsChange(addressList[i], false);
      }
    }

    function addWhitelist(address[] addressList) public onlyAdmin {
        for(uint i = 0; i < addressList.length; i++) {
          require(KYC(params.kycAddress).checkKYC(addressList[i]), "addWhitelist(address[] addressList): Error, address is not a KYC address");
          whitelist[addressList[i]] = true;
          emit whitelistChange(addressList[i], true);
        }
    }

    function addWhitelistPrivate(address[] addressList) private {
        for(uint i = 0; i < addressList.length; i++) {
          require(KYC(params.kycAddress).checkKYC(addressList[i]), "addWhitelist(address[] addressList): Error, address is not a KYC address");
          whitelist[addressList[i]] = true;
          emit whitelistChange(addressList[i], true);
        }
    }

    function removeWhitelist(address[] addressList) public onlyAdmin {
      for(uint i = 0; i < addressList.length; i++) {
        whitelist[addressList[i]] = false;
        emit whitelistChange(addressList[i], false);
      }
    }

    function addCountryBlacklist(bytes32[] countryList) public onlyAdmin {
      for(uint i = 0; i < countryList.length; i++){
        kycCountryBlacklist[countryList[i]] = true;
        emit countryBlacklistChange(countryList[i], true);
      }
    }

    function addCountryBlacklistPrivate(bytes32[] countryList) private {
      for(uint i = 0; i < countryList.length; i++){
        kycCountryBlacklist[countryList[i]] = true;
        emit countryBlacklistChange(countryList[i], true);
      }
    }

    function removeCountryBlacklist(bytes32[] countryList) public onlyAdmin {
      for(uint i = 0; i < countryList.length; i++){
        kycCountryBlacklist[countryList[i]] = false;
        emit countryBlacklistChange(countryList[i], false);
      }
    }

    function contribute() public payable {
        if(params.whitelistPool) require(whitelist[msg.sender], "contribute(): Error, tx was not initiated by whitelisted address");
        require(KYC(params.kycAddress).checkKYC(msg.sender), "contribute(): Error, tx was not initiated by KYC address");
        require(!kycCountryBlacklist[KYC(params.kycAddress).kycCountry(msg.sender)], "contribute(): Contributors countr is on blacklist");
        require(SafeMath.add(msg.value, contributors[msg.sender].grossContribution) >= params.minContribution, "contribute(): Error, contribution value is lower than minimum allowed");
        require(params.maxContribution == 0 || msg.value.add(contributors[msg.sender].grossContribution) <= params.maxContribution, "contribute(): Error, tx value is higher than maximum allowed");
        require(params.maxPoolAllocation == 0 || msg.value.add(poolStats.allGrossContributions) <= params.maxPoolAllocation, "contribute(): Error, all contributions are higher than maximum allowed");
        require(block.timestamp < params.saleEndDate, "contribute(): Error, the sale has ended");
        require(!poolStats.sentToSale, "contribute(): Error, the pools funds were already sent to the sale");
        require(!poolStats.stopped,  "contribute(): Error, the pool was stopped");
        contributors[msg.sender].lastContributionTime = block.timestamp;
        if(contributors[msg.sender].lastContributionTime == 0) contributorList.push(msg.sender);
        contributors[msg.sender].grossContribution = contributors[msg.sender].grossContribution.add(msg.value);
        poolStats.allGrossContributions = poolStats.allGrossContributions.add(msg.value);
        emit contributed(msg.sender, msg.value);
    }

    function calculateReward(uint toDistribute, address contributor) private view returns (uint) {
        return (toDistribute * ( (1 ether) * contributors[contributor].grossContribution / poolStats.allGrossContributions)) / (1 ether);
    }

    function calculateERC20OwedToContributor(address tokenType, address contributor) private view returns (uint) {
        uint totalBalance = totalPayedOut[tokenType].add(ERC20Basic(tokenType).balanceOf(address(this)));
        uint totalReward = calculateReward(totalBalance, contributor);
        return totalReward.sub(payedOut[contributor][tokenType]);
    }

    function calculateETHOwedToContributor(address contributor) private view returns (uint) {
        uint totalBalance = totalPayedOut[0x0].add(address(this).balance.sub(poolStats.creatorStash.add(poolStats.providerStash)));
        uint totalReward = calculateReward(totalBalance, contributor);
        return totalReward.sub(payedOut[contributor][0x0]);
    }

    function tokensOwedToContributor(address contributor) public view returns (uint) {
        return calculateERC20OwedToContributor(params.tokenAddress, contributor);
    }

    function withdraw(uint amount) public {
        require(!poolStats.sentToSale, "withdraw(): Error, the pools funds were already sent to the sale");
        if(!poolStats.stopped){
            require(contributors[msg.sender].lastContributionTime.add(params.withdrawTimelock) <= block.timestamp, "withdraw(): Error, the timelock is not over yet");
            require(contributors[msg.sender].grossContribution >= amount, "withdraw(): Error, tx sender has not enough funds in pool");
            require(contributors[msg.sender].grossContribution.sub(amount) >= params.minContribution, "withdraw(): Error, remaining contribution amount would have been less than 'minContribution'");
            if(amount == 0) require(params.minContribution == 0, "withdraw(): Error, remaining contribution amount would have been less than 'minContribution'");
        }
        uint transferAmount;
        if (amount == 0 || poolStats.stopped) {
            transferAmount = contributors[msg.sender].grossContribution;
        } else {
            transferAmount = amount;
        }
        poolStats.allGrossContributions = poolStats.allGrossContributions.sub(transferAmount);
        contributors[msg.sender].grossContribution = contributors[msg.sender].grossContribution.sub(transferAmount);
        msg.sender.transfer(amount);
    }

    function withdrawRefund() public {
        require(poolStats.sentToSale, "withdrawRefund(): Error, the pools funds were not sent to the sale yet");
        uint amount = calculateETHOwedToContributor(msg.sender);
        payedOut[msg.sender][0x0] = payedOut[msg.sender][0x0].add(amount);
        totalPayedOut[0x0] = totalPayedOut[0x0].add(amount);
        msg.sender.transfer(amount);
    }

    function sendOutToken(address _tokenAddress, address recipient) private {
        require(poolStats.sentToSale, "sendOutToken(address _tokenAddress, address recipient): Error, the pools funds were not sent to the sale yet");
        require(params.tokenAddress != 0x0, "sendOutToken(address _tokenAddress, address recipient): Error, ERC20 token addres cannot be 0x0, that is reserved for ether");
        uint amount = calculateERC20OwedToContributor(_tokenAddress, recipient);
        payedOut[recipient][_tokenAddress] = payedOut[recipient][_tokenAddress].add(amount);
        totalPayedOut[_tokenAddress] = totalPayedOut[_tokenAddress].add(amount);
        ERC20Basic(_tokenAddress).transfer(recipient, amount);
    }

    function stopPool() public onlyCreator {
        require(!poolStats.sentToSale, "stopPool(): Error, the pools funds were already sent to the sale");
        poolStats.stopped = true;
    }

    function withdrawToken() public {
        sendOutToken(params.tokenAddress, msg.sender);
    }

    function withdrawCustomToken(address customTokenAddress) public{
        sendOutToken(customTokenAddress, msg.sender);
    }

    function pushOutToken(address recipient) public onlyAdmin{
        sendOutToken(params.tokenAddress, recipient);
    }

    function confirmTokensReceived(uint tokensExpected) public onlyAdmin{
        require(poolStats.sentToSale, "confirmTokensReceived(uint tokensExpected): Error, the pools funds were not sent to the sale yet");
        require(!poolStats.tokensReceivedConfirmed, "confirmTokensReceived(uint tokensExpected): Error, tokens are already confirmed as received");
        require (tokensExpected > 0, "confirmTokensReceived(uint tokensExpected): Error, number of tokens expected has to be greater than 0");
        if(ERC20Basic(params.tokenAddress).balanceOf(address(this)) > tokensExpected) poolStats.tokensReceivedConfirmed = true;
    }

    function sendToSale() public onlyAdmin{
        require(!poolStats.stopped,  "sendToSale(): Error, the pool was stopped");
        require(params.saleParticipateCalldata.length == 0, "sendToSale(): Error, participation function signature is given, 'sendToSaleWithCalldata()' has to be used");
        require(!poolStats.sentToSale, "sendToSale(): Error, the pools funds were already sent to the sale");
        require(now >= params.saleStartDate, "sendToSale(): Error, sale hasn't started yet");
        require(block.timestamp < params.saleEndDate, "sendToSale(): Error, the sale has ended");
        require(calculateNetContribution() >= params.minPoolGoal, "sendToSale(): Not enough funds collected for sale");
        takeFees();
        params.saleAddress.transfer(calculateNetContribution());
        poolStats.sentToSale = true;
    }

    function sendToSaleWithCalldata() public onlyAdmin {
        require(!poolStats.stopped,  "sendToSaleWithCalldata(): Error, the pool was stopped");
        require(params.saleParticipateCalldata != 0x0, "sendToSaleWithCalldata(): Error, no participation function signature given");
        require(!poolStats.sentToSale, "sendToSaleWithCalldata(): Error, the pools funds were already sent to the sale");
        require(now >= params.saleStartDate, "sendToSaleWithCalldata(): Error, sale hasn't started yet");
        require(block.timestamp < params.saleEndDate, "sendToSaleWithCalldata(): Error, the sale has ended");
        require(calculateNetContribution() >= params.minPoolGoal, "sendToSaleWithCalldata():: Not enough funds collected for sale");
        takeFees();
        require(params.saleAddress.call.value(calculateNetContribution())(bytes4(keccak256(params.saleParticipateCalldata))), "Error, transaction failed");
        poolStats.sentToSale = true;
    }

    function sendToSaleWithCalldataParameter(bytes32 calldata) public onlyAdmin {
        require(!params.strictlyTrustlessPool, "sendToSaleWithCalldataParameter(bytes32 calldata): Error, pool is 'strictlyTrustlessPool'");
        require(!poolStats.stopped,  "sendToSaleWithCalldata(): Error, the pool was stopped");
        require(calldata != 0x0, "sendToSaleWithCalldata(): Error, no participation function signature given");
        require(!poolStats.sentToSale, "sendToSaleWithCalldata(): Error, the pools funds were already sent to the sale");
        require(now >= params.saleStartDate, "sendToSaleWithCalldata(): Error, sale hasn't started yet");
        require(block.timestamp < params.saleEndDate, "sendToSaleWithCalldata(): Error, the sale has ended");
        require(calculateNetContribution() >= params.minPoolGoal, "sendToSaleWithCalldata():: Not enough funds collected for sale");
        takeFees();
        require(params.saleAddress.call.value(calculateNetContribution())(bytes4(keccak256(calldata))), "Error, transaction failed");
        poolStats.sentToSale = true;
    }


    function takeFees() private returns(uint) {
        poolStats.creatorStash = calculateFee(poolStats.allGrossContributions, params.creatorFeeRate);
        poolStats.providerStash = calculateFee(poolStats.allGrossContributions, params.providerFeeRate);
    }


    function calculateNetContribution() private view returns (uint) {
        return poolStats.allGrossContributions.sub(poolStats.creatorStash.sub(poolStats.providerStash));
    }

    function calculateFee(uint value, uint feePerThousand) private pure returns(uint fee) {
        return (value / 1000).mul(feePerThousand);
    }

    function withdrawFromSaleWithCalldata() public onlyAdmin{
        require(params.saleWithdrawCalldata != 0x0, "withdrawFromSaleWithCalldata(): Error, no withdraw function signature given");
        require(poolStats.sentToSale, "withdrawFromSaleWithCalldata(): Error, the pools funds were not sent to the sale yet");
        require(params.saleAddress.call(bytes4(keccak256(params.saleWithdrawCalldata))), "withdrawFromSaleWithCalldata(): Error, transaction failed");
    }

    function withdrawFromSaleWithCalldataParameter(bytes32 calldata) public onlyAdmin{
        require(!params.strictlyTrustlessPool, "withdrawFromSaleWithCalldataParameter(bytes32 calldata): Error, pool is 'strictlyTrustlessPool'");
        require(params.saleWithdrawCalldata != 0x0, "withdrawFromSaleWithCalldata(): Error, no withdraw function signature given");
        require(poolStats.sentToSale, "withdrawFromSaleWithCalldata(): Error, the pools funds were not sent to the sale yet");
        require(params.saleAddress.call(bytes4(keccak256(params.saleWithdrawCalldata))), "withdrawFromSaleWithCalldata(): Error, transaction failed");
    }

    function () public payable {
        //empty fallback to take refund tx-s
    }

    function providerWithdraw() public onlyProvider{
        uint amount = poolStats.providerStash;
        poolStats.providerStash = 0;
        params.creator.transfer(amount);
    }

    function creatorWithdraw() public onlyCreator{
        uint amount = poolStats.creatorStash;
        poolStats.creatorStash = 0;
        params.creator.transfer(amount);
    }

    function setParamsCreator(
        address _creator,
        uint16 _creatorFeeRate, // 1/1000
        uint32 _saleStartDate,
        uint32 _saleEndDate,
        uint32 _withdrawTimelock,
        uint256 _minContribution, //minimum amount expected from pool participants
        uint256 _maxContribution, //maximum amount expected from pool participants 0: no limit
        uint256 _minPoolGoal,  //minimum amount needed for the sale
        bool _whitelistPool,
        bytes32 _poolDescription,
        address _tokenAddress, // address of erc20 token contract
        bool[11] toSet
    ) public onlyCreator {
        if(toSet[0]){
            params.creator = _creator;
        }
        if(toSet[1]){
            params.creatorFeeRate = _creatorFeeRate;
        }
        if(toSet[2]){
            params.saleStartDate = _saleStartDate;
        }
        if(toSet[3]){
            params.saleEndDate = _saleEndDate;
        }
        if(toSet[4]){
            params.withdrawTimelock = _withdrawTimelock;
        }
        if(toSet[5]){
            params.minContribution = _minContribution;
        }
        if(toSet[6]){
            params.maxContribution = _maxContribution;
        }
        if(toSet[7]){
            params.minPoolGoal = _minPoolGoal;
        }
        if(toSet[8]){
            params.whitelistPool = _whitelistPool;
        }
        if(toSet[9]){
            params.poolDescription = _poolDescription;
        }
        if(toSet[10]){
            require(!poolStats.tokensReceivedConfirmed, "setTokenAddress(address _tokenAddress): Error, tokens are already confirmed as received");
            params.tokenAddress = _tokenAddress;
        }
    }

    function setParamsProvider(
        address _provider, //connectICO address for fees
        uint16 _providerFeeRate, // 1/1000
        uint256 _maxPoolAllocation, //maximum amount raisable by pool
        bool[3] toSet
    ) public onlyProvider {
        if(toSet[0]){
            params.provider = _provider;
        }
        if(toSet[1]){
            params.providerFeeRate = _providerFeeRate;
        }
        if(toSet[2]){
            params.maxPoolAllocation = _maxPoolAllocation;
        }
    }

    function setSaleParticipateCalldata(bytes32 calldata) public onlyAdmin{
        require(!params.strictlyTrustlessPool, "setsaleParticipateCalldata(bytes32 calldata): Error, pool is 'strictlyTrustlessPool'");
        params.saleParticipateCalldata = calldata;
    }

    function setSaleWithdrawCalldata(bytes32 calldata) public onlyAdmin{
        require(!params.strictlyTrustlessPool, "setSaleWithdrawCalldata(bytes32 calldata): Error, pool is 'strictlyTrustlessPool'");
        params.saleWithdrawCalldata = calldata;
    }

    function getParams1() public view returns (
        uint16 providerFeeRate, // 1/1000
        uint16 creatorFeeRate, // 1/1000
        uint32 saleStartDate,
        uint32 saleEndDate,
        uint32 withdrawTimelock,
        uint256 minContribution, //minimum amount expected from pool participants
        uint256 maxContribution, //maximum amount expected from pool participants 0: no limit
        uint256 minPoolGoal,  //minimum amount needed for the sale
        uint256 maxPoolAllocation //maximum amount raisable by pool
    )
    {
        return(
            params.providerFeeRate,
            params.creatorFeeRate,
            params.saleStartDate,
            params.saleEndDate,
            params.withdrawTimelock,
            params.minContribution,
            params.maxContribution,
            params.minPoolGoal,
            params.maxPoolAllocation
        );
    }

    function getParams2() public view returns (
        bool whitelistPool,
        bool strictlyTrustlessPool,
        bytes32 saleParticipateCalldata,
        bytes32 saleWithdrawCalldata,
        bytes32 poolDescription,
        address saleAddress, //address of token sale
        address tokenAddress, // address of erc20 token contract
        address kycAddress,
        address provider, //connectICO address for fees
        address creator //pool creator address
    )
    {
        return(
            params.whitelistPool,
            params.strictlyTrustlessPool,
            params.saleParticipateCalldata,
            params.saleWithdrawCalldata,
            params.poolDescription,
            params.saleAddress,
            params.tokenAddress,
            params.kycAddress,
            params.provider,
            params.creator
        );
    }

}
