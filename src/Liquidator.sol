pragma solidity ^0.5.3;
pragma experimental ABIEncoderV2;

import "../lib/AuthTools.sol";
import "../lib/MathTools.sol";

contract BrokerLike {
    function spotPrices(bytes32) public view returns (uint);
}

contract VatLike {
    function accounts(bytes32) public view returns (Account memory);
    function updateTab(bytes32) public returns (uint);
    function assets(bytes32, address) public view returns (AssetClass memory);
    function owedGems(bytes32) public view returns (address);
    function set(bytes32, bytes32, bytes32, uint) external;
    function addTo(bytes32, bytes32, bytes32, uint) external;
    function addTo(bytes32, bytes32, uint) external;

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
    struct AssetClass {
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray, temporarily doubles as discount for collateral
        uint use;       // approved for use (0 = no, 1 = yes)
    }

}

contract VaultLike {
    function take(address, address, uint) external returns (bool);
    function give(address, address, uint) external returns (bool);
}

contract Liquidator is Ownable {
    
    VatLike public vat;
    VaultLike public vault;
    BrokerLike public broker;

    using SafeMath for uint;

    constructor(address _vat, address _broker) public {
        vat = VatLike(_vat);
        broker = BrokerLike(_broker);
    }

    function bite(bytes32 acctKey) external {

        vat.updateTab(acctKey);
        VatLike.Account memory acct = vat.accounts(acctKey);
        address owedGem = vat.owedGems(acct.paramsKey);
        VatLike.AssetClass memory asset = vat.assets(acct.paramsKey, owedGem);
        uint spotPrice = broker.spotPrices(MathTools.k256(owedGem, acct.heldGem));
        
        bool safe;
        if (acct.owedBal >= acct.owedTab) { 
            safe = true;
        } else {
            uint debit = MathTools.rmul(acct.owedTab, asset.biteLimit);
            uint credit = acct.owedBal.add(MathTools.convertBalance(acct.heldBal, spotPrice));
            safe = credit >= debit;
        }

        bool callIgnored = acct.callEnd > 0 && 
            now >= acct.callEnd             && 
            acct.owedBal < acct.callTab;

        require(!safe || callIgnored, "ecm-liquidator-bite-acct-safe");

        _grab(acctKey, owedGem, acct.heldGem, acct.heldBal, spotPrice, asset.biteFee);
    }

    function _grab(bytes32 acctKey, address owedGem, address heldGem, uint heldBal, uint spotPrice, uint biteFee) private {
        // take owedGem from biter, give heldGem
        // we know user has some heldGem, bc otherwise owedBal could not be <

        // TODO: should only bite as much collateral as we need to to cover the deficit
        // uint deficit = MathTools.max(
        //     !safe ? acct.owedTab.sub(acct.owedBal) : 0,
        //     acct.callTab > acct.owedBal ? acct.callTab - acct.owedBal : 0
        // );
        uint heldBalInOwedGem = MathTools.convertBalance(heldBal, spotPrice);
        uint biteCost = MathTools.getBiteCost(heldBalInOwedGem, biteFee);

        vat.set("account", "heldBal", acctKey, 0);

        require(vault.take(owedGem, msg.sender, biteCost), "ecm-liquidator-grab-transfer1-failed");

        vat.addTo("account", "owedBal", acctKey, biteCost);

        // require(vault.give(heldGem, msg.sender, heldBal), "ecm-liquidator-grab-transfer2-failed");
        bytes32 claimKey = MathTools.k256(msg.sender, heldGem);
        vat.addTo("claim", claimKey, heldBal);
    }
}