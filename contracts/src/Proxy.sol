pragma solidity ^0.5.3;

import "../lib/DSMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/TokenProxy.sol
contract Proxy is DSMath {
    
    address public vault;

    modifier onlyVault() {require(msg.sender == vault, "ccm-proxy-auth");_;}

    constructor(address _vault) public {
        vault = _vault;
    }

    // Transfer tokens between addresses. 'dumb' implementation that can
    // only be called by the Vault contract
    function deal(address token, address sender, address recipient, uint amt)
        external 
        onlyVault 
        returns (bool)
    {
        return IERC20(token).transferFrom(sender, recipient, amt);
    }
}