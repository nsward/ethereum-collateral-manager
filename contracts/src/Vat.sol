pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;

import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";

contract Vat is AuthAndOwnable {

    using SafeMath for uint;

    struct AssetClass {
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray, temporarily doubles as discount for collateral
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
        uint    callEnd;        // end of current callTime. 0 if not called
        uint    callTime;       // time allowed for a call
        uint    owedTab;        // max payout amt
        uint    owedBal;        // balance of owedGem currently held, denominated in owedGem
        uint    heldBal;        // balance of heldGem currently held, denominated in heldGem
        address heldGem;        // trading token currently held
        address admin;          // admin of the account
        address user;           // user of the account
        bytes32 paramsKey;      // hash(admin, user) or hash(admin). Used to get owedGem and asset params
    }

    // account key  = keccak256(admin, user)
    // params key   = keccak256(admin, user) for account-specific params
    //            or  keccak256(admin)) for admin-wide params

    mapping (bytes32 => uint)       public claims;      // keccak256(user, token) => claimable balance

    mapping (bytes32 => Account)    public accounts;    // keccak256(admin, user) => Account
    mapping (bytes32 => Order)      public safeOrders;  // keccak256(admin, user) => order
    mapping (bytes32 => uint)       public noFills;     // for used safe orders
    mapping (bytes32 => address)    public owedGems;    // paramsKey => token

    mapping (bytes32 => mapping(address => uint))   public agents;      // acctKey => agent => approval
    mapping (bytes32 => mapping(address => uint))   public allowances;  // acctKey => token => allowance
    mapping (bytes32 => mapping(address => AssetClass))  public assets;      // paramsKey => token => Asset

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
            if (which == "callEnd")     got = bytes32(accounts[key].callEnd);
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
    }
    function get(bytes32 what, bytes32 which, bytes32 key, address addr) external view returns (bytes32 got) {
        if (what == "asset") {
            if (which == "use") got = bytes32(assets[key][addr].use);
            if (which == "tax")         got = bytes32(assets[key][addr].tax);
            if (which == "biteLimit")   got = bytes32(assets[key][addr].biteLimit);
            if (which == "biteFee")     got = bytes32(assets[key][addr].biteFee);
        }
    }

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
    }
    function subFrom(bytes32 what, bytes32 key, uint amt) external auth {
        if (what == "claim") claims[key] = claims[key].sub(amt);
    }
    function addTo(bytes32 what, bytes32 key, address addr, uint amt) external auth {
        if (what == "allowance") allowances[key][addr] = allowances[key][addr].add(amt);
    }
    function subFrom(bytes32 what, bytes32 key, address addr, uint amt) external auth {
        if (what == "allowance") allowances[key][addr] = allowances[key][addr].sub(amt);
    }

    // set() provides a standard method to set any value, although some are excluded
    // intentionally becuse they can not be set after being initialized
    // example call to set:
    // vat.set("account", "owedTab", acctKey, newOwedTab)
    function set(bytes32 what, bytes32 key, address data) external auth {
        if (what == "owedGem") owedGems[key] = data;
    }
    function set(bytes32 what, bytes32 key, address addr, uint data) external auth {
        if (what == "allowance")    allowances[key][addr] = data;
        if (what == "agent")        agents[key][addr] = data;
    }
    function set(bytes32 what, bytes32 key, uint data) external auth {
        if (what == "noFill")           noFills[key] = data;
    }
    function set(bytes32 what, bytes32 which, bytes32 key, uint data) external auth {
        if (what == "account") {
            if (which == "callTab")     accounts[key].callTab = data;
            if (which == "owedTab")     accounts[key].owedTab = data;
            if (which == "owedBal")     accounts[key].owedBal = data;
            if (which == "heldBal")     accounts[key].heldBal = data;
            if (which == "callEnd")     accounts[key].callEnd = data;
            if (which == "callTime")    accounts[key].callTime = data;
            if (which == "lastAccrual") accounts[key].lastAccrual = data;
        }
    }
    function set(bytes32 what, bytes32 which, bytes32 key, bytes32 data) external auth {
        if (what == "account" && which == "paramsKey") accounts[key].paramsKey = data;
    }
    function set(bytes32 what, bytes32 which, bytes32 key, address data) external auth {
        if (what == "account") {
            if (which == "heldGem") accounts[key].heldGem = data;
            if (which == "admin")   accounts[key].admin = data;
            if (which == "user")    accounts[key].user = data;
        }
    }

    /// Batch setters

    function set(bytes32 what, bytes32 key, address gem, AssetClass memory _asset) public auth { // TODO: calldata?
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

    function safeSetPosition(bytes32 acctKey, address heldGem, uint heldBal) external auth {
        Account storage acct = accounts[acctKey];
        require(acct.heldBal == 0, "ccm-vat-safeSetPosition-position-exists");
        acct.heldGem = heldGem;
        acct.heldBal = heldBal;
    }

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

    function safeSetAsset(bytes32 paramsKey, address gem, AssetClass memory _asset) public auth {         // TODO: calldata?
        require(assets[paramsKey][gem].biteLimit == 0, "ccm-vat-safeSetAsset-asset-exists");
        assets[paramsKey][gem] = _asset;
    }

    function doOpen(bytes32 acctKey, Account memory acct) public auth returns (bool) {   // TODO: calldata?
        require(accounts[acctKey].lastAccrual == 0, "ccm-vat-doOpen-account-exists");
        address owedGem = owedGems[acct.paramsKey];
        allowances[acctKey][owedGem] = allowances[acctKey][owedGem].sub(acct.owedTab);
        accounts[acctKey] = acct;

        return true;
    }

    function updateTab(bytes32 key) public auth returns (uint) {
        Account storage acct = accounts[key];

        // no time passed since last update
        if (acct.lastAccrual == now) { return acct.owedTab; }

        acct.lastAccrual = now;

        // no tax accrued
        if (acct.owedBal >= acct.owedTab) {  return acct.owedTab; }
        
        // get tax for the trade token
        uint tax = assets[acct.paramsKey][acct.heldGem].tax;

        acct.owedTab = MathTools.getInterest(
            acct.owedTab.sub(acct.owedBal),
            tax,
            now.sub(acct.lastAccrual)
        ).add(acct.owedTab);

        return acct.owedTab;
    }

    function doCall(bytes32 acctKey, uint callTab) external auth returns (uint) {
        updateTab(acctKey);
        Account storage acct = accounts[acctKey];
        // require(acct.admin == caller, "ccm-vat-doCall-not-admin");   // checked by acctKey
        require(callTab <= acct.owedTab, "ccm-vat-doCall-callTab-invalid");
        acct.callTab = callTab;
        uint callEnd = acct.callTime.add(now);
        acct.callEnd = callEnd;
        return callEnd;
    }

    function isUserOrAgent(bytes32 acctKey, address guy) public view returns (bool) {
        return (guy == accounts[acctKey].user || agents[acctKey][guy] == 1);
    }

}