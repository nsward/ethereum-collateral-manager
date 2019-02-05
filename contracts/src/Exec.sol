pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./interfaces/VaultLike.sol";
import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";

contract VatLike {
    enum State{ Par, Call, Bit, Old }
    struct Asset {
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray, temporarily doubles as discount for collateral
        uint use;       // approved for use (0 = no, 1 = yes)
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
    function owedGems(bytes32) public view returns (address);
    function set(bytes32, bytes32, address) external;
    function set(bytes32, bytes32, bytes32, address, uint) external;
    function set(bytes32, bytes32, uint) external;
    function doOpen(bytes32, Account memory) public returns (address);    // TODO: calldata??
    function safeSetOwedGem(bytes32, address) external;
    function safeSetAsset(bytes32, address, Asset memory) public;                  // tODO calldata structs?
    function owedGemByAccount(bytes32) external view returns (address, bytes32);
}

contract Exec is Ownable {

    uint constant RAY = 10 ** 27;
    mapping (bytes32 => uint) public validTokenPairs;   // keccak256(dueToken, tradeToken) => use

    VatLike     public vat;
    VaultLike   public vault;

    constructor(address _vat, address _vault) public {
        vat = VatLike(_vat);
        vault = VaultLike(_vault);
    }

    function open(
        uint owedTab,
        uint callTime,
        address user,
        address owedGem,
        bool useAdminParams
    )
        external returns (bool)
    {
        return _open(owedTab, callTime, user, owedGem, useAdminParams);
    }

    // Assume use Exec Params
    function open(
        uint owedTab,
        uint callTime,
        address user
    )
        external returns (bool)
    {
        return _open(owedTab, callTime, user, address(0), true);
    }


    // called by the managing contract
    // if _mom == true, _due should be 0
    function _open(
        uint256 owedTab,         // collateral amt, denominated in dueToken
        uint256 callTime,       // time allowed after a call
        address user,           // address of the payer TODO: can't be msg.sender?
        address owedGemGiven,       // address of the token to pay out in
        bool useAdminParams
    ) 
        private returns (bool) 
    {
        // Account user can't be zero
        require(user != address(0), "ccm-exec-open-lad-invalid");

        // Get owed gem and check that it's not 0
        address owedGem;
        bytes32 paramsKey;
        if (useAdminParams) {
            paramsKey = MathTools.k256(msg.sender);
            owedGem = vat.owedGems(paramsKey);
        } else {
            paramsKey = MathTools.k256(msg.sender, user);
            owedGem = owedGemGiven;
            vat.set("owedGem", paramsKey, owedGem);
        }
        require(owedGem != address(0), "ccm-exec-open-no-owedGem");

        // get account key
        bytes32 acctKey = MathTools.k256(msg.sender, user);
        
        // initialize the account
        VatLike.Account memory acct;
        acct.admin = msg.sender;
        acct.owedTab = owedTab;
        acct.owedBal = owedTab;
        acct.callTime = callTime;
        acct.paramsKey = paramsKey;
        acct.lastAccrual = now;

        // TODO: reentrancy here if bad ERC20? balance added before transfer successful

        require(vault.take(owedGem, user, owedTab), "ccm-exec-open-take-failed");
        
        assert(vat.doOpen(acctKey, acct) == owedGem);   // TODO: remove this assert?

        return true;       
    }

    function setAdminOwedToken(address owedToken) external returns (bool) {
        // can't be 0
        require(owedToken != address(0), "ccm-exec-setAdminOwedToken-owedToken-invalid");
        bytes32 paramsKey = MathTools.k256(msg.sender);
        // verifies that current owedToken is uninitialized, then sets it
        vat.safeSetOwedGem(paramsKey, owedToken);
        return true;
    }

    function addAsset(uint tax, uint biteLimit, uint biteFee, address gem, address user) external returns (bool) {
        // liquidation penalty must be at least 1
        require(biteFee >= RAY, "ccm-exec-ngem-axe-invalid");
        // extra collateral has to be able to at least cover penalty
        require(biteLimit > biteFee, "ccm-exec-ngem-mat-invalid");
        // RAY is equivalent to no tax
        require(tax > RAY, "ccm-exec-addAsset-tax-invalid");

        bytes32 acctKey = MathTools.k256(msg.sender, user);

        (address owedGem, bytes32 paramsKey) = vat.owedGemByAccount(acctKey);
        require(paramsKey != bytes32(0));
        
        // must be approved token pair
        bytes32 pairKey = MathTools.k256(owedGem, gem);
        require(validTokenPairs[pairKey] == 1);

        VatLike.Asset memory asset;
        asset.use = 1;
        asset.tax = tax;
        asset.biteFee = biteFee;
        asset.biteLimit = biteLimit;

        vat.safeSetAsset(paramsKey, gem, asset);
        
        return true;
    }

    function toggleAsset(bytes32 acctKey, address gem, bool use) external returns (bool) {
        vat.set("asset", "use", acctKey, gem, use ? 1 : 0);
        return true;
    }


    // --- Administration ---
    function file(bytes32 what, address data) external onlyOwner {
        if (what == "vat") vat = VatLike(data);
        if (what == "vault") vault = VaultLike(data);
    }
    function file(bytes32 what, bytes32 key, uint data) external onlyOwner {
        if (what == "validTokenPair") validTokenPairs[key] = data;
    }


    // address owedGem;
    //     if (useAdminParams) {
    //         owedGem = vat.doOpenWithAdminOwedGem(accountKey, paramsKey, account);
    //     } else {
    //         owedGem = owedGemGiven;
    //         vat.doOpenWithNewOwedGem(acctKey, paramsKey, owedGem, acct);
    //     }
    // // called by the managing contract
    // // if _mom == true, _due should be 0
    // function _openWithAllCallsToTheVatContracct(
    //     uint256 owedTab,         // collateral amt, denominated in dueToken
    //     uint256 callTime,       // time allowed after a call
    //     address user,           // address of the payer TODO: can't be msg.sender?
    //     address owedGemGiven,       // address of the token to pay out in
    //     bool useAdminParams
    // ) 
    //     private returns (bool) 
    // {
    //     // Account user can't be zero
    //     require(user != address(0), "ccm-chief-open-lad-invalid");

    //     // Get owed gem and check that it's not 0? -- does this matter?
    //     // bc vault.take will fail from address 0 anyway
    //     address owedGem;
    //     bytes32 paramsKey;
    //     if (useAdminParams) {
    //         paramsKey = MathTools.k256(msg.sender);
    //         owedGem = vat.owedGems(paramsKey);
    //     } else {
    //         paramsKey = MathTools.k256(msg.sender, user);
    //         owedGem = owedGemGiven;
    //         vat.set("owedGem", paramsKey, owedGem);
    //     }
    //     require(owedGem != address(0), "ccm-exec-open-no-owedGem");


    //     // Check that account doesn't exist already. TODO: check who too?
    //     bytes32 accountKey = MathTools.k256(msg.sender, user);
    //     require(
    //         uint(vat.get("account", "lastAccrual", acctKey)) == 0,
    //         "ccm-exec-open-account-exists"
    //     );

    //     VatLike.Account memory account;
    //     account.admin = msg.sender;
    //     account.owedTab = owedTab;
    //     account.owedBal = owedTab;
    //     account.callTime = callTime;
    //     account.paramsKey = paramsKey;
    //     account.lastAccrual = now;

    //     // TODO: check this in the vault? Also, don;t need to check. asserted below via SafeMath
    //     // Check that exec contract is allowed to take funds from user
    //     uint allowance = vat.allowances(accountKey, owedGem);
    //     // require(allowance >= owedTab, "ccm-exec-open-insufficient-allowance");

    //     // TODO: do this in vault?
    //     vat.set("allowance", accountKey, allowance.sub(owedTab));

    //     // Vat calls
    //     // reads: (maybe)owedGem, lastAccrual / acct empty, allowance
    //     // writes: (maybe)owedGem, allowance, Account
    

    //     require(vault.take(owedGem, user, owedTab), "ccm-exec-open-take-failed");
        

    //     return true;       
    // }
}