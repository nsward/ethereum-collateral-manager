pragma solidity ^0.5.3;

contract ExecEvents {
    event Open(
        address indexed admin,
        address indexed user,
        address owedGem,
        uint owedTab
    );
}