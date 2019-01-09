pragma solidity 0.4.24;

// import "./openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../lib/Interest.sol";
// import "./openzeppelin-solidity/contracts/ownership/Ownable.sol";

// CCM - contract-collateral-manager
contract Manager is Interest {

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
        // TODO: need to track due balance
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

        uint dueBalance; // TODO
        uint era;       // Time of last interest accrual
    }

    // uint min_tab;   // tab below which it's not profitable for keepers to bite?
    uint public max_tax;    // maximum interest rate
    uint public max_tab;    // tab above which keepers can bite TODO: change name of this if tab is not updated with interest
    uint public accti;      // Incremented for keepers to find accounts
    
    mapping (address => mapping(address => TradingPair)) public pairs;  // due => gem => TradingPair
    mapping (address => Mama) public mamas; // Contract-wide GemParams
    mapping (bytes32 => Acct) public accts;  // keccak256(who, user) => Account
    mapping (uint => bytes32) public radar;     // accti => accts key for the acct
    

    // TODO - how to keep track of everyone's balances in multiple tokens
    // without a potentially unbounded iteration? - see how spankchain or raiden does this
    // Maybe we don't, just make them call pull(tokenAddress) and use events whenever
    // a balance is added to pull
    mapping(address => mapping(address => uint)) pulls; // withdraw balances


    // called by the managing contract
    // if _mom == true, _due should be 0
    function _open(
        uint    _tab,   // Collateral amount, denominated in _due token
        address _lad,   // Address of the payer TODO: can't be msg.sender?
        address _due,   // Address of the token to pay out in
        bool    _mom    // If true, use contract-wide GemParams. else, set below
    ) internal returns (bool) {
        // Account user can't be zero
        require(_lad != address(0), "collateral-vault-open-lad-address-invalid");
        
        // Payout token can't be 0 unless mama params being used. 
        // NOTE: No checks on whether _due has any token matches
        // if _mom, check contract-wide due address, else check _due
        if (_mom) {
            require(mamas[msg.sender].due != address(0), "collateral-vault-open-mama-due-invalid");
        } else {
            require(_due != address(0), "collateral-vault-open-due-invalid");
        }

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
        // _grab

        return true;       
    }

    function _ngem(
        uint    _tax,   // interest rate charged on swapped collateral   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem,   // address of the token to add
        address _lad,   // address of the holder / payer
        bool    _mom    // set this to contract-wide params?
    ) internal returns (bool) {
        // do all the checks
        // if mom grab from mom else grab from baby
        // do last check and set

        // TODO: make sure we don't need a minimum for axe
        // liquidation penalty > 1 required to prevent auction grinding
        require(_axe > RAY, "collateral-vault-mama-axe-invalid");
        // extra collateral has to be able to at least cover axe
        require(_mat > _axe, "ccm-manager-mama-mat-invalid");
        // Check that tax is valid
        require(_tax < max_tax, "ccm-manager-mama-tax-invalid");

        // TODO: probably don't need these, checking pairs
        // require(mama.due != address(0), "collateral-vault-mama-due-not-set");
        // require(_gem != address(0), "collateral-vault-mama-address-invalid");

        bytes32 key;
        address _due;
        GemParams memory ngem;
        // mama or account?
        if (_mom) { 
            _due = mamas[msg.sender].due;
            ngem = mamas[msg.sender].gems[_gem]; 
        } else {
             // Check that account exists 
            key = keccak256(abi.encodePacked(msg.sender, _lad));
            require(accts[key].era > 0, "collateral-vault-baby-account-doesnt-exist");
            _due = accts[key].due;
            ngem = accts[key].gems[_gem];
        }

        // gem must be an approved token pair with due
        require(pairs[_due][_gem].use, "collateral-vault-mama-token-pair-invalid");

        // TODO: mama.mat>0 very important, prevents editing gem params
        // after setting use to false. Make sure there's no way around this
        // Also, does just checking mat work?
        // require(!mama.use && mama.mat > 0, "collateral-vault-mama-gem-in-use");
        require(ngem.mat > 0, "collateral-vault-mama-gem-in-use");

        ngem.use = true;
        ngem.tax = _tax;
        ngem.mat = _mat;
        ngem.axe = _axe;

        if(_mom) {mamas[msg.sender].gems[_gem] = ngem;}
        else {accts[key].gems[_gem] = ngem;}

        return true; 
    }

    // State altering functions
    ////// Managing Contract Functions:
    // open()       - implemented
    // mdue()   - add initial due to mamas, born, girl?, mama
    //    - add initial due to specific acct, -- Not needed, can't be initialized w/o one
    // mama()   - add a GemParam to mamas, mgem, 
    // baby()   - add a GemParam to specific acct, daut, bgem
    // dump()   - disable a gem in mama for future users - could also use mama/daut(false) to remove, mpop
    // bump()   - disable a gem for specific acct as long as not currently held, bump, bpop  ** make these be able to toggle use
    // take()   - pay out to specified address, send-probs confusing, post, drop, give, move, take
    // close()?  - set tab = 0, either leave user balance or transfer it to pull() balances
    //
    ////// User Functions:
    // lock()   - add either gem or due tokens, as long as it stays safe
    // free()   - claim either gem or due tokens, as long as it stays safe
    //          - set, change, or remove jet, zoom, tend, plane, edit, lift, land
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


    /////////////
    // External Functions
    ////////////

    // Set the contract-wide due token
    function mdue(address _due) external returns (bool) {
        // _due can't be zero
        require(_due != address(0), "collateral-vault-mama-due-token-invalid");
        // can't change due token
        require(mamas[msg.sender].due == address(0), "collateral-vault-mama-due-already-set");
        // set due
        mamas[msg.sender].due = _due;
    } 

    // add a GemParam to mamas
    function mama(
        uint    _tax,   // interest rate charged on tab - .....   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem    // address of the token to add
    ) external returns (bool) {
        return _ngem(_tax, _mat, _axe, _gem, address(0), true);        
    }
    // Add a GemParam to a specific account
    function baby(
        uint    _tax,   // interest rate charged on swapped collateral   
        uint    _mat,   // minimum collateralization ratio, as a ray
        uint    _axe,   // liquidation penalty, as a ray
        address _gem,   // address of the token to add
        address _lad    // address of the holder / payer
    ) external returns (bool) {
        return _ngem(_tax, _mat, _axe, _gem, _lad, false);
    }
    // Open an account
    function open(
        uint    _tab,   // Collateral amount, denominated in _due token
        address _lad,   // Address of the payer TODO: can't be msg.sender?
        address _due,   // Address of the token to pay out in
        bool    _mom    // If true, use contract-wide GemParams. else, set below
    ) external returns (bool) {
        return _open(_tab, _lad, _due, _mom);
    }
    // Open an account that will use mama params
    function open(uint _tab, address _lad) external returns (bool) {
        return _open(_tab, _lad, address(0), false);
    }

    
    /////////////
    // Getters
    /////////////
    


}