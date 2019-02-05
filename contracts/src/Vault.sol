pragma solidity ^0.5.3;


// import "../lib/DSMath.sol";
// import "../lib/DSNote.sol";
// import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";
import "./interfaces/ProxyLike.sol";
import "./interfaces/GemLike.sol";
// import "openzeppelin-solidity/contracts/math/SafeMath.sol";


// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/Vault.sol
// use MathTools
// AuthTools
contract Vault is AuthAndOwnable {

    constructor(address _proxy) public {
        proxy = ProxyLike(_proxy);
    }

    // address public PROXY;
    ProxyLike public proxy;
    // address public chief;
    // modifier onlyChief() {require(msg.sender == chief, "ccm-vault-auth");_;}

    // TODO: make sure we're emitting sufficient events for users to find these
    // for claim(). Note that this is the net payouts from all accounts user/contract 
    // is involved in and is separate from the balance within accounts
    // user => token address => balance of that token that is held in vault
    // mapping(address => mapping(address => uint)) public claims;

    // Keep track of all our $$$
    // Note that this is only updated when tokens come in or out. No change
    // when we move balances from accounts to claims
    mapping (address => uint) public chest;

    // Transfer tokens from user to us
    function take(address _gem, address src, uint amt) external auth returns (bool) {
        require(proxy.deal(_gem, src, address(this), amt), "ccm-vault-take-deal-failed");
        chest[_gem] = SafeMath.add(chest[_gem], amt);
        verifyBalance(_gem);
        return true;
    }

    // Transfer tokens from us to user
    function give(address _gem, address dst, uint amt) external auth returns (bool) {
        // This is also asserted by line below, but leaving extra check in here for now
        // require(claims[dst][_gem] >= amt, "ccm-vault-give-insufficient-balance");
        // claims[dst][_gem] = sub(claims[dst][_gem], amt);
        chest[_gem] = SafeMath.sub(chest[_gem], amt);
        GemLike gem = GemLike(_gem);
        // NOTE: this is pull only
        require(gem.transfer(dst, amt), "ccm-vault-give-transfer-failed");

        verifyBalance(_gem);

        return true;
    }

    // // Add to user's claim balance
    // function addClaim(address _gem, address lad, uint amt) external onlyChief {
    //     claims[lad][_gem] = SafeMathadd(claims[lad][_gem], amt);
    // }

    // Verify that nothing has gone crazy
    function verifyBalance(address _gem) private view {
        // If this is false, something is wrong
        assert(GemLike(_gem).balanceOf(address(this)) >= chest[_gem]);
    }


    function giveToWrapper(address _gem, address dst, uint amt) external auth returns (bool) {
        chest[_gem] = SafeMath.sub(chest[_gem], amt);
        GemLike gem = GemLike(_gem);
        require(gem.transfer(dst, amt), "ccm-vault-giveToWrapper-transfer-failed");
        verifyBalance(_gem);
        return true;
    }

    function takeFromWrapper(address _gem, address src, uint amt) external auth returns (bool) {
        chest[_gem] = SafeMath.add(chest[_gem], amt);
        GemLike gem = GemLike(_gem);
        require(gem.transferFrom(src, address(this), amt), "ccm-vault-takeFromWrapper-transfer-failed");
        verifyBalance(_gem);
        return true;
    }

    ///////////
    // Owner Functions
    ///////////

    function file(bytes32 what, address data) external onlyOwner {
        if (what == "proxy") proxy = ProxyLike(data);
        // if (what == "chief") chief = data;
    }

}