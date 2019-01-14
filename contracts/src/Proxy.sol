pragma solidity 0.5.2;

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
    // deal, pass
    function deal(address gem, address src, address dst, uint amt)
        external 
        onlyVault 
        returns (bool)
    {
        return IERC20(gem).transferFrom(src, dst, amt);
    }

    // TODO: Remove
    // // Check how much we can transfer from another address to our address
    // function ours(address _gem, address src) external view returns (uint) {
    //     IERC20 gem = IERC20(_gem);
    //     // uint allowance = gem.allowance(src, address(this))
    //     // uint theirBalance = gem.balanceOf(src);
        
    //     // minimum of user's allowance to us and their token balance
    //     return min(gem.allowance(src, address(this), gem.balanceOf(src));
    // }
}