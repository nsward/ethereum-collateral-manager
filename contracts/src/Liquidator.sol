pragma solidity ^0.5.3;

import "../lib/AuthTools.sol";

contract BrokerLike {
    function safe(bytes32) public view returns (bool);
}

contract VatLike {

}

contract Liquidator is Ownable {
    
    VatLike public vat;
    BrokerLike public broker;

    constructor(address _vat, address _broker) public {
        vat = VatLike(_vat);
        broker = BrokerLike(_broker);
    }

    function bite(bytes32 acctKey) external {
        require(!broker.safe(acctKey), "ccm-biter-bite-account-is-safe");

        // TODO: check if at end of call phase?

        // give all heldGem to biter in exchange for biteFee discounted amount of owedGem
        


        // _grab(acctKey);
    }

    function _grab(bytes32 acctKey) private {
        // get 
    }
}