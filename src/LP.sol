pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LP is ERC20 {

    uint256 public initialSupply = 10000;
    constructor() ERC20("MyToken", "MT") {
        _mint(msg.sender, initialSupply);
    }
}
