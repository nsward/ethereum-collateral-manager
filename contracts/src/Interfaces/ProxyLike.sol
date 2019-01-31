pragma solidity ^0.5.2;

contract ProxyLike {

    // Transfer tokens between addresses. 'dumb' implementation that can
    // only be called by the Vault contract
    function deal(address token, address sender, address recipient, uint amt)
        external 
        returns (bool);
}