pragma solidity ^0.5.2;

import "../src/Chief.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

// Contract used to test Chief contract
contract Tester is Ownable {
    Chief public chief;

    constructor(address _chief) public {
        chief = Chief(_chief);
    }

    function open(
        uint    tab, 
        uint    zen, 
        address lad, 
        address due,
        bool    mom
    )
        public returns (bool)
    {
        return chief.open(tab, zen, lad, due, mom);
    }

    function open(
        uint    tab,
        uint    zen,
        address lad
    )
        external returns (bool)
    {
        return chief.open(tab, zen, lad);
    }

    
    function bump(address _gem, bool _use) external returns (bool) {
        return chief.bump(_gem, _use);
    }
}