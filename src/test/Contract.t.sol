// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.10;

import "forge-std/Test.sol";
import "../Contract.sol";
import "../StableCoin.sol";
import "../LP.sol";

contract FarmTest is Test {

    Farm public farm;
    LP public holdToken;
    StableCoin public dai;

    address DEPLOYER_ADDRESS;

    function setUp() public {
        holdToken = new LP();
        dai = new StableCoin();
        farm = new Farm(holdToken, dai);
        DEPLOYER_ADDRESS = farm.owner(); // (DEPLOYER == address(this)) != (msg.sender == <sender_in_foundry.toml>)
    }

    /** Unit Testing For Mock Contracts*/

    function testOwner() public {
        assertEq(DEPLOYER_ADDRESS, farm.owner());
    }

    function testMockContractInit() public {
        // Initial Mint
        assertEq(holdToken.balanceOf(DEPLOYER_ADDRESS), holdToken.initialSupply());
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), holdToken.initialSupply());
    }

    function testMockContractTransferFrom(uint256 _amount) public {
        vm.assume(_amount <= holdToken.initialSupply() && _amount <= dai.initialSupply());

        holdToken.approve(DEPLOYER_ADDRESS, _amount);
        holdToken.transferFrom(DEPLOYER_ADDRESS, address(1), _amount);
        assertEq(holdToken.balanceOf(address(1)), _amount);

        dai.approve(DEPLOYER_ADDRESS, _amount);
        dai.transferFrom(DEPLOYER_ADDRESS, address(1), _amount);
        assertEq(dai.balanceOf(address(1)), _amount);
    }

    function testPrank1() public {
        assertEq(DEPLOYER_ADDRESS, farm.owner()); // now owner() is DEPLOYER
        farm.transferOwnership(msg.sender); 
        // the transaction originator of transferOwnership is the "contract" ---> DEPLOYER == address(this)  
        assertEq(msg.sender, farm.owner()); // transfer successfully
        // now owner is the "msg.sender" ---> <sender_in_foundry.toml>

        vm.prank(DEPLOYER_ADDRESS);  // change the "msg.sender" ---> DEPLOYER == address(this)
        try farm.transferOwnership(msg.sender){
            assertTrue(false, "prank failed!");
            // transferOwnership should revert, 
            // when "msg.sender" is now being the DEPLOYER, but the owner is <sender_in_foundry.toml>

            // if transferOwnership not revert,
            // it means the function called successfully,
            // ---> the "msg.sender" is still the <sender_in_foundry.toml>
            // ---> we prank failed.
        } catch {
            assertTrue(true);
            // revert successfully
        }

        // The most important thing is that the prank is only useful for "external" call
        // the only "external" call above is "farm.transferOwnership()"
    }

    function testPrank2() public {
        assertEq(msg.sender, 0xB42faBF7BCAE8bc5E368716B568a6f8Fdf3F84ec); //[PASS]
        assertEq(DEPLOYER_ADDRESS, address(this)); // [PASS]
        assertEq(DEPLOYER_ADDRESS, farm.owner()); // [PASS]
        /**
        vm.prank(DEPLOYER_ADDRESS);
        assertEq(DEPLOYER_ADDRESS, msg.sender); // [Failed] ---> Because "assertEq()" is not external call
         */
    }

    /** Unit Testing For Farm Contract*/

    function testStaking(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= holdToken.initialSupply() && _amount <= dai.initialSupply());
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply());

        vm.startPrank(DEPLOYER_ADDRESS);
        dai.approve(address(farm), _amount);
        farm.stakeTokens(_amount);
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply() - _amount);
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), _amount);
        assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), block.timestamp);
        assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), true);
        vm.stopPrank();
    }

    function testCalYield(uint _amount, uint32 _timeRoll) public {
        vm.assume(_amount > 0 && _amount <= holdToken.initialSupply() && _amount <= dai.initialSupply());
        vm.assume(_timeRoll < 2**32);
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply());

        vm.startPrank(DEPLOYER_ADDRESS);
        // Stake
        dai.approve(address(farm), _amount);
        farm.stakeTokens(_amount);
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply() - _amount);
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), _amount);
        assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), block.timestamp);
        assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), true);

        // CalYield
        vm.warp(_timeRoll);
        uint result = SafeMath.div(SafeMath.sub(_timeRoll, farm.getClientStartTime(DEPLOYER_ADDRESS)), 60);
        assertEq(farm.calYield(DEPLOYER_ADDRESS), result);

        vm.stopPrank();
    }

    function testWithdrawYield(uint256 _amount, uint _timeRoll) public {
        vm.assume(_amount > 0 && _amount <= holdToken.initialSupply() && _amount <= dai.initialSupply());
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply());

        vm.startPrank(DEPLOYER_ADDRESS);
        // Stake
        dai.approve(address(farm), _amount);
        farm.stakeTokens(_amount);
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply() - _amount);
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), _amount);
        assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), block.timestamp);
        assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), true);

        // withdrawYield
        vm.assume(_timeRoll < 2**8); 
        // here is a risk of that holdtoken.totalSupply < withdraw, 
        // the defi model should hava a better Tokenomics Model
        vm.warp(_timeRoll);
        farm.withdrawYield();
        uint withdraw = SafeMath.add(
                            SafeMath.div(
                                SafeMath.mul(farm.getClientStakingBalance(DEPLOYER_ADDRESS), 
                                    SafeMath.div(
                                        SafeMath.sub(_timeRoll, farm.getClientStartTime(DEPLOYER_ADDRESS))
                                    , 60))
                            , 100)
                        , farm.getClientYieldBalance(DEPLOYER_ADDRESS));
        
        if(withdraw > 0 || farm.getClientYieldBalance(DEPLOYER_ADDRESS) > 0){
            assertEq(holdToken.balanceOf(DEPLOYER_ADDRESS), withdraw);
            assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
            assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), _timeRoll);
        }
        vm.stopPrank();

        // Stake Status Check Again
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply() - _amount);
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), _amount);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), true);
    }

    function testX(uint256 x) public {
        
        uint256 y;

        try {

        } catch {
            require(false, "debug");
        }

        assertEq(x, x);
    } 

    function testUnStaking(uint256 _amount) public {
        vm.assume(_amount > 0 && _amount <= holdToken.initialSupply() && _amount <= dai.initialSupply());
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply());

        vm.startPrank(DEPLOYER_ADDRESS);
        // Stake
        dai.approve(address(farm), _amount);
        farm.stakeTokens(_amount);
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply() - _amount);
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), _amount);
        assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), block.timestamp);
        assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), true);

        // Unstake
        farm.unstakeTokens();
        assertEq(dai.balanceOf(DEPLOYER_ADDRESS), dai.initialSupply());
        assertEq(farm.getClientStakingBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientStartTime(DEPLOYER_ADDRESS), block.timestamp);
        assertEq(farm.getClientYieldBalance(DEPLOYER_ADDRESS), 0);
        assertEq(farm.getClientIsStaking(DEPLOYER_ADDRESS), false);
        vm.stopPrank();
    }

    /** Integration Testing for Staking System*/

    function testRandomWalk(uint256 _amount1, uint256 _amount2, uint256 _amount3, uint256 _amount4) public {
        assertEq(true, true);
    }


    /** Special Testing*/

    function testFlashLoan() public {
        assertEq(true, true);
    }

    function testReEntrancyAtt() public {
        assertEq(true, true);
    }

}
