pragma solidity ^0.5.2;

import "../src/Chief.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
// this import is just here so the ERC20Mintable contract compiles for testing
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";

// Contract used to test Chief contract
contract Tester is Ownable {
    Chief public chief;

    constructor(address _chief) public {
        chief = Chief(_chief);
    }

    function open(
        uint    dueTab, 
        uint    callTime, 
        address user, 
        address dueToken,
        bool    useExecParams
    )
        public returns (bool)
    {
        return chief.open(dueTab, callTime, user, dueToken, useExecParams);
    }

    function open(
        uint    dueTab,
        uint    callTime,
        address user
    )
        external returns (bool)
    {
        return chief.open(dueTab, callTime, user);
    }
 
    function toggleExecAsset(address token, bool use) external returns (bool) {
        return chief.toggleExecAsset(token, use);
    }
}