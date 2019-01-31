// For use with 0x V2 contracts

pragma solidity ^0.5.2;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

contract ZeroExWrapper {

    address public chief;
    address public vault;

    address public zeroExExchange;
    address public zeroExProxy;
    IERC20 public zrx;


    modifier onlyChief() { require(msg.sender == chief, "ccm-ZeroExWrapper-auth");_; }

    constructor(
        address _chief, 
        address _vault, 
        address _zeroExExchange,
        address _zeroExProxy,
        address _zrx
    ) 
        public 
    {
        chief = _chief;
        vault = _vault;
        zeroExExchange = _zeroExExchange;
        zeroExProxy = _zeroExProxy;
        zrx = IERC20(_zrx);
    }


    function fillOrKill(
        address tradeOrigin,
        address makerAsset,
        address takerAsset,
        uint makerAmt,          // -- might not need this. all we care about at this point is fill amt?
        uint takerAmt,          // -- same?
        uint fillAmt,
        bytes calldata orderData
    )
        external onlyChief returns (uint)
    {
        // ** make sure we're approving the vault to take everything
        // Also need to take taker fee from user? --- need to get this from chief

    }
}