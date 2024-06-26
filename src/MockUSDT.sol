// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock USDT, FOR TESTING ONLY
contract MockUSDT is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        _mint(_msgSender(), 100_000_000_000 ether);
    }
}