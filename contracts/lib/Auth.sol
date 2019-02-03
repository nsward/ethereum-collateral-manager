pragma solidity ^0.5.0;

contract Auth {
    event AddAuth(
        address added,
        address adder
    );
    event RemoveAuth(
        address removed,
        address remover
    );
    event ChangeOwner(
        address newOwner,
        address oldOwner
    );
    address public owner;
    mapping (address => uint) public auths;
    modifier auth { require(auths[msg.sender] == 1, "ccm-auth"); _; }
    modifier onlyOwner {
        require(msg.sender == owner, "ccm-onlyOwner");
        _;
    }
    function addAuth(address guy) public onlyOwner {
        auths[guy] = 1; 
        emit AddAuth(guy, msg.sender);
    }
    function removeAuth(address guy) public onlyOwner { 
        auths[guy] = 0; 
        emit RemoveAuth(guy, msg.sender);
    }
    function changeOwner(address guy) public onlyOwner {
        owner = guy;
        emit ChangeOwner(guy, msg.sender);
    }

    // --- Init ---
    constructor() public {
        owner = msg.sender;
        emit ChangeOwner(msg.sender, address(0));
    }
}