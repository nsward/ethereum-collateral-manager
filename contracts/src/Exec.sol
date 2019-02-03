pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./Interfaces/VaultLike.sol";
import "../lib/MathTools.sol";
import "../lib/Auth.sol";

contract VatLike {

}

// TODO: just need ownable? maybe break up AuthTools into Auth, Owned, AuthAndOwned
contract Exec is Auth {

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
        require(user != address(0), "ccm-chief-open-lad-invalid");

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
        bytes32 paramsKey = Math.k256(msg.sender);
        // verifies that current owedToken is uninitialized, then sets it
        vat.safeSetOwedGem(paramsKey, owedToken);
        return true;
    }

    function addAsset(uint tax, uint biteLimit, uint biteFee, address asset, address user) external returns (bool) {
        // liquidation penalty must be at least 1
        require(biteFee >= RAY, "ccm-chief-ngem-axe-invalid");
        // extra collateral has to be able to at least cover penalty
        require(biteLimit > biteFee, "ccm-chief-ngem-mat-invalid");
        // RAY is equivalent to no tax
        require(tax > RAY, "ccm-exec-addAsset-tax-invalid");

        bytes32 acctKey = MathTools.k256(msg.sender, user);

        (address owedGem, bytes32 paramsKey) = vat.owedGemByAccount(acctKey);
        require(paramsKey != bytes32(0));
        
        // must be approved token pair
        bytes32 pairKey = MathTools.k256(owedGem, newGem);
        require(validTokenPairs[pairKey] == 1);

        VatLike.Asset asset;
        asset.use = 1;
        asset.tax = tax;
        asset.biteFee = biteFee;
        asset.biteLimit = biteLimit;

        vat.safeSetAsset(paramsKey, asset);
        
        return true;
    }

    function toggleAsset(address asset, uint use) external retunrs (bool) {
        uint useAsUint = use ? 1 : 0;
        vat.set("asset", "use", useAsUint);
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