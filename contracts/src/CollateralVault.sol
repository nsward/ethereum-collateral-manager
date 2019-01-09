pragma solidity ^0.4.24;

import "./openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../lib/Interest.sol";
// import "./openzeppelin-solidity/contracts/ownership/Ownable.sol";

// CCM - contract-collateral-manager
contract CollateralVault is Interest {

    struct Order {
        // TODO
        uint amt;
    }
    // trade, 
    struct TradingPair {
        // TODO
        bool use;
    }
    // Asset class
    struct GemParams {
        bool use;
        uint tax;
        uint mat;   // Minimum Collateralization Ratio
        uint axe;   // liquidation penalty
    }
    struct Mama {
        address due;
        mapping (address => GemParams) gems;
    }
    struct Acct {
        // Set by managing contract
        address who;    // Address of managing contract, man, 
        address due;    // Address of the ERC20 token to pay out in
        uint tab;       // Max payout amt 
        mapping (address => GemParams) gems;    // Tokens that can be held as collateral and the parameters
        bool mom;    // true ? use local gems : use mamas[who]. ** make sure mamas[mom].axe valid (> 1)?
        
        // Set by user
        mapping (address => bool) pals; // Approved to handle trader's account
        bool opt;       // opt-in to dutch auction? auc
        address gem;    // Token currently held (can be in addition to due balance)
        uint bal;       // gem balance
        Order jet;      // Default order to take if called for payment.

        uint era;       // Time of last interest accrual
    }

    // uint min_tab;   // tab below which it's not profitable for keepers to bite?
    uint public max_tax;    // maximum interest rate
    uint public max_tab;    // tab above which keepers can bite TODO: change name of this if tab is not updated with interest
    uint public accti;      // Incremented for keepers to find accounts
    
    mapping (address => mapping(address => TradingPair)) public pairs;  // due => gem => TradingPair
    mapping (address => mapping(address => Mama)) public mamas; // Contract-wide GemParams
    mapping (bytes32 => Acct) public accts;  // keccak256(who, user) => Account
    mapping (uint => bytes32) public radar;     // accti => accts key for the acct
    

    // TODO - how to keep track of everyone's balances in multiple tokens
    // without a potentially unbounded iteration? - see how spankchain or raiden does this
    // Maybe we don't, just make them call pull(tokenAddress) and use events whenever
    // a balance is added to pull
    mapping(address => mapping(address => uint)) pulls; // withdraw balances
    
    // TODO: we can't open without a transfer of due, so we need to have due from somewhere
    // called by the managing contract
    // if _mom == true, _due should be 0
    function open(
        bool _mom,      // If true, use contract-wide GemParams. else, set below
        address _lad,   // Address of the payer TODO: can't be msg.sender?
        address _due,   // Address of the token to pay out in
        uint _tab       // Collateral amount, denominated in _due token
    ) public returns (bool) {
        // Account user can't be zero
        require(_lad != address(0), "collateral-vault-open-lad-address-invalid");
        // Payout token can't be 0 unless mama params being used. 
        // NOTE: No checks on whether _due has any token matches
        if (!_mom) {require(_due != address(0), "collateral-vault-open-due-token-invalid");}
        // Check that owed amt under limit
        require(_tab > 0 && _tab < max_tab, "collateral-vault-open-tab-invalid");
        // Grab the account
        bytes32 key = keccak256(abi.encodePacked(msg.sender, _lad));
        Acct storage acct = accts[key];
        // Check that account doesn't exist already. TODO: check who too?
        require(acct.era == 0, "collateral-vault-open-account-exists");
        // Add id to radar and increment accti
        radar[accti] = key;
        accti = add(accti, 1); 
        // Initialize the account
        acct.who = msg.sender;
        acct.tab = _tab;
        acct.mom = _mom;
        acct.era = now;
        if (!_mom) {acct.due = _due;}    // TODO: just set this anyway?

        // **************
        // TODO: instantiate _due as an ERC20
        // TODO: transfer _tab of _due from _lad to us

        return true;       
    }

    // TODO: can be used to edit?
    // add a GemParam to mamas
    function _mama(
        address _due,   // address of the token to settle in
        address _gem,   // address of the token to add
        uint _tax,      // interest rate charged on swapped collateral   
        uint _mat,      // minimum collateralization ratio, as a ray
        uint _axe       // liquidation penalty, as a ray
    ) internal returns (bool) {
        // If due set, it cannot be changed
        // if gem set, you can only change use which is == deleting?

        // 3 things we would want to do:
            // - initialize with new due [and new gem]
            // - add gem
            // - change gem to use = false
        
        Mama storage mama = mamas[msg.sender];

        if (mama.due == address(0)) {
            // brand new stuff
            // if gem == 0, just change due
            // return true
        } 

        if (mama.gems[_gem].use) {
            // can only change use
            // return true?
        }

        // Else, same due but new mama

        // TODO: make sure we don't need a minimum for axe
        // liquidation penalty > 1 required to prevent auction grinding
        require(_axe > RAY, "collateral-vault-mama-axe-invalid");

        // extra collateral has to be able to at least cover axe
        require(_mat > _axe, "collateral-vault-mama-mat-invalid");
        // Check that tax is valid
        require(_tax < max_tax, "collateral-vault-mama-tax-invalid");
        
        // due can't be zero
        require(_due != address(0), "collateral-vault-mama-due-invalid");
        // TODO: probably don't need this
        // Gem can't be zero
        // require(_gem != address(0), "collateral-vault-mama-address-invalid");

        // gem must be an approved token pair with due
        require(pairs[_due][_gem].use, "collateral-vault-mama-token-pair-invalid");

        


    }

    // version called 
    function mama(
        address _gem,   // address of the token to add
        uint _tax,      // interest rate charged on swapped collateral   
        uint _mat,      // minimum collateralization ratio, as a ray
        uint _axe       // liquidation penalty, as a ray
    ) public returns (bool) {
    
    // State altering functions
    ////// Managing Contract Functions:
    // open()       - implemented
    // mama()   - add a GemParam to mamas
    // daut()   - add a GemParam to specific acct, daut
    // dump()   - disable a gem in mama for future users - could also use mama/daut(false) to remove
    // bump()   - disable a gem for specific acct as long as not currently held, bump
    // take()   - pay out to specified address, send-probs confusing, post, drop, give, move, take
    // close()  - set tab = 0, either leave user balance or transfer it to pull() balances
    //
    ////// User Functions:
    // lock()   - add either gem or due tokens, as long as it stays safe
    // free()   - claim either gem or due tokens, as long as it stays safe
    //          - set, change, or remove jet, zoom, tend, plane, edit
    // meet()   - approve/unapprove a pal, talk, 
    //          - opt in/out of dutch auction, care, tend, 
    // swap()   - use 0x order to trade due or gem for new gem, as long as it stays safe. Also, delete jet
    //          
    //
    ////// Keeper Functions:
    // accti()      - implemented
    // bite()
    //
    ////// Payed address functions:
    // pull()   - Claim balance, or claim()
    //
    ////// Auction Functions:
    //
    ////// Intermediate Functions:
    // safe()


}