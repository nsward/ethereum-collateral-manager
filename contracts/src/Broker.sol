pragma solidity ^0.5.3;

import "./interfaces/VaultLike.sol";
import "./interfaces/WrapperLike.sol";
import "./events/BrokerEvents.sol";
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

contract Broker is AuthAndOwnable, BrokerEvents {

    using SafeMath for uint;

    mapping (address => uint256) public wrappers;   // valid exchange wrappers. address => 0 if invalid, 1 if valid
    mapping (bytes32 => uint256) public spotPrices;  // keccak256(dueToken, tradeToken) => wad due tokens / 1 wei trade token

    VatLike public vat;
    VaultLike public vault;

    constructor(address _vat, address _vault) public {
        vat = VatLike(_vat);
        vault = VaultLike(_vault);
    }

    // Sets account allowance, can only be called by the user of the account
    // or an approved pal. Prevents an attack where anyone could monitor the
    // approval events from popular ERC20s waiting for approvals to this contract,
    // then call open() from a malicious contract and steal all approved funds
    function setAllowance(address admin, address gem, uint allowance) external {
        bytes32 acctKey = MathTools.k256(admin, msg.sender);
        vat.set("allowance", acctKey, gem, allowance);
        emit SetAllowance(admin, msg.sender, gem, allowance);
    }

    function setAgent(bytes32 acctKey, address guy, bool trust) external {
        require(
            address(bytes20(vat.get("account", "user", acctKey))) == msg.sender,
            "ecm-broker-setAgent-unauthorized"
        );
        vat.set("agent", acctKey, guy, trust ? 1 : 0);
    }

    function free(bytes32 acctKey, address gem, uint amt) external {
        require(vat.isUserOrAgent(acctKey, msg.sender), "ecm-broker-free-not-authorized");
        vat.updateTab(acctKey);
        (address owedGem, address heldGem, ) = vat.owedAndHeldGemsByAccount(acctKey);

        require(gem == owedGem || gem == heldGem, "ecm-broker-free-gem-not-possessed");

        if (gem == heldGem) {
            vat.subFrom("account", "heldGem", amt);
        } else if (gem == owedGem) {
            vat.subFrom("account", "owedGem", amt);
        }

        address user = address(bytes20(vat.get("account", "user", acctKey)));

        require(safe(acctKey), "ecm-broker-free-resulting-account-unsafe");

        bytes32 claimKey = MathTools.k256(user, gem);
        vat.addTo("claims", claimKey, amt);
    }

    // Note: no allowance needed or decremented here, since funds come from msg.sender
    function lock(bytes32 acctKey, address gem, uint amt) external {
        require(gem != address(0) && amt > 0, "ecm-broker-lock-inputs-invalid");

        // get the owedToken and asset.use
        (   address owedGem, 
            address heldGem, 
            bytes32 paramKey
        ) = vat.owedAndHeldGemsByAccount(acctKey);
        
        if (gem == owedGem) {
            require(vault.take(gem, msg.sender, amt), "ecm-broker-lock-transfer-failed");
            vat.addTo("account", "owedBal", acctKey, amt);
            return;
        } else if (gem == heldGem) {
            require(vault.take(gem, msg.sender, amt), "ecm-broker-lock-transfer-failed");
            vat.addTo("account", "heldBal", acctKey, amt);
            return;
        } else if (heldGem == address(0)) {
            require(uint(vat.get("asset", "use", paramKey, gem)) == 1, "ecm-broker-lock-gem-unapproved");
            require(vault.take(gem, msg.sender, amt), "ecm-broker-lock-transfer-failed");
            vat.safeSetPosition(acctKey, gem, amt);
            return;
        } else {
            revert("ecm-broker-lock-invalid-gem");
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
        
        // debit. interest compounded once per second on the quantity (owedTab - owedBal)
        // over the time (now - lastAccrual). Debit also include the minimum
        // collateralization ratio (biteLimit)
        uint debit = MathTools.rmul(
            MathTools.getInterest(
                owedTab.sub(owedBal),
                tax,
                now.sub(lastAccrual)
            ).add(owedTab),
            biteLimit
        );
        uint val = spotPrices[MathTools.k256(owedGem, heldGem)];
        uint credit = SafeMath.add(owedBal, MathTools.convertBalance(heldBal, val));

        return credit >= debit;
    }

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
    public {
        // must be approved wrapper
        require(wrappers[wrapper] == 1, "ecm-broker-swap-invalid-wrapper");

        // get the owed token and held token
        (   address owedGem, 
            address heldGem, 
            bytes32 paramKey
        ) = vat.owedAndHeldGemsByAccount(acctKey);

        require(vat.isUserOrAgent(acctKey, msg.sender), "ecm-broker-swap-unauthorized");

        // accrue interest on the existing position
        vat.updateTab(acctKey);

        // cases:
        // - giving up due token, getting a new trade token
        // - giving up due token, getting more of our current trade token
        // - giving up trade token, getting due token
        // - giving up trade token, getting a new trade token

        uint partialAmt = MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt);

        // giving up owed token
        if (takerGem == owedGem) {
            if (makerGem == heldGem) {
                // giving up due token, getting more of our current trade token
                _swapOwedForHeld(acctKey, fillAmt, partialAmt);

            } else {
                // giving up due token, getting a new trade token
                _swapOwedForNewHeld(acctKey, paramKey, makerGem, fillAmt, partialAmt);

            }
        } else {
            require(takerGem == heldGem, "ecm-broker-swap-invalid-trading-pair");
            // giving up trade token

            if (makerGem == owedGem) {
                // giving up trade token, getting owed token
                _swapHeldForOwed(acctKey, fillAmt, partialAmt);

            } else {
                // giving up trade token, getting a new trade token
                _swapHeldForNewHeld(acctKey, paramKey, makerGem, heldGem, fillAmt, partialAmt);

            }
        }

        // make sure the account is still safe
        require(safe(acctKey), "ecm-broker-swap-resulting-position-unsafe");
        
        // take the trade
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
    }

    function _swapOwedForHeld(bytes32 acctKey, uint fillAmt, uint partialAmt) internal {
        vat.subFrom("account", "owedBal", acctKey, fillAmt);
        vat.addTo("account", "heldBal", acctKey, partialAmt);
    }

    function _swapOwedForNewHeld(bytes32 acctKey, bytes32 paramKey, address makerGem, uint fillAmt, uint partialAmt) internal {
        require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ecm-broker-lock-gem-unapproved");
        vat.subFrom("account", "owedBal", acctKey, fillAmt);
        // also checks that heldBal == 0
        vat.safeSetPosition(acctKey, makerGem, partialAmt);
    }

    function _swapHeldForOwed(bytes32 acctKey, uint fillAmt, uint partialAmt) internal {
        vat.subFrom("account", "heldBal", acctKey, fillAmt);
        vat.addTo("account", "owedBal", acctKey, partialAmt);
    }

    function _swapHeldForNewHeld(bytes32 acctKey, bytes32 paramKey, address makerGem, address heldGem, uint fillAmt, uint partialAmt) internal {
        require(uint(vat.get("asset", "use", paramKey, makerGem)) == 1, "ecm-broker-lock-gem-unapproved");

        // make sure we can cover the fillAmt. This is checked by the safe sub()
        // in every other case, but we must be explicit about it here
        uint heldBal = uint(vat.get("account", "heldBal", acctKey));
        require(heldBal >= fillAmt, "ecm-broker-swap-insufficient-tradeBalance");

        if (heldBal > fillAmt) {
            // add difference to claims
            address user = address(bytes20(vat.get("account", "user", acctKey)));
            bytes32 claimKey = MathTools.k256(user, heldGem);
            vat.addTo("claim", claimKey, heldBal.sub(fillAmt));
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
            fillAmt,
            orderData
        );

        require(
            makerAmtReceived >= MathTools.getPartialAmt(makerAmt, takerAmt, fillAmt), 
            "ecm-broker-executeTrade-unsuccessful"
        );

        // transfer from exchange wrapper back to vault
        vault.takeFromWrapper(
            makerGem, 
            wrapper,
            makerAmtReceived
        );
    }

    function claim(address gem, uint amt) external {
        bytes32 claimKey = MathTools.k256(msg.sender, gem);
        vat.subFrom("claim", claimKey, amt);
        require(vault.give(gem, msg.sender, amt), "ecm-broker-claim-transfer-failed");
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