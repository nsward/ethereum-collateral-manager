pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;

import "./interfaces/VaultLike.sol";
import "./events/ExecEvents.sol";
import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";

contract VatLike {
    struct AssetClass {
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray, temporarily doubles as discount for collateral
        uint use;       // approved for use (0 = no, 1 = yes)
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
    function owedGems(bytes32) public view returns (address);
    function set(bytes32, bytes32, address) external;
    function set(bytes32, bytes32, bytes32, address, uint) external;
    function set(bytes32, bytes32, uint) external;
    function get(bytes32, bytes32, bytes32) external returns (bytes32);
    function doOpen(bytes32, Account memory) public returns (bool);    // TODO: calldata??
    function doCall(bytes32, uint) external returns (uint);
    function safeSetOwedGem(bytes32, address) external;
    function safeSetAsset(bytes32, address, AssetClass memory) public;                  // tODO calldata structs?
    function owedGemByAccount(bytes32) external view returns (address, bytes32);
    function addTo(bytes32, bytes32, uint) external;
    function subFrom(bytes32, bytes32, bytes32, uint) external;
}

contract Exec is Ownable, ExecEvents {

    uint constant RAY = 10 ** 27;
    mapping (bytes32 => uint) public validTokenPairs;   // keccak256(dueToken, tradeToken) => use

    VatLike     public vat;
    VaultLike   public vault;

    constructor(address _vat, address _vault) public {
        vat = VatLike(_vat);
        vault = VaultLike(_vault);
    }

    function move(address user, address recipient, uint amt) external returns (bool) {
        bytes32 acctKey = MathTools.k256(msg.sender, user);

        // if enough owedGem in acct to cover amt, do transfer. else, call account
        if (uint(vat.get("account", "owedBal", acctKey)) < amt) {
            _call(acctKey, amt);
        }

        vat.subFrom("account", "owedBal", acctKey, amt);
        (address owedGem,) = vat.owedGemByAccount(acctKey);
        
        // require vault.give(owedGem, recipient, amt);
        bytes32 claimKey = MathTools.k256(recipient, owedGem);
        vat.addTo("claim", claimKey, amt);
        return true;
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

    function openWithAdminParams(
        uint owedTab,
        uint callTime,
        address user
    )
        external returns (bool)
    {
        return _open(owedTab, callTime, user, address(0), true);
    }

    function _open(
        uint256 owedTab,        // collateral amt, denominated in dueToken
        uint256 callTime,       // time allowed after a call
        address user,           // address of the payer
        address owedGemGiven,   // address of the token to pay out in
        bool useAdminParams
    ) 
        private returns (bool) 
    {
        // Account user can't be zero
        require(user != address(0), "ecm-exec-open-lad-invalid");

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
        require(owedGem != address(0), "ecm-exec-open-no-owedGem");

        // get account key
        bytes32 acctKey = MathTools.k256(msg.sender, user);
        
        // initialize the account
        VatLike.Account memory acct;
        acct.admin = msg.sender;
        acct.user = user;
        acct.owedTab = owedTab;
        acct.owedBal = owedTab;
        acct.callTime = callTime;
        acct.paramsKey = paramsKey;
        acct.lastAccrual = now;

        require(vault.take(owedGem, user, owedTab), "ecm-exec-open-take-failed");
        
        require(vat.doOpen(acctKey, acct), "ecm-exec-open-doOpen-failed");

        emit Open(msg.sender, user, owedGem, owedTab);
        return true;       
    }

    function setAdminOwedGem(address owedToken) external returns (bool) {
        // can't be 0
        require(owedToken != address(0), "ecm-exec-setAdminOwedToken-owedToken-invalid");
        bytes32 paramsKey = MathTools.k256(msg.sender);
        // verifies that current owedToken is uninitialized, then sets it
        vat.safeSetOwedGem(paramsKey, owedToken);
        return true;
    }

    function addAdminAsset(uint tax, uint biteLimit, uint biteFee, address gem) external returns (bool) {
        return _addAsset(tax, biteLimit, biteFee, gem, address(0));
    }

    function addAccountAsset(uint tax, uint biteLimit, uint biteFee, address gem, address user) external returns (bool) {
        require(user != address(0), "ecm-exec-addAccount-asset-invalid-user");
        return _addAsset(tax, biteLimit, biteFee, gem, user);
    }

    function _addAsset(uint tax, uint biteLimit, uint biteFee, address gem, address user) internal returns (bool) {
        // liquidation penalty must be at least 1 (no penalty)
        require(biteFee >= RAY, "ecm-exec-addAsset-biteFee-invalid");
        // extra collateral has to be able to at least cover penalty
        require(biteLimit >= biteFee, "ecm-exec-addAsset-biteLimit-invalid");
        // RAY is equivalent to no tax
        require(tax >= RAY, "ecm-exec-addAsset-tax-invalid");

        bytes32 paramsKey = user == address(0)  ?
            MathTools.k256(msg.sender)          :
            MathTools.k256(msg.sender, user);

        address owedGem = vat.owedGems(paramsKey);
        
        // must be approved token pair
        bytes32 pairKey = MathTools.k256(owedGem, gem);
        require(validTokenPairs[pairKey] == 1, "ecm-exec-addAsset-invalid-token-pair");

        VatLike.AssetClass memory asset;
        asset.use = 1;
        asset.tax = tax;
        asset.biteFee = biteFee;
        asset.biteLimit = biteLimit;

        vat.safeSetAsset(paramsKey, gem, asset);
        
        return true;
    }

    function toggleAsset(address user, address gem, bool use) external returns (bool) {
        bytes32 acctKey = MathTools.k256(msg.sender, user);
        vat.set("asset", "use", acctKey, gem, use ? 1 : 0);
        return true;
    }

    function call(address user, uint callTab) external returns (uint) {
        bytes32 acctKey = MathTools.k256(msg.sender, user);
        return _call(acctKey, callTab);
    }

    function _call(bytes32 acctKey, uint callTab) internal returns (uint) {
        return vat.doCall(acctKey, callTab);
    }


    // --- Administration ---
    function file(bytes32 what, address data) external onlyOwner {
        if (what == "vat") vat = VatLike(data);
        if (what == "vault") vault = VaultLike(data);
    }
    function file(bytes32 what, bytes32 key, uint data) external onlyOwner {
        if (what == "validTokenPair") validTokenPairs[key] = data;
    }

}