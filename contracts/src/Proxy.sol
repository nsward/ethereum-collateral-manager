pragma solidity ^0.5.3;

import "../lib/AuthTools.sol";
import "./interfaces/GemLike.sol";

// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/TokenProxy.sol
contract Proxy is AuthAndOwnable {
    
    // address public vault;

    // modifier onlyVault() {require(msg.sender == vault, "ccm-proxy-auth");_;}

    // constructor(address _vault) public {
    //     vault = _vault;
    // }

    // Transfer tokens between addresses. 'dumb' implementation that can
    // only be called by the Vault contract
    function deal(address gem, address sender, address recipient, uint amt)
        external 
        auth 
        returns (bool)
    {
        return GemLike(gem).transferFrom(sender, recipient, amt);
    }
}