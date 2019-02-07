pragma solidity ^0.5.3;

import "../lib/AuthTools.sol";
import "./interfaces/GemLike.sol";

// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/TokenProxy.sol
contract Proxy is AuthAndOwnable {

    // Transfer tokens between addresses
    function deal(address gem, address sender, address recipient, uint amt)
        external 
        auth 
        returns (bool)
    {
        return GemLike(gem).transferFrom(sender, recipient, amt);
    }
}