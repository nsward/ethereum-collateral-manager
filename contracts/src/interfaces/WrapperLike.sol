pragma solidity ^0.5.3;

// interface for exchange wrapper contracts
contract WrapperLike {
    function fillOrKill(address, address, address, uint, uint, uint, bytes calldata) 
        external returns (uint);
}