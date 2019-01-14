pragma solidity 0.5.2;

import "./Proxy.sol";
import "../lib/DSMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";

// modeled after https://github.com/dydxprotocol/protocol/blob/master/contracts/margin/Vault.sol
contract Vault is Ownable, DSMath {

    // address public PROXY;
    Proxy   public proxy;
    address public chief;

    modifier onlyChief() {require(msg.sender == chief, "ccm-vault-auth");_;}

    // TODO: make sure we're emitting sufficient events for users to find these
    // for pull(). Note that this is the net payouts from all accounts user/contract 
    // is involved in and is separate from the balance within accounts
    // user => token address => balance of that token that is held in vault ready
    mapping(address => mapping(address => uint)) public pulls;

    // Keep track of all our $$$
    // Note that this is only update when tokens come in or out. No change
    // when we move balances from accounts to pulls
    mapping (address => uint) public money;

    // Transfer tokens from user to us
    function take(address gem, address src, uint amt) external onlyChief returns (bool) {
        require(proxy.deal(gem, src, address(this), amt), "ccm-vault-take-deal-failed");

        money[gem] = add(money[gem], amt);

        rich(gem);

        return true;
    }

    // Transfer tokens from us to user
    function give(address _gem, address dst, uint amt) external onlyChief returns (bool) {
        // This is also asserted by line below, but leaving extra check in here for now
        require(pulls[dst][_gem] >= amt, "ccm-vault-give-insufficient-balance");

        pulls[dst][_gem] = sub(pulls[dst][_gem], amt);
        
        money[_gem] = sub(money[_gem], amt);

        IERC20 gem = IERC20(_gem);
        // NOTE: this is pull only - i.e. this will only be called from Chief.pull()
        require(gem.transfer(dst, amt), "ccm-vault-give-transfer-failed");

        // Make sure we're still rich $$
        rich(_gem);

        return true;
    }

    // TODO: change return value if not being used
    // Add to user's pull balance
    function gift(address gem, address lad, uint amt) external onlyChief returns (uint) {
        pulls[lad][gem] = add(pulls[lad][gem], amt);
        return pulls[lad][gem];
    }

    // Verify that nothing has gone crazy
    function rich(address gem) private view {
        // If this is false, we have big problems
        assert(IERC20(gem).balanceOf(address(this)) >= money[gem]);
    }

    ///////////
    // Owner Functions
    ///////////

    // Vault has to be deployed before Chief and Proxy, so no constructor
    // Use this to set other contract addresses
    function init(address _chief, address _proxy) external onlyOwner {
        // Prevent owner from changing chief address
        require(chief == address(0), "ccm-vault-init-no-new-chief");
        chief = _chief; 
        proxy = Proxy(_proxy);
    }

}