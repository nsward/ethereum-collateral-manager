pragma solidity ^0.5.3;

// import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./interfaces/VaultLike.sol";
import "./interfaces/WrapperLike.sol";
import "../lib/MathTools.sol";
import "../lib/AuthTools.sol";

contract VatLike {
    function set(bytes32, bytes32, address, uint) external;
    function set(bytes32, bytes32, bytes32, uint) external;
    function set(bytes32, bytes32, bytes32, address) external;
    function get(bytes32, bytes32, bytes32) external view returns (bytes32);
    function get(bytes32, bytes32, bytes32, address) external view returns (bytes32);
    function addTo(bytes32, bytes32, bytes32, uint) external;
    function addTo(bytes32, bytes32, uint) external;
    function subFrom(bytes32, bytes32, bytes32, uint) external;
    function subFrom(bytes32, bytes32, uint) external;
    function updateTab(bytes32) external returns (uint);
    function getSafeArgs(bytes32) external view returns (address, address, uint, uint, uint, uint, uint, uint);
    function isUserOrAgent(bytes32, address) public view returns (bool);
    function owedAndHeldGemsByAccount(bytes32) external view returns (address, address, bytes32);
    function safeSetPosition(bytes32, address, uint) external;

}

// could be just Owned depending how spotter is handled
contract Broker is AuthAndOwnable {

    using SafeMath for uint;

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
    function setAllowance(address admin, address gem, uint allowance) external {
        // vat.safeSetAllowance(acctKey, msg.sender, gem, allowance);
        // require(vat.isUserOrAgent(acctKey, msg.sender), "ccm-broker-setAllowance-unauthorized");
        bytes32 acctKey = MathTools.k256(admin, msg.sender);
        vat.set("allowance", acctKey, gem, allowance);
    }

    function setAgent(bytes32 acctKey, address guy, bool trust) external {
        require(
            address(bytes20(vat.get("account", "user", acctKey))) == msg.sender,
            "ccm-broker-setAgent-unauthorized"
        );
        vat.set("agent", acctKey, guy, trust ? 1 : 0);
    }

    // TODO: ** nonReentrant?
    // Note: no allowance needed or decremented here, since funds come from msg.sender
    function lock(bytes32 acctKey, address gem, uint amt) external returns (bool) {
        require(gem != address(0) && amt > 0, "ccm-broker-lock-inputs-invalid");

        // get the owedToken and asset.use
        (   address owedGem, 
            address heldGem, 
            bytes32 paramKey
        ) = vat.owedAndHeldGemsByAccount(acctKey);
        
        if (gem == owedGem) {
            require(vault.take(gem, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.addTo("account", "owedBal", acctKey, amt);
            // vat.addOwedBal(acctKey, amt);
            return true;
        } else if (gem == heldGem) {
            require(vault.take(gem, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.addTo("account", "heldBal", acctKey, amt);
            // vat.addHeldBal(acctKey, amt);
            return true;
        } else if (heldGem == address(0)) {
            require(uint(vat.get("asset", "use", paramKey, gem)) == 1, "ccm-broker-lock-gem-unapproved");
            require(vault.take(gem, msg.sender, amt), "ccm-broker-lock-transfer-failed");
            vat.safeSetPosition(acctKey, gem, amt);
            return true;
        } else {
            revert("ccm-broker-lock-invalid-gem");
        }
    }

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
                owedTab.sub(owedBal),
                tax,
                now.sub(lastAccrual)
            ),
            biteLimit
        );
        uint val = spotPrices[MathTools.k256(owedGem, heldGem)];
        uint credit = SafeMath.add(owedBal, SafeMath.mul(heldBal, val));

        return credit >= debit;
    }

    // TODO nonReentrant
    // TODO: provide an option to add order to noFills
    function swap(
        bytes32 acctKey,
        address wrapper,
        address makerGem,
        address takerGem,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes memory orderData
    ) 
    public returns (bool) {
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

        uint partialAmt = MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt); // todo: stack too deep

        // giving up owed token
        if (takerGem == owedGem) {
            if (makerGem == heldGem) {
                // giving up due token, getting more of our current trade token
                _swapOwedForHeld(acctKey, fillAmt, partialAmt);

                // update balances
                // vat.subOwedBal(acctKey, fillAmt);
                // vat.addHeldBal(partialAmt);
                // vat.subFrom("account", "owedBal", acctKey, fillAmt);
                // vat.addTo("account", "heldBal", acctKey, 
                //     MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt));  // todo: stack too deep
            } else {
                // giving up due token, getting a new trade token
                _swapOwedForNewHeld(acctKey, paramKey, makerGem, fillAmt, partialAmt);

                // require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");
                // // vat.subOwedBal(acctKey, fillAmt);
                // vat.subFrom("account", "owedBal", acctKey, fillAmt);
                // // also checks that heldBal == 0
                // vat.safeSetPosition(acctKey, makerGem, 
                //     MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt));
            }
        } else {
            require(takerGem == heldGem, "ccm-broker-swap-invalid-trading-pair");
            // giving up trade token

            if (makerGem == owedGem) {
                // giving up trade token, getting owed token
                _swapHeldForOwed(acctKey, fillAmt, partialAmt);

                // vat.subHeldBal(acctKey, fillAmt);
                // vat.addOwedBal(acctKey, partialAmt);
                // vat.subFrom("account", "heldBal", acctKey, fillAmt);
                // vat.addTo("account", "owedBal", acctKey, partialAmt);
            } else {
                // giving up trade token, getting a new trade token
                _swapHeldForNewHeld(acctKey, paramKey, makerGem, heldGem, fillAmt, partialAmt);

                // require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");
                // // make sure we can cover the fillAmt. This is check by the DSMath sub()
                // // in every other case, but we must be explicit about it here
                // uint heldBal = uint(vat.get("account", "heldBal", acctKey));
                // require(heldBal >= fillAmt, "ccm-broker-swap-insufficient-tradeBalance");
                // // figure out how to handle excess current tradeToken
                // // if fillAmt < tradeBalance -> we'll have some left over. Can we just add this to claims? or should we not allow this?
                // if (heldBal > fillAmt) {
                //     // add difference to claims
                //     address user = address(bytes20(vat.get("account", "user", acctKey)));    // todo:stack too deep
                //     bytes32 claimKey = MathTools.k256(user, heldGem);
                //     // vat.addTo("claim", claimKey, heldBal.sub(fillAmt));
                //     vat.addTo("claim", claimKey, heldGem), heldBal.sub(fillAmt));
                //     // vat.addClaim(
                //     //     claimKey,
                //     //     SafeMath.sub(heldBal, fillAmt)
                //     // );
                // }
                // vat.set("account", "heldGem", acctKey, makerGem);
                // vat.set("account", "heldBal", acctKey, partialAmt);

            }
        }

        // make sure the account is still safe
        require(safe(acctKey), "ccm-broker-swap-resulting-position-unsafe");

        _executeTrade(
            wrapper,
            msg.sender,
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

    function _swapOwedForHeld(bytes32 acctKey, uint fillAmt, uint partialAmt) internal {
        vat.subFrom("account", "owedBal", acctKey, fillAmt);
        vat.addTo("account", "heldBal", acctKey, partialAmt);
    }

    function _swapOwedForNewHeld(bytes32 acctKey, bytes32 paramKey, address makerGem, uint fillAmt, uint partialAmt) internal {
        require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");
        // vat.subOwedBal(acctKey, fillAmt);
        vat.subFrom("account", "owedBal", acctKey, fillAmt);
        // also checks that heldBal == 0
        vat.safeSetPosition(acctKey, makerGem, partialAmt);
    }

    function _swapHeldForOwed(bytes32 acctKey, uint fillAmt, uint partialAmt) internal {
        vat.subFrom("account", "heldBal", acctKey, fillAmt);
        vat.addTo("account", "owedBal", acctKey, partialAmt);
    }

    function _swapHeldForNewHeld(bytes32 acctKey, bytes32 paramKey, address makerGem, address heldGem, uint fillAmt, uint partialAmt) internal {
        require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ccm-broker-lock-gem-unapproved");

        // make sure we can cover the fillAmt. This is checked by the DSMath sub()
        // in every other case, but we must be explicit about it here
        uint heldBal = uint(vat.get("account", "heldBal", acctKey));
        require(heldBal >= fillAmt, "ccm-broker-swap-insufficient-tradeBalance");

        // figure out how to handle excess current tradeToken
        // if fillAmt < tradeBalance -> we'll have some left over. Can we just add this to claims? or should we not allow this?
        if (heldBal > fillAmt) {
            // add difference to claims
            address user = address(bytes20(vat.get("account", "user", acctKey)));    // todo:stack too deep
            bytes32 claimKey = MathTools.k256(user, heldGem);
            vat.addTo("claim", claimKey, heldBal.sub(fillAmt));
            // vat.addTo("claim", claimKey, heldGem, heldBal.sub(fillAmt));
            // vat.addClaim(
            //     claimKey,
            //     SafeMath.sub(heldBal, fillAmt)
            // );
        }

        vat.set("account", "heldGem", acctKey, makerGem);
        vat.set("account", "heldBal", acctKey, partialAmt);
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
            makerGem,
            takerGem,
            makerAmt,
            takerAmt,
            fillAmt,
            orderData
        );

        require(
            makerAmtReceived >= MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt), 
            "ccm-broker-executeTrade-unsuccessful"
        );

        // transfer from exchange wrapper back to vault
        // TODO: ** will need to make sure wrappers are all approving() sufficient amounts
        vault.takeFromWrapper(
            makerGem, 
            wrapper,
            makerAmtReceived
        );
    }

    // TODO nonReentrant
    function claim(address gem, uint amt) external returns (bool) {
        bytes32 claimKey = MathTools.k256(msg.sender, gem);
        // vat.subClaim(claimKey, amt);
        vat.subFrom("claim", claimKey, amt);
        require(vault.give(gem, msg.sender, amt), "ccm-broker-claim-transfer-failed");
    }


    // --- Administration ---
    // called by spotter
    function spot(bytes32 key, uint data) external auth {
        spotPrices[key] = data;
    }
    function file(bytes32 what, address addr, uint data) external onlyOwner {
        if (what == "wrapper") wrappers[addr] = data;
    }
    function file(bytes32 what, address data) external onlyOwner {
        if (what == "vat") vat = VatLike(data);
        if (what == "vault") vault = VaultLike(data);
    }


}