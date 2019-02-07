pragma solidity ^0.5.3;

contract BrokerEvents {
    event SetAllowance(
        address indexed admin,
        address indexed user,
        address gem,
        uint allowance
    );
}