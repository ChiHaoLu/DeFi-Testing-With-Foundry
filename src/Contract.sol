// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./StableCoin.sol";
import "./LP.sol";
import "./safeMath.sol";
import "./Ownable.sol";

contract Farm is Ownable {
    LP public holdToken;
    StableCoin public dai;

    constructor(LP _holdToken, StableCoin _dai) {
        holdToken = _holdToken;
        dai = _dai;
    }

    /** Constructs the Data Structures */

    struct ClientInfo {
        uint startTime;
        uint stakingBalance;
        uint yieldBalance;
        bool isStaking;
    }

    mapping(address => ClientInfo) public ClientList;

    /** Getter Function */

    function getClientStartTime(address _addr) view public returns(uint){
        return ClientList[_addr].startTime;
    }
    function getClientStakingBalance(address _addr) view public returns(uint){
        return ClientList[_addr].stakingBalance;
    }
    function getClientYieldBalance(address _addr) view public returns(uint){
        return ClientList[_addr].yieldBalance;
    }
    function getClientIsStaking(address _addr) view public returns(bool){
        return ClientList[_addr].isStaking;
    }

    /** Algorithms */

    function stakeTokens(uint _amount) public {
        require(_amount > 0, 'You cannot stake 0 tokens');

        uint oldDaiBal = dai.balanceOf(msg.sender);
        require( oldDaiBal > _amount, "insufficient DAI!");

        uint256 allowance = dai.allowance(msg.sender, address(this));
        require(allowance >= _amount, "Check the token allowance");
        
        dai.transferFrom(msg.sender, address(this), _amount);
        require(dai.balanceOf(msg.sender) == oldDaiBal - _amount, "Transfer Failed!");
        require(dai.balanceOf(address(this)) == _amount, "Transfer Failed!");

        uint oldBalance = ClientList[msg.sender].stakingBalance;
        ClientList[msg.sender].stakingBalance = SafeMath.add(ClientList[msg.sender].stakingBalance, _amount);
        require(ClientList[msg.sender].stakingBalance > oldBalance, "Staking Bug!");

        ClientList[msg.sender].startTime = block.timestamp;
        ClientList[msg.sender].isStaking = true;
    }

    function calYield(address _address) public view returns(uint){
        uint end = block.timestamp;
        uint totalTime = SafeMath.sub(end, ClientList[_address].startTime);
        return SafeMath.div(totalTime, 60);
        // Yield Per Minute
    }

    function withdrawYield() public {

        uint profit = calYield(msg.sender);
        uint withdraw = SafeMath.div(SafeMath.mul(ClientList[msg.sender].stakingBalance, profit), 100);

        if(ClientList[msg.sender].yieldBalance > 0){
            uint originalYBal = ClientList[msg.sender].yieldBalance;
            ClientList[msg.sender].yieldBalance = 0;
            withdraw = SafeMath.add(withdraw, originalYBal);
        }

        if(withdraw == 0 && ClientList[msg.sender].yieldBalance == 0){
            return ;
        }

        ClientList[msg.sender].startTime = block.timestamp;
        holdToken.transfer(msg.sender, withdraw);
    }

    function unstakeTokens() public {
        require(ClientList[msg.sender].isStaking, 'You are not staker!');
        
        withdrawYield();
        
        uint balance = ClientList[msg.sender].stakingBalance;
        require(balance > 0, "There is no fund in your staking account!");
        
        // need to prevent re-entrancy attack later!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        dai.transfer(msg.sender, balance);
        ClientList[msg.sender].stakingBalance = 0;
        ClientList[msg.sender].isStaking = false;
    }
}
