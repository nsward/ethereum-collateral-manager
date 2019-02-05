pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;

// import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";

contract Vat is AuthAndOwnable {

    // constructor(address foo) AuthAndOwnable(foo) public {}

    using SafeMath for uint;

    // Could just have a called bool? or even calltime == 0?
    enum State{ Par, Call, Bit, Old }

    struct Asset {
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray, temporarily doubles as discount for collateral
        // bool use;       // approved for use  // TODO
        uint use;       // approved for use (0 = no, 1 = yes)
    }
    struct Order {
        uint    makerAmt;
        uint    takerAmt;
        uint    fillAmt;
        address wrapper;
        address exchange;
        address makerGem;
        address takerGem;
        bytes   orderData;
    }
    struct Account {
        uint    lastAccrual;    // time of last interest accrual
        uint    callTab;        // tab due at end of call
        uint    callTime;       // time allowed for a call
        uint    owedTab;        // max payout amt
        uint    owedBal;        // balance of owedGem currently held, denominated in owedGem
        uint    heldBal;        // balance of heldGem currently held, denominated in heldGem
        bytes32 paramsKey;      // hash(admin, user) or hash(admin). Used to get owedGem and asset params
        address heldGem;        // trading token currently held
        address admin;          // admin of the account
        address user;           // user of the account
        State   state;
    }

    // account key -> keccak256(admin, user)
    // params key -> either keccak256(admin, user) or keccak256(admin)

    // TODO: make sure we're emitting sufficient events for users to find these
    // for claim(). Note that this is the net payouts from all accounts user/contract 
    // is involved in and is separate from the balance within accounts
    // user => token address => balance of that token that is held in vault
    // keccak256(user, token) => balance of that token that is held in vault
    mapping(bytes32 => uint) public claims;

    mapping (bytes32 => Account)    public accounts;    // keccak256(admin, user) => Account
    mapping (bytes32 => Order)      public safeOrders;  // keccak256(admin, user) => order
    mapping (bytes32 => uint)       public noFills;     // for used safe orders
    mapping (bytes32 => address)    public owedGems;    // paramsKey => token

    mapping (bytes32 => mapping(address => uint)) public agents;    // accountKey => agent => approval
    mapping (bytes32 => mapping(address => uint)) public allowances;// accountKey => token => allowance
    mapping (bytes32 => mapping(address => Asset)) public assets;  // paramKey => token => Asset

    //////////
    // Getters
    //////////

    // get() provides a standard method to get any struct value without copying the entire struct
    // example calls:
    // uint owedTab = uint(vat.get("account", "owedTab", acctKey))   
    // address user = address(bytes20(vat.get("account", "user", acctKey)))
    function get(bytes32 what, bytes32 which, bytes32 key) external view returns (bytes32 got) {
        if (what == "account") {
            if (which == "paramsKey")   got = accounts[key].paramsKey;
            if (which == "lastAccrual") got = bytes32(accounts[key].lastAccrual);
            if (which == "callTab")     got = bytes32(accounts[key].callTab);
            if (which == "callTime")    got = bytes32(accounts[key].callTime);
            if (which == "owedTab")     got = bytes32(accounts[key].owedTab);
            if (which == "owedBal")     got = bytes32(accounts[key].owedBal);
            if (which == "heldBal")     got = bytes32(accounts[key].heldBal);
            if (which == "heldGem")     got = bytes32(bytes20(accounts[key].heldGem));
            if (which == "admin")       got = bytes32(bytes20(accounts[key].admin));
            if (which == "user")        got = bytes32(bytes20(accounts[key].user));
        }
        if (what == "safeOrder") {
            if (which == "makerAmt")    got = bytes32(safeOrders[key].makerAmt);
            if (which == "takerAmt")    got = bytes32(safeOrders[key].takerAmt);
            if (which == "fillAmt")     got = bytes32(safeOrders[key].fillAmt);
            if (which == "wrapper")     got = bytes32(bytes20(safeOrders[key].wrapper));
            if (which == "exchange")    got = bytes32(bytes20(safeOrders[key].exchange));
            if (which == "makerGem")    got = bytes32(bytes20(safeOrders[key].makerGem));
            if (which == "takerGem")    got = bytes32(bytes20(safeOrders[key].takerGem));
        }
        // if (what == "asset") {
        //     if (which == "use")         got == bytes32(assets[key].use);
        //     if (which == "tax")         got == bytes32(assets[key].tax);
        //     if (which == "biteLimit")   got == bytes32(assets[key].biteLimit);
        //     if (which == "biteFee")     got == bytes32(assets[key].biteFee);
        //     // if (which == "biteGap")     got == bytes32(assets[key].biteGap);
        // }
    }
    function get(bytes32 what, bytes32 which, bytes32 key, address addr) external view returns (bytes32 got) {
        if (what == "asset") {
            if (which == "use") got = bytes32(assets[key][addr].use);
            if (which == "tax")         got == bytes32(assets[key][addr].tax);
            if (which == "biteLimit")   got == bytes32(assets[key][addr].biteLimit);
            if (which == "biteFee")     got == bytes32(assets[key][addr].biteFee);
            // if (which == "biteGap")     got == bytes32(assets[key].biteGap);
        }
    }

    function getOrderData(bytes32 key) external view returns (bytes memory) {
        return safeOrders[key].orderData;
    }

    /// Batched Getters


    //////////
    // Getters
    /////////

    // set() provides a standard method to set any value, although some are excluded
    // intentionally becuse they can only be set once via setNew()
    // example call to set:
    // vat.set("account", "owedTab", acctKey, newOwedTab)
    function set(bytes32 what, bytes32 key, address data) external auth {
        if (what == "owedGem") owedGems[key] = data;
    }
    function set(bytes32 what, bytes32 key, address addr, uint data) external auth {
        if (what == "allowance") allowances[key][addr] = data;
        if (what == "agent") agents[key][addr] = data;
    }
    function set(bytes32 what, bytes32 key, uint data) external auth {
        // if (what == "agent") agents[key] = data;
        if (what == "noFill") noFills[key] = data;
    }

    // tODO
    function addTo(bytes32 what, bytes32 which, bytes32 key, uint amt) external auth {
        if (what == "account") {
            if (which == "owedBal") accounts[key].owedBal = accounts[key].owedBal.add(amt);
            if (which == "heldBal") accounts[key].heldBal = accounts[key].heldBal.add(amt);
            if (which == "owedTab") accounts[key].owedTab = accounts[key].owedTab.add(amt);
        }
    }
    function subFrom(bytes32 what, bytes32 which, bytes32 key, uint amt) external auth {
        if (what == "account") {
            if (which == "owedBal") accounts[key].owedBal = accounts[key].owedBal.sub(amt);
            if (which == "heldBal") accounts[key].heldBal = accounts[key].heldBal.sub(amt);
            if (which == "owedTab") accounts[key].owedTab = accounts[key].owedTab.sub(amt);
        }
    }
    function addTo(bytes32 what, bytes32 key, uint amt) external auth {
        if (what == "claim") claims[key] = claims[key].add(amt);
        // if (what == "allowance") allowances[key] = allowances[key].add(amt);
    }
    function subFrom(bytes32 what, bytes32 key, uint amt) external auth {
        if (what == "claim") claims[key] = claims[key].sub(amt);
        // if (what == "allowance") allowances[key] = allowances[key].sub(amt);
    }

    function set(bytes32 what, bytes32 which, bytes32 key, uint data) external auth {
        if (what == "account") {
            if (which == "callTab") accounts[key].callTab = data;
            if (which == "owedTab") accounts[key].owedTab = data;
            if (which == "owedBal") accounts[key].owedBal = data;
            if (which == "heldBal") accounts[key].heldBal = data;

            // TODO: make unsettable?
            if (which == "lastAccrual") accounts[key].lastAccrual = data;
            if (which == "callTime") accounts[key].callTime = data;
        }
        // if (what == "asset" && which == "use") assets[key].use = data;
    }
    function set(bytes32 what, bytes32 which, bytes32 key, bytes32 data) external auth {
        if (what == "account" && which == "paramsKey") accounts[key].paramsKey = data;
    }
    function set(bytes32 what, bytes32 which, bytes32 key, address data) external auth {
        if (what == "account") {
            if (which == "heldGem") accounts[key].heldGem = data;

            // TODO: make unsettable?
            if (which == "admin") accounts[key].admin = data;
            if (which == "user") accounts[key].user = data;
        }
    }

    /// Batch setters

    function set(bytes32 what, bytes32 key, address gem, Asset memory _asset) public auth { // TODO: calldata?
        if (what == "asset") assets[key][gem] = _asset;
    }
    function set(bytes32 what, bytes32 key, Account memory _account) public auth {  // TODO: calldata?
        if (what == "account") accounts[key] = _account;
    }
    function set(bytes32 what, bytes32 key, Order memory _order) public auth {  // TODO: calldata?
        if (what == "safeOrder") safeOrders[key] = _order; 
    }
    function set(bytes32 what, bytes32 which, bytes32 key, address addr, uint data) external auth {
        if (what == "asset" && which == "use") assets[key][addr].use = data;
    }

    // make this addToBals
    function setPosition(bytes32 acctKey, uint owedBal, uint heldBal) external auth {
        setPosition(acctKey, owedBal, heldBal, address(0));
    }
    function setPosition(bytes32 acctKey, uint owedBal, uint heldBal, address heldGem) public auth {
        if (heldGem != address(0)) { accounts[acctKey].heldGem = heldGem; }
        accounts[acctKey].owedBal = owedBal;
        accounts[acctKey].heldBal = heldBal;
    }

    function safeSetPosition(bytes32 acctKey, address heldGem, uint heldBal) external auth {
        Account storage acct = accounts[acctKey];
        require(acct.heldBal == 0, "ccm-vat-safeSetPosition-position-exists");
        acct.heldGem = heldGem;
        acct.heldBal = heldBal;
    }
    // function addOwedBal(bytes32 acctKey, uint amt) external auth {
    //     accounts[acctKey].owedBal = SafeMath.add(accounts[acctKey].owedBal, amt);
    // }
    // function addHeldBal(bytes32 acctKey, uint amt) external auth {
    //     accounts[acctKey].heldBal = SafeMath.add(accounts[acctKey].heldBal, amt);
    // }
    // function subOwedBal(bytes32 acctKey, uint amt) external auth {
    //     accounts[acctKey].owedBal = SafeMath.sub(accounts[acctKey].owedBal, amt);
    // }
    // function subHeldBal(bytes32 acctKey, uint amt) external auth {
    //     accounts[acctKey].heldBal = SafeMath.sub(accounts[acctKey].heldBal, amt);
    // }


    // do not include wrapper or fillAmt in hash, as these could be used 
    // to make the same order return a different hash but still be fillable
    function setSafeOrderAndNoFill(bytes32 key, Order memory _order) public auth {  // TODO: calldata?
        safeOrders[key] = _order;
        noFills[
            keccak256(abi.encodePacked(
                _order.makerGem, 
                _order.takerGem, 
                _order.makerAmt, 
                _order.takerAmt, 
                _order.orderData
            ))
        ] = 1;
    }

    function getSafeArgs(bytes32 acctKey) 
        external 
        view 
        returns (
            address owedGem,
            address heldGem,
            uint    owedBal,
            uint    heldBal,
            uint    owedTab,
            uint    lastAccrual,
            uint    tax,
            uint    biteLimit
        )
    {
        bytes32 paramsKey = accounts[acctKey].paramsKey;
        owedGem = owedGems[paramsKey];
        heldGem = accounts[acctKey].heldGem;
        owedBal = accounts[acctKey].owedBal;
        heldBal = accounts[acctKey].heldBal;
        owedTab = accounts[acctKey].owedTab;
        lastAccrual = accounts[acctKey].lastAccrual;
        tax = assets[paramsKey][heldGem].tax;
        biteLimit = assets[paramsKey][heldGem].biteLimit;
    }

    function safeSetOwedGem(bytes32 paramsKey, address owedToken) external auth {
        require(owedGems[paramsKey] == address(0), "ccm-vat-safeSetOwedToken-owedToken-exists");
        owedGems[paramsKey] = owedToken;
    }

    function owedGemByAccount(bytes32 acctKey) external view returns (address owedGem, bytes32 paramsKey) {
        paramsKey = accounts[acctKey].paramsKey;
        owedGem = owedGems[paramsKey];
    }

    function owedAndHeldGemsByAccount(bytes32 acctKey) external view returns (address owedGem, address heldGem, bytes32 paramsKey) {
        paramsKey = accounts[acctKey].paramsKey;
        heldGem = accounts[acctKey].heldGem;
        owedGem = owedGems[paramsKey];
    }

    function safeSetAsset(bytes32 paramsKey, address gem, Asset memory _asset) public auth {         // TODO: calldata?
        require(assets[paramsKey][gem].biteLimit == 0, "ccm-vat-safeSetAsset-asset-exists");
        assets[paramsKey][gem] = _asset;
    }

    function doOpen(bytes32 acctKey, Account memory acct) public auth returns (address) {   // TODO: calldata?
        require(accounts[acctKey].lastAccrual == 0, "ccm-vat-doOpen-account-exists");
        address owedGem = owedGems[acct.paramsKey];
        allowances[acctKey][owedGem] = allowances[acctKey][owedGem].sub(acct.owedTab);
        accounts[acctKey] = acct;

        return owedGem;
    }

    // function addClaim(bytes32 claimKey, uint amt) external auth {
    //     claims[claimKey] = SafeMath.add(claims[claimKey], amt);
    // }

    // function subClaim(bytes32 claimKey, uint amt) external auth {
    //     claims[claimKey] = SafeMath.sub(claims[claimKey], amt);
    // }

    function updateTab(bytes32 key) external auth returns (uint) {
        Account storage acct = accounts[key];

        // no time passed since last update
        if (acct.lastAccrual == now) { return acct.owedTab; }

        acct.lastAccrual = now;

        // no tax accrued
        if (acct.owedBal >= acct.owedTab) {  return acct.owedTab; }
        
        // get tax for the trade token
        uint tax = assets[acct.paramsKey][acct.heldGem].tax;

        acct.owedTab = MathTools.accrueInterest(
            acct.owedTab.sub(acct.owedBal),
            tax,
            now.sub(acct.lastAccrual)
        );

        return acct.owedTab;
    }
    // function safeSetAllowance(bytes32 acctKey, address guy, address gem, uint allowance) external auth {
    //     require(isUserOrAgent(acctKey, guy), "ccm-vat-safeSetAllowance-unauthorized");
    //     allowances[acctKey][gem] = allowance;
    // }

    function isUserOrAgent(bytes32 acctKey, address guy) public view returns (bool) {
        return (guy == accounts[acctKey].user || agents[acctKey][guy] == 1);
    }




    // // check account empty
    // // check allowance > acct.owedTab
    // // new allowance = allowance - acct.owedTab
    // // store account
    // function doOpenWithAdminOwedGem(
    //     bytes32 acctKey, 
    //     bytes32 paramsKey, 
    //     Account calldata acct
    // )
    //     external auth returns (address) 
    // {
    //     require(accounts[acctKey].lastAccrual == 0, "ccm-vat-doOpen-account-exists");
    //     address owedGem = owedGems[paramsKey];
    //     allowances[key][owedGem] = SafeMath.sub(allowances[key][owedGem], acct.owedTab);
    //     accounts[acctKey] = acct;

    //     return owedGem;
    // }

    // function doOpenWithNewOwedGem(
    //     bytes32 acctKey,
    //     bytes32 paramsKey,
    //     address owedGem,
    //     Account calldata acct
    // )
    //     external auth
    // {
    //     require(accounts[acctKey].lastAccrual == 0, "ccm-vat-doOpen-account-exists");
    //     // TODO:
    //     // require(owedGems[paramsKey] == 0) ?? -- Not unless we're sure we're deleting old owedGems
    //     owedGems[paramsKey] = owedGem;
    //     allowances[key][owedGem] = SafeMath.sub(allowances[key][owedGem], acct.owedTab);
    //     accounts[acctKey] = acct;
    // }


    // function editAccount(bytes32 key, bytes32 which, uint data) external auth {
    //     if (which == "callTab") accounts[key].callTab = data;
    //     if (which == "dueTab") accounts[key].dueTab = data;
    //     if (which == "dueBalance") accounts[key].dueBalance = data;
    //     if (which == "tradeBalance") accounts[key].tradeBalance = data;
    // }

    // function editAccount(bytes32 key, bytes32 which, address data) external auth {
    //     if (which == "tradeToken") accounts[key].tradeToken = data;
    // }

    // struct BrokerAcct {
    //     uint dueBalance;
    //     uint tradeBalance;
    //     uint lastAccrual;
    //     uint allowance;
    //     address user;
    // }

    // struct AdminAcct {
    //     uint callTab;
    //     uint callTime;
    //     uint dueTab;
    //     address admin;
    //     bool useAdminParams;
    // }
    // struct Account {
    //     uint    callTab;        // tab due at end of current call
    //     uint    dueTab;         // max payout amt 
    //     uint    dueBalance;     // balance of due tokens currently held, denominated in due tokens
    //     uint    tradeBalance;   // trading token balance. denominated in the trading token
    //     uint    callTime;       // time given for a call 
    //     uint    lastAccrual;    // Time of last interest accrual
    //     address user;           // address of user / trader / payer
    //     address admin;          // address of managing contract 
    //     address tradeToken;     // trading token currently held
    //     bool    useAdminParams; // use exec-contract-wide paramaters 
    //     State   state;
    //     //uint    allowance;      // must be set by user before open(). Prevents malicious
    //                             // contract from taking token allowances made to this contract
    // }

    // function readAccount(bytes32 key, bytes)

    // function editAccount(bytes32 key, bytes32 which, State calldata data) external auth {
    //     if (which == "state") account[key].state = data;
    // }

    //mapping (bytes32 => Asset)      public assets;      // hash(admin, user, token) or hash(admin, token)
    

    


    //mapping (bytes32 => uint)       public agents;      // keccak256(admin, user, pal)
    //mapping (bytes32 => uint)       public allowances;  // hash(admin, user, token)

    // TODO: set these values
    //uint256 public accountId;               // Incremented for keepers to find accounts
    // TODO: should be able to have a tab below this, but unable to trade due token 
    // for other tokens, bc the only danger of having a small amt in the acct is
    // getting keepers to bite it
    //uint256 public minTab = 0.005 ether;    // not profitable for keepers to bite below this. TODO: this is just based on the dai cdp minimum. Need to determine what this should be
    //uint256 public maxTax = uint(-1);       // maximum interest rate
    //uint256 public maxTab = uint(-1);     // tab above which keepers can bite
    
    
    //mapping (bytes32 => AdminParam) public adminParams;   // Contract-wide Asset Paramaters
    // Only internal bc of compiler complaint about nested structs. Need to create getter
    
    //mapping (uint256 => bytes32) public accountKeys;    // accountId => accountKey

    // 
    // mapping (bytes32 => address) public adminDueTokens; // or address?
    // mapping (bytes32 => address) public accountDueTokens;   // keccak256(admin, user)

    

    

    



    // OR: combine these into one mapping access with two different hashes??
    // mapping (bytes32 => AssetClass) public accountAssets;   // keccak256(admin, user, token)
    // mapping (bytes32 => AssetClass) public adminAssets;     // keccak256(admin, token)

    

    // if one address stored in bytes32, the address is just the first 20 bytes of the variable
    // Should I store 2 different assets mappings?
    // - if admin-wide assets are going to be keccak256(adminAddress, tokenAddress) and
    //   acct-specific assets are going to be address+12 empty bytes, the acct-specific asset
    //   keys are no longer uniformaly distributed over the entire set, but rather uniformly
    //   distributed over the subset of keys with the last 12 bytets empty. Does this increase
    //   the probability of a collision with a hash (admin-wide keys) to a significant degree?

}