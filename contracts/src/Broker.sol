pragma solidity ^0.5.3;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./Interfaces/VaultLike.sol";
import "../lib/MathTools.sol";
import "../lib/Auth.sol";

contract VatLike {

}

// could be just Owned depending how spotter is handled
contract Broker is Auth {

    mapping (address => uint256) public wrappers;   // valid exchange wrappers. keccak256(wrapperAddress, exchangeAddress) => bool
    //mapping (bytes32 => address) public spotters;   // keccak256(dueToken, tradeToken) => spotter
    mapping (bytes32 => uint256) public spotPrices;  // keccak256(dueToken, tradeToken) => due tokens / 1 trade token

    VatLike public vat;
    VaultLike public vault;

    constructor(address _vat, address _vault) public {
        vat = VatLike(_vat);
        vault = VaultLike(_vault);
    }

    // Sets account allowance, can only be called by the user of the account
    // or an approved pal. Prevents an attack where anyone could monitor the
    // approval events from popular ERC20s waiting for approvals to this contract,
    // then call open() from a malicious contract and effectively steal all
    // approved funds
    function setAllowance(bytes32 acctKey, address gem, uint allowance) external {
        // vat.safeSetAllowance(acctKey, msg.sender, gem, allowance);
        require(vat.isUserOrAgent(acctKey, msg.sender), "ccm-broker-setAllowance-unauthorized");
        vat.set("allowance", acctKey, gem, allowance);
    }

    function setAgent(bytes32 acctKey, address guy, bool trust) external {
        require(
            address(bytes20(vat.get("account", "user", acctKey))) == msg.sender,
            "ccm-broker-setAgent-unauthorized"
        );
        uint trustAsUint = trust ? 1 : 0;
        vat.set("agent", acctKey, guy, trustAsUint);
    }

    // TODO: ** nonReentrant?
    // Note: no allowance needed or decremented here, since funds come from msg.sender
    function lock(bytes32 acctKey, address gem, uint amt) external returns (bool) {
        require(gem != address(0) && amt > 0, "ccm-chief-lock-inputs-invalid");

        // get the owedToken and asset.use
        (   address owedGem, 
            address heldGem, 
            bytes32 paramKey
        ) = vat.owedAndHeldGemsByAccount(acctKey);
        
        if (gem == owedGem) {
            require(vault.take(gem, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.addOwedBal(acctKey, amt);
            return true;
        } else if (gem == heldGem) {
            require(vault.take(token, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.addHeldBal(acctKey, amt);
            return true;
        } else if (heldGem == address(0)) {
            require(uint(vat.get("asset", "use", paramKey, gem)) == 1, "ccm-broker-lock-gem-unapproved");
            require(vault.take(token, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.safeSetPosition(acctKey, gem, amt);
            return true;
        } else {
            revert("ccm-broker-lock-invalid-gem");
        }
    }

    // Should safe just be a vat function?
    // vat reads:
    // owedBal
    // heldBal
    // owedTab
    // lastAccrual
    // asset.tax
    // asset.biteLimit
    // 
    function safe(bytes32 acctKey) public view returns (bool) {
        (address owedGem,
            address heldGem,
            uint owedBal, 
            uint heldBal, 
            uint owedTab, 
            uint lastAccrual, 
            uint tax, 
            uint biteLimit
        ) = vat.getSafeArgs(acctKey);

        // if the due amount is held in due token, then account is safe
        // regardless of biteLimit or interest charged
        if (owedBal >= owedTab) { return true; }
        
        uint debit = MathTools.rmul(
            MathTools.accrueInterest(
                SafeMath.sub(owedTab, owedBal),
                tax,
                SafeMath.sub(lastAccrual)
            ),
            biteLimit
        );
        uint val = spotPrices[MathTools.k256(owedGem, heldGem)];
        uint credit = SafeMath.add(owedBal, SafeMath.mul(heldBal, val));

        return credit >= debit;
    }

    // TODO nonReentrant
    function swap(
        bytes32 acctKey,
        address wrapper,
        address makerGem,
        address takerGem,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes calldata orderdata
    ) 
    external returns (bool) {
        // TODO: add delete safe order

        // must be approved wrapper
        require(wrappers[wrapper] == 1, "ccm-broker-swap-invalid-wrapper");

        // get the owed token and held token
        (   address owedGem, 
            address heldGem, 
            bytes32 paramKey
        ) = vat.owedAndHeldGemsByAccount(acctKey);

        require(vat.isUserOrAgent(acctKey, msg.sender), "ccm-broker-swap-unauthorized");

        // accrue interest on the existing position
        vat.updateTab(acctKey);

        // cases:
        // - giving up due token, getting a new trade token
        // - giving up due token, getting more of our current trade token
        // - giving up trade token, getting due token
        // - giving up trade token, getting a new trade token

        uint parialAmt = MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt);

        // giving up owed token
        if (takerGem == owedGem) {
            if (makerGem == heldGem) {
                // giving up due token, getting more of our current trade token
                // update balances
                vat.subOwedBal(acctKey, fillAmt);
                vat.addHeldBal(partialAmt);
            } else {
                // giving up due token, getting a new trade token
                require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");
                vat.subOwedBal(acctKey, fillAmt);
                // also checks that heldBal == 0
                vat.safeSetPosition(acctKey, makerGem, partialAmt);
            }
        } else {
            require(takerGem == heldGem, "ccm-broker-swap-invalid-trading-pair");
            // giving up trade token

            if (makerGem == owedGem) {
                // giving up trade token, getting owed token
                vat.subHeldBal(acctKey, fillAmt);
                vat.addOwedBal(acctKey, partialAmt);
            } else {
                // giving up trade token, getting a new trade token
                require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");

                // make sure we can cover the fillAmt. This is check by the DSMath sub()
                // in every other case, but we must be explicit about it here
                uint heldBal = uint(vat.get("account", "heldBal", acctKey));
                require(heldBal >= fillAmt, "ccm-chief-swap-insufficient-tradeBalance");

                // figure out how to handle excess current tradeToken
                // if fillAmt < tradeBalance -> we'll have some left over. Can we just add this to claims? or should we not allow this?
                if (heldBal > fillAmt) {
                    // add difference to claims
                    address user = address(bytes20(vat.get("account", "user", acctKey)));
                    bytes32 claimKey = MathTools.k256(user, heldGem);
                    vat.addClaim(
                        claimKey,
                        SafeMath.sub(heldBal, fillAmt)
                    );
                }

                vat.set("account", "heldGem", acctKey, makerGem);
                vat.set("account", "heldBal", acctKey, partialAmt);

            }
        }

        // make sure the account is still safe
        require(safe(accountKey), "ccm-broker-swap-resulting-position-unsafe");

        _executeTrade(
            msg.sender,
            wrapper,
            makerGem,
            takerGem,
            makerAmt,
            takerAmt,
            fillAmt,
            orderData
        );

        // reads:
        // - safeArgs
        // owedGem
        // heldGem
        // asset.use
        // isUserOrAgent()
        // 

        // writes:
        // updateTab()
        // owedBal
        // heldBal
        // heldGem
    }

    function _executeTrade(
        address wrapper,
        address tradeOrigin,
        address makerGem,
        address takerGem,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes memory orderData
    ) 
        internal
    {
        // transfer funds to wrapper
        vault.giveToWrapper(takerGem, wrapper, fillAmt);

        // Note that the actual implementation of this will be different for
        // each exchange wrapper, but this will fill the order exactly as
        // specified or revert the transaction
        uint makerAmtReceived = WrapperLike(wrapper).fillOrKill(
            tradeOrigin,
            makerAsset,
            takerAsset,
            makerAmt,
            takerAmt,
            fillAmt,
            orderData
        );

        require(
            makerAmtReceived >= getPartialAmt(makerAmt, takerAmt, fillAmt), 
            "ccm-broker-executeTrade-unsuccessful"
        );

        // transfer from exchange wrapper back to vault
        // TODO: ** will need to make sure wrappers are all approving() sufficient amounts
        vault.takeFromWrapper(
            makerAsset, 
            wrapper,
            makerAmtReceived
        );
    }

    // TODO nonReentrant
    function claim(address gem, uint amt) external returns (bool) {
        bytes32 claimKey = MathTools.k256(msg.sender, gem);
        vat.subClaim(claimKey, amt);
        require(vault.give(gem, msg.sender, amt), "ccm-broker-claim-transfer-failed");
    }


    // --- Administration ---
    function spot(bytes32 key, uint data) external auth {
        spotPrices[key] = data;
    }
    function file(bytes32 what, address key, uint data) external onlyOwner {
        if (what == "wrapper") wrappers[key] = data;
    }
    function file(bytes32 what, address data) external onlyOwner {
        if (what == "vat") vat = VatLike(data);
        if (what == "vault") vault = VaultLike(data);
    }


}