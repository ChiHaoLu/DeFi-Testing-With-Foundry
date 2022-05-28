pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StableCoin is ERC20 {

    uint256 public initialSupply = 10000;
    constructor() ERC20("TestDAI", "tDAI") {
        _mint(msg.sender, initialSupply);
    }
}
