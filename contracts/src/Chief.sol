pragma solidity ^0.5.2;

import "./Vault.sol";
import "../lib/DSMath.sol";
import "../lib/DSNote.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

// TODO return false when reasonable instead of reverting to allow managing contract to deal with shit

// TODO 1/9
// diagram out the flow between contracts -> esp. storage between chief and vault
// Get the tester contract working (i.e. external contract for testing Chief)
// Look into 0x proxy plans
// Call dad
// - update interest before entering zen, then era + zen = liquidation time
// What happens if we need to increase ohm while in zen?

// TODO: need a max zen?
    // bad things from a super high zen:
    //  - could overflow endZen time in move(), but that would really
    //  only stop the contract from moving money, which would be the case
    //  anyway if their zen time overflows a uint256
    //  - ?
// - Add state enum and an amtDueAfterCall (owe?, ohm?) to Acct
// - add a call() function to start zen without paying out
// - if zen expires and you get bitten, axe won't go to keepers (they should be 
//   able to bite, but managing contracts can't just wait until bitten, so they
//   will call move() first sometimes. axe can't go to managing contract bc it
//   would incentivize tricky acct management strategies. So it has to go to
//   a burn pool. As long as we have a burn pool, let's add win and send
//   axe - win to the burn pool too
//   

// CCM - contract-collateral-manager
// Ownable for setting oracle stuff - hopefully governance in the future
contract Chief is Ownable, DSMath, DSNote, ReentrancyGuard {
    // TODO:
    // Par, Called, Liquidation, Old
    enum State{ Par, Call, Bit, Old } // -- par, zen, bit, auc, old
                                    //This can just be a bool (inZenState) IF we don't need
                                    // an additional state for liquidations, auctions, etc. (which we probably do?)
                                    //

    // Note: 0x standard followed in favor of our own naming convention here
    struct Order {
        address makerAddress;           // Address that created the order.
        address takerAddress;           // Address that is allowed to fill the order. If set to 0, any address is allowed to fill the order.
        address feeRecipientAddress;    // Address that will recieve fees when order is filled.
        address senderAddress;          // Address that is allowed to call Exchange contract methods that affect this order. If set to 0, any address is allowed to call these methods.
        uint256 makerAssetAmount;       // Amount of makerAsset being offered by maker. Must be greater than 0.
        uint256 takerAssetAmount;       // Amount of takerAsset being bid on by maker. Must be greater than 0.
        uint256 makerFee;               // Amount of ZRX paid to feeRecipient by maker when order is filled. If set to 0, no transfer of ZRX from maker to feeRecipient will be attempted.
        uint256 takerFee;               // Amount of ZRX paid to feeRecipient by taker when order is filled. If set to 0, no transfer of ZRX from taker to feeRecipient will be attempted.
        uint256 expirationTimeSeconds;  // Timestamp in seconds at which order expires.
        uint256 salt;                   // Arbitrary number to facilitate uniqueness of the order's hash.
        bytes makerAssetData;           // ABIv2 encoded data that can be decoded by a specified proxy contract when transferring makerAsset.
        bytes takerAssetData;           // ABIv2 encoded data that can be decoded by a specified proxy contract when transferring takerAsset.
    }
    // tokenPair, tradingPair
    struct TokenPair {
        address spotter;  // spotter  // fetches and sets the spot price
        uint spotPrice;       // spotPrice    // spot price. Important note: does not incorporate mat like dai's spotter does
        bool use;       // valid, approved, use       // valid pair?
        // // TODO: oracle stuff
        // bool use;
        // uint val;  // val?, Price. pairs[gem1][gem2] is selling gem1 for gem2.
        //             // price will be X gem2 tokens for 1 gem1 token
        //   val should be due tokens / 1 gem
    }
    // AssetClass Token, tokenParams, params, 
    struct AssetClass {
        bool use;   
        uint tax;   // rate
        uint biteLimit;   // liquidationLimit, mcr, biteLimit        // Minimum Collateralization Ratio
        uint biteFee;   // liquidationPenalty, biteFee, penaltyRatio            // liquidation penalty
        // add keeperReward, biteReward, bitePay? What do keepers get for biting?
                
    }
    // execParam, execPair, 
    struct ExecParam {
        address dueToken;
        mapping (address => AssetClass) tokens;    // tokenParams
    }
    struct Account {
        // Set by managing contract
        uint    callTab;    // callAmt, callTab    // TODO, amt of due token needed at end of Zen. Should be 0 if not in zen
        uint    dueTab;    // dueTab, dueAmt, owedAmt    // Max payout amt 
        uint    dueBalance;    // dueBal, dueBalance     // due balance, denominated in due tokens
        uint    callTime;    // callTime    // time given to return collateral to due before liquidation 
        bool    useExecParams;    // ?    // true ? use local gems : use mamas[who]. ** make sure mamas[mom].axe valid (> 1)?
        address exec;    // managingContract, manager, exec, captain    // Address of managing contract, man, 
        address dueToken;    // dueToken, owedToken    // Address of the ERC20 token to pay out in
        mapping (address => AssetClass) tokens;    // tokens    // Tokens that can be held as collateral and the parameters

        // Set by user
        bool    useAuction;    // useAuction, auction    // opt-in to dutch auction? auc
        uint    tradeBalance;    // heldBal, heldBalance    // lot, vol, own? gem balance, denominated in gems?
        address tradeToken;    // tradeToken, heldToken    // Token currently held (can be in addition to due balance)
        Order   safeOrder;    // defaultOrder, safeOrder    // Default order to take if called for payment.
        mapping (address => bool) pals; // Approved to handle trader's account

        State state;   
        uint  lastAccrual;    // lastAccrual,    // Time of last interest accrual
    }

    // function foo(address a, address b) public pure returns(bytes32) {
    //     return keck(a, b);
    // }

    // TODO: get lock() working(), then come back to this?
    // or find a way to figure this out without gem balance?
    // function safe(bytes32 acctKey) public view returns (bool) {
    // // function safe(address a, address b) public view returns (uint) {
    //     // literally just return whether adjusted collateral value > mat * tab
    //     // where adjusted collateral value = bal + own * pairs[]
    //     // return accts[keck(a, b)].tab;
    //     Acct memory acct = accts[acctKey];
    //     Asset memory asset = accts[acctKey].gems[accts[acctKey].gem];

    //     uint debit = mul(grow(acct.tab, asset.tax, sub(now, acct.era)), asset.mat);

    //     uint val = pairs[keck(acct.due, acct.gem)].val;
    //     uint credit = add(acct.bal, mul(acct.own, val));    // wmul()?

    //     // uint ownInDueToken = mul(acct.own, val);

    //     return credit >= debit;
    // }

    // TODO: check check check this
    // TODO: manage owe overflow here?
    // function safe(address _who, address _lad) public view returns (bool) {
    //     // if state is bit? or old, return true
    //     //
    //     // if state is zen:
    //     // if Zen is over and bal < ohm, return false
    //     // else, check the same stuff as par:
    //     //
    //     // if state is par:
    //     // owe = grow(tab, tax, now - era)
    //     // if owe > max_tab, return false
    //     // held = bal + val converted into due token
    //     // if held < owe * mat, return false
    //     // else:
    //     // return true?
        
    //     // Acct memory acct = accts[keccak256(abi.encodePacked(_who, _lad))];
    //     Acct memory acct = accts[keck(_who, _lad)];

    //     // TODO: return true if state is bit?
    //     if (acct.state == State.Old || acct.state == State.Bit) {return true;}

    //     uint age = sub(now, acct.era);

    //     // TODO: Should not meeting ohm after Zen be unsafe?
    //     //      - I think we should have a separate function for this?
    //     // If state is Zen, Zen is over, and bal < ohm, unsafe
    //     if (acct.state == State.Zen && age >= acct.zen) {   // TODO: this is all wrong. How can you check
    //         uint owe = grow(acct.ohm, acct.tax, age);       // undercollateralization if Zen is expired?
    //         if (owe > max_tab || acct.bal < owe) {
    //             return false;
    //         }
    //     }   // TODO: this after some sleep

    //     if (acct.state == State.Par) {

    //     }

        

    // }

    // "the minimum amount you must lock in the cdp is 0.005 ether"
    // TODO: set these values
    uint256 public accountId;             // Incremented for keepers to find accounts
    uint256 public minTab = 1;         // minTab   // not profitable for keepers to bite below this
    uint256 public maxTax = uint(-1);  // maxRate  // maximum interest rate
    uint256 public maxTab = uint(-1);  // maxTab  // tab above which keepers can bite TODO: change name of this if tab is not updated with interest
    
    
    mapping (address => ExecParam) public execParams; //execParams    // Contract-wide Asset Paramaters
    // Only internal bc of compiler complaint about nested structs. Need to create getter
    mapping (bytes32 => Account) internal accounts; // keccak256(contract, user) => Account
    mapping (bytes32 => TokenPair) public tokenPairs;  //tokenPairs, tradingPairs // keccak256(due, gem) => Trading Pair
    mapping (uint256 => bytes32) public accountKeys;  // acctKeys, acctIds -> acct_id => acct_key // acct_id => accts key for the acct, finds? finda

    // address public proxy;   // Only used for automatic getter
    Vault public vault;

    constructor(address _vault) public {
        vault = Vault(_vault);
        // proxy = _proxy;
    }

    // called by the managing contract
    // if _mom == true, _due should be 0
    function _open(
        uint256 dueTab,   // Collateral amount, denominated in _due token
        uint256 callTime,
        address user,   // Address of the payer TODO: can't be msg.sender?
        address dueToken,   // Address of the token to pay out in
        bool    useExecParams    // If true, use contract-wide Asset Params. else, set below
    ) private returns (bool) {
        // Account user can't be zero
        require(user != address(0), "ccm-chief-open-lad-invalid");

        // TODO: Should we require the manager to be a contrract? To prevent people unaware
        // that an EOA would be able to take all their funds?
        
        // Payout token can't be 0 unless mama params being used. 
        // NOTE: No checks on whether _due has any token matches
        // if mom, check contract-wide due address, else check _due
        if (useExecParams) {
            require(execParams[msg.sender].dueToken != address(0), "ccm-chief-open-mama-due-invalid");
        } else {
            require(dueToken != address(0), "ccm-chief-open-due-invalid");
        }

        // Check that owed amt is valid
        require(dueTab > minTab && dueTab < maxTab, "ccm-chief-open-tab-invalid");
        // Grab the account
        bytes32 accountKey = getHash(msg.sender, user);
        Account storage account = accounts[accountKey];
        // Check that account doesn't exist already. TODO: check who too?
        require(account.lastAccrual == 0, "ccm-chief-open-account-exists");
        // Add id to radar and increment acct_id
        accountKeys[accountId] = accountKey;
        accountId = add(accountId, 1); 
        // Initialize the account
        account.exec = msg.sender;
        account.dueTab = dueTab;
        account.useExecParams = useExecParams;
        account.callTime = callTime;
        account.lastAccrual = now;
        if (!useExecParams) {account.dueToken = dueToken;}    // TODO: just set this anyway?

        require(vault.take(dueToken, user, dueTab), "ccm-chief-open-take-failed");
        // TODO
        account.dueBalance = dueTab;

        return true;       
    }

    // add new Asset to mama or acct
    // addAsset(), addAssetClass(), addToken, addAsset
    function _addAsset(
        uint256 tax,   // interest rate charged on swapped collateral   
        uint256 biteLimit,   // minimum collateralization ratio, as a ray
        uint256 biteFee,   // liquidation penalty, as a ray
        address token,   // address of the token to add
        address user,   // address of the holder / payer
        bool    useExecParams    // set this to contract-wide params?
    ) 
        private returns (bool) 
    {
        // do all the checks
        // if mom grab from mom else grab from baby
        // do last check and set

        // TODO: make sure we don't need a minimum for axe
        // liquidation penalty > 1 required to prevent auction grinding
        require(biteFee > RAY, "ccm-chief-ngem-axe-invalid");
        // extra collateral has to be able to at least cover axe
        require(biteLimit > biteFee, "ccm-chief-ngem-mat-invalid");
        // Check that tax is valid
        require(tax < maxTax, "ccm-chief-ngem-tax-invalid");

        // TODO: probably don't need these, checking pairs
        // require(mama.due != address(0), "collateral-vault-mama-due-not-set");
        // require(_gem != address(0), "collateral-vault-mama-address-invalid");

        bytes32 key;
        address dueToken;
        AssetClass memory asset;
        // mama or account?
        if (useExecParams) { 
            dueToken = execParams[msg.sender].dueToken;
            asset = execParams[msg.sender].tokens[token]; 
        } else {
             // Check that account exists 
            key = getHash(msg.sender, user);
            require(accounts[key].lastAccrual > 0, "ccm-chief-ngem-acct-nonexistant");
            // Check that account is not using the mom params (waste of gas and
            // deceptive to the contract to set params that aren't used)
            require(!accounts[key].useExecParams, "ccm-chief-ngem-acct-uses-mom");
            dueToken = accounts[key].dueToken;
            asset = accounts[key].tokens[token];
        }

        // gem must be an approved token pair with due
        require(tokenPairs[getHash(dueToken, token)].use, "ccm-chief-ngem-token-pair-invalid");

        // TODO: mama.mat>0 very important, prevents editing gem params
        // after setting use to false. Make sure there's no way around this
        // Also, does just checking mat work?
        // require(!mama.use && mama.mat > 0, "collateral-vault-mama-gem-in-use");
        require(asset.biteLimit > 0, "ccm-chief-ngem-gem-in-use");

        asset.use = true;
        asset.tax = tax;
        asset.biteLimit = biteLimit;
        asset.biteFee = biteFee;


        if(useExecParams) {execParams[msg.sender].tokens[token] = asset;}
        else {accounts[key].tokens[token] = asset;}

        return true; 
    }

    // State altering functions
    ////// Managing Contract Functions:
    // open()       - implemented
    // mdue()   - add initial due to mamas, born, girl?, mama
    // mama()   - add an Asset to mamas, mgem, 
    // baby()   - add an Asset to specific acct, daut, bgem
    // bump()   - disable a gem in mama for future users - could also use mama/daut(false) to remove, mpop, clean, moff and boff, m_on and b_on
    //          - X disable a gem for specific acct as long as not currently held, bump, bpop  ** make these be able to toggle use
    // move()   - pay out to specified address, send-probs confusing, post, drop, give, move, take
    // close()?  - set tab = 0, either leave user balance or transfer it to pull() balances
    //
    ////// User Functions:
    // lock()   - add either gem or due tokens, as long as it stays safe
    // free()   - claim either gem or due tokens, as long as it stays safe
    //          - set, change, or remove jet, zoom, tend, plane, edit, lift, land
    // meet()   - approve/unapprove a pal, talk, 
    //          - opt in/out of dutch auction, care, tend, 
    // swap()   - use 0x order to trade due or gem for new gem, as long as it stays safe. Also, delete jet
    // pull()   - calls Vault.give(), pays out users         
    //
    ////// Keeper Functions:
    // acct_id()      - implemented
    // bite()
    //
    ////// Vault Functions:
    // take() - transfers tokens from user to vault
    // give() - transfers tokens from vault to user
    // gift() - updates a user's pull balance
    //
    ////// Proxy Functions:
    // deal()   - transfers tokens
    //
    ////// Auction Functions:
    //
    ////// Intermediate Functions:
    // safe()


    /////////////
    // External Functions
    ////////////

    // TODO: do we need to check safe()? Nope - might be using this while unsafe to get safe.
    function lock(
        address exec, 
        address token, 
        uint256 amt
    ) 
        external nonReentrant returns (bool) 
    {    
        require(exec != address(0) && token != address(0) && amt > 0, "ccm-chief-lock-invalid-inputs");

        // Acct storage acct = accts[keccak256(abi.encodePacked(who, msg.sender))];
        Account storage account = accounts[getHash(exec, msg.sender)];
        address dueToken;
        bool use;

        if (account.useExecParams) {                     // use mom params
            dueToken = execParams[exec].dueToken;
            use = execParams[exec].tokens[token].use;
        } else {                            // use acct params
            dueToken = account.dueToken;
            use = account.tokens[token].use;
        }

        if (token == dueToken) {                  // topping up due token
            require(vault.take(token, msg.sender, amt));
            account.dueBalance = add(account.dueBalance, amt);
            return true;
        } 
        if (token == account.tradeToken) {             // topping up gem token
            require(vault.take(token, msg.sender, amt)); 
            account.tradeBalance = add(account.tradeBalance, amt);
            return true;
        }
        if (account.tradeToken == address(0)) {       // adding a new gem token
            require(use, "ccm-chief-lock-gem-not-approved");
            assert(account.tradeBalance == 0);          // If this is false, we're in trouble
            require(vault.take(token, msg.sender, amt)); //TODO: reentrancy
            account.tradeToken = token;
            account.tradeBalance = amt;
            return true;
        }

        return false;   // user submitted an invalid _gem address. revert here?
    }

    // toggle approved acct managers
    // togglePal()
    function togglePal(address exec, address pal, bool approve) external returns (bool) {
        // accts[keccak256(abi.encodePacked(who, msg.sender))].pals[pal] = yes;
        accounts[getHash(exec, msg.sender)].pals[pal] = approve;
        return true;    // Note: return true on sucess, not new pals[pal]
    }

    // Set the contract-wide due token
    // setExecDueToken
    function setExecDueToken(address dueToken) external returns (bool) {
        // _due can't be zero
        require(dueToken != address(0), "ccm-chief-mdue-token-invalid");
        // can't change due token
        require(execParams[msg.sender].dueToken == address(0), "ccm-chief-mdue-already-set");
        // set due
        execParams[msg.sender].dueToken = dueToken;
    } 

    // Claim your payout
    // claim(), withdraw()
    function claim(address token, uint256 amt) external returns (bool) {
        return vault.give(token, msg.sender, amt);
    }

    // add an Asset to mamas
    // addExecAsset
    function addExecAsset(
        uint256 tax,   // interest rate charged on tab - .....   
        uint256 biteLimit,   // minimum collateralization ratio, as a ray
        uint256 biteFee,   // liquidation penalty, as a ray
        address token    // address of the token to add
    ) external returns (bool) {
        return _addAsset(tax, biteLimit, biteFee, token, address(0), true);        
    }

    // Add an Asset to a specific account
    // addAccountAsset
    function addAccountAsset(
        uint256 tax,   // interest rate charged on swapped collateral   
        uint256 biteLimit,   // minimum collateralization ratio, as a ray
        uint256 biteFee,   // liquidation penalty, as a ray
        address token,   // address of the token to add
        address user    // address of the holder / payer
    ) external returns (bool) {
        return _addAsset(tax, biteLimit, biteFee, token, user, false);
    }

    // Open an account
    function open(
        uint256 dueTab,   // Collateral amount, denominated in _due token
        uint256 callTime,
        address user,   // Address of the payer TODO: can't be msg.sender?
        address dueToken,   // Address of the token to pay out in
        bool    useExecParams    // If true, use contract-wide Asset Params. else, set below
    ) external nonReentrant returns (bool) {
        return _open(dueTab, callTime, user, dueToken, useExecParams);
    }
    // Open an account that will use mama params
    function open(
        uint256 dueTab, 
        uint256 callTime, 
        address user
    ) 
        external nonReentrant returns (bool) 
    {
        return _open(dueTab, callTime, user, address(0), true);
    }

    // toggle mama asset on and off
    // can't do this for an acct bc they have already agreed to the terms
    // _gem - which gem to toggle
    // toggleExecAsset()
    function toggleExecAsset(address token, bool use) external returns (bool) {
        if (execParams[msg.sender].tokens[token].biteLimit > RAY) {return false;}
        execParams[msg.sender].tokens[token].use = use;
        return true;
    }

    
    /////////////
    // External Getters
    /////////////
    // stack to deep error if return everything at once
    function accountUints(address exec, address user)
        external
        view
        returns (uint lastAccrual, uint dueTab, uint dueBalance, uint tradeBalance, uint callTime, uint callTab)
        // returns (uint, uint, uint, uint, uint, uint)
    {
        // Acct memory acct = accts[keccak256(abi.encodePacked(who, lad))];
        Account memory account = accounts[getHash(exec, user)];
        lastAccrual = account.lastAccrual;
        dueTab = account.dueTab;
        dueBalance = account.dueBalance;
        tradeBalance = account.tradeBalance;
        callTime = account.callTime;
        callTab = account.callTab;
        
        // State state = acct.state;
        // return (_era, _tab, _bal, _val, _zen, _ohm);
    }

    function accountState(address _exec, address _user) external view returns (State) {
        // return accts[keccak256(abi.encodePacked(who, lad))].state;
        return accounts[getHash(_exec, _user)].state;
    }

    function accountAddresses(address _exec, address _user)
        external
        view
        returns (address exec, address dueToken, address tradeToken)
    {
        // Acct memory acct = accts[keccak256(abi.encodePacked(_who, _lad))];
        Account memory account = accounts[getHash(_exec, _user)];
        exec = account.exec; // TODO: don't need this after testing
        dueToken = account.dueToken;
        tradeToken = account.tradeToken;
    }

    function accountBools(address _exec, address _user) 
        external
        view 
        returns (bool useExecParams, bool useAuction)
    {
        // Acct memory acct = accts[keccak256(abi.encodePacked(who, lad))];
        Account memory account = accounts[getHash(_exec, _user)];
        useExecParams = account.useExecParams;
        useAuction = account.useAuction;
    } 

    function pals(address _exec, address _user, address _pal) external view returns (bool) {
        // return accts[keccak256(abi.encodePacked(who, lad))].pals[pal];
        return accounts[getHash(_exec, _user)].pals[_pal];
    }

    ///////Math

    // Go from wad (10**18) to ray (10**27)
    function ray(uint256 wad) internal pure returns (uint) {
        return mul(wad, 10 ** 9);
    }

    // Go from wei to ray (10**27)
    // function weiToRay(uint _wei) internal pure returns (uint) {
    //     return mul(_wei, 10 ** 27);
    // } 

    // could make this public for ease of use?
    // accrueInterest(), accrue(), 
    function accrueInterest(uint principal, uint rate, uint age) internal pure returns (uint256) {
        return rmul(principal, rpow(rate, age));
    }

    // gethash(), getkeccak, getSha3
    function getHash(address _A, address _B) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_A, _B));
    }


    // Setters
    // modifier onlyScout(bytes32 pair) {
    //     require(msg.sender == pairs[pair].scout, "ccm-chief-auth"); 
    //     _;
    // }
    function file(bytes32 pair, bytes32 what, uint data) external note {
        require(msg.sender == tokenPairs[pair].spotter, "ccm-chief-auth");
        if (what == "spotPrice") tokenPairs[pair].spotPrice = data;
    }
    function file(bytes32 pair, bytes32 what, bool data) external note onlyOwner {
        if (what == "use") tokenPairs[pair].use = data;
    }
    function file(bytes32 pair, bytes32 what, address data) external note onlyOwner {
        if (what == "spotter") tokenPairs[pair].spotter = data;
    }
    function file(bytes32 what, uint data) external note onlyOwner {
        if (what == "maxTax") maxTax = data;
        if (what == "maxTab") maxTab = data;
        if (what == "minTab") minTab = data;
    }
    function file(bytes32 what, address data) external note onlyOwner {
        if (what == "vault") vault = Vault(data);
    }

    
    // function file(bytes32 ilk, bytes32 what, bool data) public 

    // scout, 
    // modifier onlySpotter(bytes32) {require(msg.sender==spotter, "ccm-auth"); _;}
    // function spot(address gem1, address gem2, uint256 val) public onlySpotter {

    // }
}