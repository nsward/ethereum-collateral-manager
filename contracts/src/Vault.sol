pragma solidity ^0.5.2;

import "./Proxy.sol";
import "../lib/DSMath.sol";
import "../lib/DSNote.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/Vault.sol
contract Vault is Ownable, DSMath, DSNote {

    // address public PROXY;
    Proxy   public proxy;
    address public chief;

    modifier onlyChief() {require(msg.sender == chief, "ccm-vault-auth");_;}

    // TODO: make sure we're emitting sufficient events for users to find these
    // for claim(). Note that this is the net payouts from all accounts user/contract 
    // is involved in and is separate from the balance within accounts
    // user => token address => balance of that token that is held in vault
    mapping(address => mapping(address => uint)) public claims;

    // Keep track of all our $$$
    // Note that this is only updated when tokens come in or out. No change
    // when we move balances from accounts to claims
    mapping (address => uint) public chest;

    // Transfer tokens from user to us
    function take(address gem, address src, uint amt) external onlyChief returns (bool) {
        require(proxy.deal(gem, src, address(this), amt), "ccm-vault-take-deal-failed");
        chest[gem] = add(chest[gem], amt);
        verifyBalance(gem);
        return true;
    }

    // Transfer tokens from us to user
    function give(address _gem, address dst, uint amt) external onlyChief returns (bool) {
        // This is also asserted by line below, but leaving extra check in here for now
        // require(claims[dst][_gem] >= amt, "ccm-vault-give-insufficient-balance");
        claims[dst][_gem] = sub(claims[dst][_gem], amt);
        chest[_gem] = sub(chest[_gem], amt);
        IERC20 gem = IERC20(_gem);
        // NOTE: this is pull only - i.e. this will only be called from Chief.pull()
        require(gem.transfer(dst, amt), "ccm-vault-give-transfer-failed");

        verifyBalance(_gem);

        return true;
    }

    // Add to user's claim balance
    function addClaim(address gem, address lad, uint amt) external onlyChief {
        claims[lad][gem] = add(claims[lad][gem], amt);
    }

    // Verify that nothing has gone crazy
    function verifyBalance(address gem) private view {
        // If this is false, we have big problems
        assert(IERC20(gem).balanceOf(address(this)) >= chest[gem]);
    }

    ///////////
    // Owner Functions
    ///////////

    function file(bytes32 what, address data) external note onlyOwner {
        if (what == "proxy") proxy = Proxy(data);
        if (what == "chief") {
            require(chief == address(0), "ccm-vault-init-no-new-chief");
            chief = data;
        }
    }

    // // Vault has to be deployed before Chief and Proxy, so no constructor
    // // Use this to set other contract addresses
    // function initAuthContracts(address _chief, address _proxy) external onlyOwner {
    //     // Prevent owner from changing chief address
    //     require(chief == address(0), "ccm-vault-init-no-new-chief");
         
    //     proxy = Proxy(_proxy);
    // }

}