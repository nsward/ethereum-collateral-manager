pragma solidity ^0.5.3;

// import "./Vault.sol";
import "./Interfaces/VaultLike.sol";
import "./Interfaces/WrapperLike.sol";
import "../lib/DSMath.sol";
import "../lib/DSNote.sol";
import "../lib/LibOrder.sol";
// import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract Chief is Ownable, DSMath, DSNote, ReentrancyGuard {

    enum State{ Par, Call, Bit, Old }

    struct TokenPair {
        address spotter;    // fetches and sets the spot price
        uint spotPrice;     // Important note: does not incorporate mat like dai's spotter does
        bool use;           // approved for use 
        // spotPrice should be due tokens / 1 tradeToken
    }
    struct AssetClass {
        bool use;       // approved for use
        uint tax;       // interest rate paid on quantity of collateral not held in dueToken
        uint biteLimit; // Minimum Collateralization Ratio as a ray
        uint biteFee;   // liquidation penalty as a ray
        // add keeperReward, biteReward, bitePay? What do keepers get for biting? biteGap, biteSpread
    }
    // execParam, execPair, 
    struct AdminParam {
        address dueToken;                       // address of the ERC20 token to pay out in
        mapping (address => AssetClass) tokens; // tokenParams
    }
    struct Order {
        address wrapper;
        address makerAsset;
        address takerAsset;
        uint makerAmt;
        uint takerAmt;
        uint fillAmt;
        bytes orderData;
    }
    struct Account {
        // Set by managing contract
        uint    callTab;                        // tab due at end of call
        uint    dueTab;                         // max payout amt 
        uint    dueBalance;                     // balance of due tokens currently held, denominated in due tokens
        uint    callTime;                       // time given for a call 
        bool    useAdminParams;                  // use exec-contract-wide paramaters 
        address admin;                           // address of managing contract 
        address dueToken;                       // address of the ERC20 token to pay out in
        mapping (address => AssetClass) tokens; // tokens that can be held as collateral and the parameters

        // Set by user
        address user;                   // address of user / trader / payer
        uint    allowance;              // must be set by user before open(). Prevents malicious
                                        // contract from taking token allowances made to this contract
        uint    tradeBalance;           // trading token balance. denominated in the trading token
        address tradeToken;             // trading token currently held
        Order   safeOrder;              // default order to take if called
        mapping (address => bool) pals; // approved to handle trader's account

        State state;   
        uint  lastAccrual;              // Time of last interest accrual
    }

    // TODO: set these values
    uint256 public accountId;               // Incremented for keepers to find accounts
    // TODO: should be able to have a tab below this, but unable to trade due token 
    // for other tokens, bc the only danger of having a small amt in the acct is
    // getting keepers to bite it
    uint256 public minTab = 0.005 ether;    // not profitable for keepers to bite below this. TODO: this is just based on the dai cdp minimum. Need to determine what this should be
    uint256 public maxTax = uint(-1);       // maximum interest rate
    //uint256 public maxTab = uint(-1);     // tab above which keepers can bite
    
    
    mapping (address => AdminParam) public adminParams;   // Contract-wide Asset Paramaters
    // Only internal bc of compiler complaint about nested structs. Need to create getter
    mapping (bytes32 => Account) internal accounts;     // keccak256(exec, user) => Account
    mapping (bytes32 => TokenPair) public tokenPairs;   // keccak256(dueToken, tradeToken) => Token Pair
    mapping (uint256 => bytes32) public accountKeys;    // accountId => accountKey

    mapping (address => bool) public wrappers;  // valid exchange wrappers

    VaultLike public vault;     // Address of the vault contract that holds funds

    constructor(address _vault) public {
        vault = VaultLike(_vault);
    }

    // TODO: contract won't deploy under block gas limit with bytecode size
    // Potential structure:
    // Chief, Vat -> data source, auth - protected, logicless writes
    // User,  Broker  -> all user-facing functions, trader, debtor, payer
    // Exec,  Admin  -> all exec contract facing functions, controller
    // Keep,  Keeper  -> all keeper functions, keeper, monitor
    // Proxy -> same stuff
    // Vault -> same stuff 

    // How to handle reentrancy between contracts?
    // if sticking with reentrancy locks, one option would be to make the chief
    // external auth-restricted functions nonReentrant


    // swap
    // makerAmt and takerAmt give us the price the user intends to get, then
    // fill Amt gives us the amt of takerToken user wants to sell. We need to do
    // validations based on these values, update state, then pass these values
    // to the exchange wrapper, which must revert if the expected values are not
    // met (bc user could pass in diff values in orderData)
    // Also, verify our balances in each token afterwards and require(safe())
    function swap(
        bytes32 accountKey,
        address wrapper,
        address makerAsset,
        address takerAsset,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes calldata orderData
    )
        external nonReentrant returns (bool) 
    {
        // TODO: delete safeOrder

        // take an order, execute the trade, update balances, and check safe
        // we will always be taker

        // must be an approved wrapper
        require(wrappers[wrapper], "ccm-chief-swap-invalid-wrapper");

        // grab account
        Account storage account = accounts[accountKey];

        // get dueToken
        address dueToken = account.useAdminParams ?
            adminParams[account.admin].dueToken :
            account.dueToken;

        // TODO: might need to pull this into an internal / public function
        // to remove this require when called to take safeOrder
        // must be called by account user or authorized delegate
        require(
            msg.sender == account.user || account.pals[msg.sender],
            "ccm-chief-swap-unauthorized"
        );

        // update account tab
        _updateTab(account);

        // we are getting maker asset and losing takerAsset

        // cases:
        // - giving up due token, getting a new trade token
        // - giving up due token, getting more of our current trade token
        // - giving up trade token, getting due token
        // - giving up trade token, getting a new trade token

        uint partialAmt = getPartialAmt(makerAmt, takerAmt, fillAmt);

        // giving up due token
        if (takerAsset == dueToken) {
            if (makerAsset == account.tradeToken) {
                // giving up due token, getting more of our current trade token
                // update balances
                account.dueBalance = sub(account.dueBalance, fillAmt);
                account.tradeBalance = add(account.tradeBalance, partialAmt);
            } else {
                // giving up due token, getting a new trade token
                require(account.tradeBalance == 0, "ccm-chief-swap-tradeToken-exists");
                bool use = account.useAdminParams ?
                    adminParams[account.admin].tokens[makerAsset].use :
                    account.tokens[makerAsset].use;
                require(use, "ccm-chief-swap-new-tradeToken-invalid-1");
                account.dueBalance = sub(account.dueBalance, fillAmt);
                account.tradeToken = makerAsset;
                account.tradeBalance = partialAmt;
            }
        } else {
            require(takerAsset == account.tradeToken, "ccm-chief-swap-invalid-trading-pair");
            // giving up trade token

            if (makerAsset == account.dueToken) {
                // giving up trade token, getting due token
                account.tradeBalance = sub(account.tradeBalance, fillAmt);
                account.dueBalance = add(account.dueBalance, partialAmt);
            } else {
                // giving up trade token, getting a new trade token

                // require new token approved
                bool use = account.useAdminParams ?
                    adminParams[account.admin].tokens[makerAsset].use :
                    account.tokens[makerAsset].use;
                require(use, "ccm-chief-swap-new-tradeToken-invalid-2");

                // make sure we can cover the fillAmt. This is check by the DSMath sub()
                // in every other case, but we must be explicit about it here
                require(account.tradeBalance >= fillAmt, "ccm-chief-swap-insufficient-tradeBalance");

                // figure out how to handle excess current tradeToken
                // if fillAmt < tradeBalance -> we'll have some left over. Can we just add this to claims? or should we not allow this?
                if (account.tradeBalance > fillAmt) {
                    // add difference to claims
                    vault.addClaim(
                        account.tradeToken, 
                        account.user, 
                        sub(account.tradeBalance, fillAmt)
                    );
                }

                account.tradeToken = makerAsset;
                account.tradeBalance = partialAmt;
            }
        }

        // make sure the account is still safe
        require(safe(accountKey), "ccm-chief-swap-resulting-position-unsafe");

        _executeTrade(
            msg.sender, 
            wrapper, 
            makerAsset, 
            takerAsset, 
            makerAmt, 
            takerAmt, 
            fillAmt, 
            orderData
        );
    }


    // function validateTrade() internal pure {}
    // function updatePosition(Account storage account, ) internal {}

    // reverts on failure
    function _executeTrade(
        address wrapper,
        address tradeOrigin,
        address makerAsset,
        address takerAsset,
        uint makerAmt,
        uint takerAmt,
        uint fillAmt,
        bytes memory orderData
    )
        internal
    {
        // transfer funds to wrapper
        vault.giveToWrapper(takerAsset, wrapper, fillAmt);

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
            "ccm-chief-executeTrade-fillOrKill-unsuccessful"
        );

        // transfer from exchange wrapper back to vault
        // ** will need to make sure wrappers are all approving() sufficient amounts
        vault.takeFromWrapper(
            makerAsset, 
            wrapper,
            makerAmtReceived
        );
    }

    // Returns the value of a partial fill given an implied price (makerAmt / takerAmt)
    // and the fill amt
    function getPartialAmt(uint makerAmt, uint takerAmt, uint fillAmt) 
        internal 
        pure 
        returns (uint) 
    {
        // TODO: DSMath does not include a div function because solidity
        // errors on div by 0. But, it doesn't revert, so leave this check
        // for now
        require(takerAmt > 0, "ccm-chief-getPartialAmt-div-by-zero");
        return mul(makerAmt, fillAmt) / takerAmt;
    }


    function _updateTab(Account storage account) internal {
        // Account storage account = accounts[accountKey];

        // no time passed since last update
        if (account.lastAccrual == now) { return; }

        // no tax accrued
        if (account.dueBalance >= account.dueTab) { 
            account.lastAccrual = now; 
            return;
        }
        
        // get tax for the trade token
        uint tax = account.useAdminParams ?
            adminParams[account.admin].tokens[account.dueToken].tax :
            account.tokens[account.dueToken].tax;

        account.dueTab = accrueInterest(
            sub(account.dueTab, account.dueBalance),
            tax,
            sub(now, account.lastAccrual)
        );

        account.lastAccrual = now;
    }

    function updateTab(bytes32 accountKey) public {
        Account storage account = accounts[accountKey];
        return _updateTab(account);
    }
    
    // return callTime or callTime + now?
    function callAccount(address user) external returns (uint) {}


    // called by the managing contract
    // if _mom == true, _due should be 0
    function _open(
        uint256 dueTab,         // collateral amt, denominated in dueToken
        uint256 callTime,       // time allowed after a call
        address user,           // address of the payer TODO: can't be msg.sender?
        address dueToken,       // address of the token to pay out in
        bool    useAdminParams  // if true, use exec asset params. else, set below
    ) 
        private returns (bool) 
    {
        // Account user can't be zero
        require(user != address(0), "ccm-chief-open-lad-invalid");

        // TODO: Should we require the manager to be a contract? To prevent people unaware
        // that an EOA would be able to take all their funds? -- this wouldn't really stop
        // them, bc they could just make a contract with auth functions that do basically the same thing
        
        // Payout token can't be 0 unless mama params being used. 
        // NOTE: No checks on whether dueToke has any tradeToken matches
        if (useAdminParams) {
            require(
                adminParams[msg.sender].dueToken != address(0), 
                "ccm-chief-open-mama-due-invalid"
            );
        } else {
            require(dueToken != address(0), "ccm-chief-open-due-invalid");
        }

        // Check that owed amt is valid
        require(dueTab > minTab, "ccm-chief-open-tab-invalid");
        // Grab the account
        bytes32 accountKey = getHash(msg.sender, user); 
        Account storage account = accounts[accountKey];
        // Check that account doesn't exist already. TODO: check who too?
        require(account.lastAccrual == 0, "ccm-chief-open-account-exists");
        // Check that exec contract is allowed to take funds from user
        require(account.allowance >= dueTab, "ccm-chief-open-insufficient-allowance");
        // Add id to accountKeys and increment acctId
        accountKeys[accountId] = accountKey;
        accountId = add(accountId, 1); 
        // Initialize the account
        account.admin = msg.sender;
        account.dueTab = dueTab;
        account.useAdminParams = useAdminParams;
        account.callTime = callTime;
        account.lastAccrual = now;
        if (!useAdminParams) {account.dueToken = dueToken;}

        require(vault.take(dueToken, user, dueTab), "ccm-chief-open-take-failed");
        // TODO
        account.dueBalance = dueTab;
        account.allowance = sub(account.allowance, dueTab);

        return true;       
    }

    // add new Asset to execParams or account
    function _addAsset(
        uint256 tax,   // interest rate charged on swapped collateral   
        uint256 biteLimit,   // minimum collateralization ratio, as a ray
        uint256 biteFee,   // liquidation penalty, as a ray
        address token,   // address of the token to add
        address user,   // address of the holder / payer
        bool    useAdminParams    // set this to contract-wide params?
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
        if (useAdminParams) { 
            dueToken = adminParams[msg.sender].dueToken;
            asset = adminParams[msg.sender].tokens[token]; 
        } else {
             // Check that account exists 
            key = getHash(msg.sender, user);
            require(accounts[key].lastAccrual > 0, "ccm-chief-ngem-acct-nonexistant");
            // Check that account is not using the mom params (waste of gas and
            // deceptive to the contract to set params that aren't used)
            require(!accounts[key].useAdminParams, "ccm-chief-ngem-acct-uses-mom");
            dueToken = accounts[key].dueToken;
            asset = accounts[key].tokens[token];
        }

        // trade token must be an approved token pair with due
        require(tokenPairs[getHash(dueToken, token)].use, "ccm-chief-ngem-token-pair-invalid");

        // prevents editing params after setting use to false. 
        // TODO: Make sure there's no way around this
        // Also, does just checking mat work?
        // require(!mama.use && mama.mat > 0, "collateral-vault-mama-gem-in-use");
        require(asset.biteLimit == 0, "ccm-chief-ngem-gem-in-use"); // TODO

        asset.use = true;
        asset.tax = tax;
        asset.biteLimit = biteLimit;
        asset.biteFee = biteFee;


        if(useAdminParams) {adminParams[msg.sender].tokens[token] = asset;}
        else {accounts[key].tokens[token] = asset;}

        return true; 
    }


    /////////////
    // External Functions
    ////////////

    // Sets account allowance, can only be called by the user of the account
    // or an approved pal. Prevents an attack where anyone could monitor the
    // approval events from popular ERC20s waiting for approvals to this contract,
    // then call open() from a malicious contract and effectively steal all
    // approved funds 
    function setAllowance(address admin, address user, uint allowance) external returns (bool) {
        bytes32 accountKey = getHash(admin, user);
        require(
            msg.sender == user ||
            accounts[accountKey].pals[msg.sender],
            "ccm-chief-approve-unauthorized"
        );

        accounts[accountKey].allowance = allowance;
    }

    // TODO: add user param to allow pals to call
    // TODO: takeAddress is unsafe because anyone can add a take address
    // that has an unlimited approval for this contract
    // TODO: allowance
    function lock(
        bytes32 accountKey,
        address token, 
        uint256 amt
    ) 
        external nonReentrant returns (bool) 
    {    
        require(token != address(0) && amt > 0, "ccm-chief-lock-invalid-inputs");

        Account storage account = accounts[accountKey];

        // TODO: need this?
        // require(
        //     msg.sender == account.user ||
        //     account.pals[msg.sender],
        //     "ccm-chief-lock-unauthorized"
        // );

        address dueToken;
        bool use;

        if (account.useAdminParams) {                // use exec params
            address admin = account.admin;
            dueToken = adminParams[admin].dueToken;
            use = adminParams[admin].tokens[token].use;
        } else {                                    // use acct params
            dueToken = account.dueToken;
            use = account.tokens[token].use;
        }

        if (token == dueToken) {                    // topping up due token
            require(vault.take(token, msg.sender, amt), "ccm-chief-lock-transfer-failed");
            account.dueBalance = add(account.dueBalance, amt);
            return true;
        } 
        else if (token == account.tradeToken) {          // topping up trade token
            require(vault.take(token, msg.sender, amt)); 
            account.tradeBalance = add(account.tradeBalance, amt);
            return true;
        }
        else if (account.tradeToken == address(0)) {     // adding a new trade token
            require(use, "ccm-chief-lock-gem-not-approved");
            assert(account.tradeBalance == 0);  //TODO: require() here?
            require(vault.take(token, msg.sender, amt), "ccm-chief-lock-transfer-failed");
            account.tradeToken = token;
            account.tradeBalance = amt;
            return true;
        } else {
            revert("ccm-chief-lock-invalid-token");
        }

        // revert("ccm-chief-lock-invalid-token");
        // return false;   // user submitted an invalid _gem address. revert here?
    }

    // toggle approved acct managers
    function togglePal(bytes32 accountKey, address pal, bool trusted) external returns (bool) {
        require(msg.sender == accounts[accountKey].user, "ccm-chief-togglePal-unauthorized");
        accounts[accountKey].pals[pal] = trusted;
        return true;    // Note: returns true on sucess, not the new pals[pal] value
    }

    // Set the contract-wide due token
    function setAdminDueToken(address dueToken) external returns (bool) {
        // dueToken can't be zero
        require(dueToken != address(0), "ccm-chief-mdue-token-invalid");
        // can't change due token
        require(adminParams[msg.sender].dueToken == address(0), "ccm-chief-mdue-already-set");
        // set due
        adminParams[msg.sender].dueToken = dueToken;
    } 

    // Claim your payout
    function claim(address token, uint256 amt) external nonReentrant returns (bool) {
        return vault.give(token, msg.sender, amt);
    }

    // add an asset to exec params
    function addAdminAsset(
        uint256 tax,        // interest rate charged on swapped collateral  
        uint256 biteLimit,  // minimum collateralization ratio, as a ray
        uint256 biteFee,    // liquidation penalty, as a ray
        address token       // address of the token to add
    ) external returns (bool) {
        return _addAsset(tax, biteLimit, biteFee, token, address(0), true);        
    }

    // Add an Asset to a specific account
    function addAccountAsset(
        uint256 tax,        // interest rate charged on swapped collateral   
        uint256 biteLimit,  // minimum collateralization ratio, as a ray
        uint256 biteFee,    // liquidation penalty, as a ray
        address token,      // address of the token to add
        address user        // address of the holder / payer of account
    ) external returns (bool) {
        return _addAsset(tax, biteLimit, biteFee, token, user, false);
    }

    // Open an account
    function open(
        uint256 dueTab,
        uint256 callTime,
        address user,
        address dueToken,
        bool useAdminParams
    ) external nonReentrant returns (bool) {
        return _open(dueTab, callTime, user, dueToken, useAdminParams);
    }
    // Open an account that will use exec params
    function open(
        uint256 dueTab, 
        uint256 callTime, 
        address user
    ) 
        external nonReentrant returns (bool) 
    {
        return _open(dueTab, callTime, user, address(0), true);
    }

    // can't do this for an acct bc they have already agreed to the terms
    function toggleAdminAsset(address token, bool use) external returns (bool) {
        if (adminParams[msg.sender].tokens[token].biteLimit > RAY) {return false;}
        adminParams[msg.sender].tokens[token].use = use;
        return true;
    }


    function safe(bytes32 accountKey) public view returns (bool) {
        Account memory account = accounts[accountKey];
        AssetClass memory asset = accounts[accountKey].tokens[account.tradeToken];

        // if the due amount is held in due token, then account is safe
        // regardless of biteLimit or interest charged
        if (account.dueBalance >= account.dueTab) {
            return true;
        } else {
            uint debit = rmul(
                accrueInterest(
                    sub(account.dueTab, account.dueBalance),    // charge interest on amt not held in dueToken
                    asset.tax, 
                    sub(now, account.lastAccrual)
                ), 
                asset.biteLimit
            );

            uint val = tokenPairs[getHash(account.dueToken, account.tradeToken)].spotPrice;
            uint credit = add(account.dueBalance, mul(account.tradeBalance, val));    // wmul()?

            return credit >= debit;
        }
    }

    /////////////
    // External Getters
    /////////////
    // stack to deep error if return everything at once
    function accountUints(address admin, address user)
        external
        view
        returns (uint lastAccrual, uint dueTab, uint dueBalance, uint tradeBalance, uint callTime, uint callTab)
    {
        Account memory account = accounts[getHash(admin, user)];
        lastAccrual = account.lastAccrual;
        dueTab = account.dueTab;
        dueBalance = account.dueBalance;
        tradeBalance = account.tradeBalance;
        callTime = account.callTime;
        callTab = account.callTab;
    }

    function accountState(address _admin, address _user) external view returns (State) {
        return accounts[getHash(_admin, _user)].state;
    }

    function accountAddresses(address _admin, address _user)
        external
        view
        returns (address admin, address dueToken, address tradeToken)
    {
        Account memory account = accounts[getHash(_admin, _user)];
        admin = account.admin;
        dueToken = account.dueToken;
        tradeToken = account.tradeToken;
    }

    function accountBools(address _admin, address _user) 
        external
        view 
        returns (bool useAdminParams)
    {
        Account memory account = accounts[getHash(_admin, _user)];
        useAdminParams = account.useAdminParams;
        // useAuction = account.useAuction;
    } 

    function accountAsset(address _admin, address _user, address _token) 
        external
        view
        returns(bool use, uint tax, uint biteLimit, uint biteFee) 
    {
        AssetClass memory asset = accounts[getHash(_admin, _user)].tokens[_token];
        use = asset.use;
        tax = asset.tax;
        biteLimit = asset.biteLimit;
        biteFee = asset.biteFee;
    }

    function pals(address _admin, address _user, address _pal) external view returns (bool) {
        return accounts[getHash(_admin, _user)].pals[_pal];
    }

    // Go from wad (10**18) to ray (10**27)
    function ray(uint256 wad) internal pure returns (uint) {
        return mul(wad, 10 ** 9);
    }

    // Go from wei to ray (10**27)
    // function weiToRay(uint _wei) internal pure returns (uint) {
    //     return mul(_wei, 10 ** 27);
    // } 

    // could make this public for ease of use?
    function accrueInterest(uint principal, uint rate, uint age) internal pure returns (uint256) {
        return rmul(principal, rpow(rate, age));
    }

    function getHash(address _A, address _B) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_A, _B));
    }

    //////////
    // Authorized Setters
    //////////
    modifier onlySpotter(bytes32 pair) {
        require(msg.sender == tokenPairs[pair].spotter, "ccm-chief-auth"); 
        _;
    }
    function file(bytes32 id, bytes32 what, uint data) external note onlySpotter(id) {
        //require(msg.sender == tokenPairs[pair].spotter, "ccm-chief-auth");
        if (what == "spotPrice") tokenPairs[id].spotPrice = data;
    }
    function file(bytes32 id, bytes32 what, bool data) external note onlyOwner {
        if (what == "use") tokenPairs[id].use = data;
    }
    function file(bytes32 id, bytes32 what, address data) external note onlyOwner {
        if (what == "spotter") tokenPairs[id].spotter = data;
    }
    function file(bytes32 what, uint data) external note onlyOwner {
        if (what == "maxTax") maxTax = data;
        //if (what == "maxTab") maxTab = data;
        if (what == "minTab") minTab = data;
    }
    function file(bytes32 what, address data) external note onlyOwner {
        if (what == "vault") vault = VaultLike(data);
        if (what == "wrapper") wrappers[data] = !wrappers[data];
    }
    

}


// State altering functions
////// Managing Contract Functions:
// openWithEth()?       -- exec can forward msg.value and we'll wrap it and store it
// open()               - open an account, called by exec contract, implemented
// setExecDueToken()    - add initial due to execParams, implemented
// addExecAsset()       - add an Asset to execParams, implemented
// addAcountAsset()     - add an Asset to specific acct, implemented
// toggleExecAsset()    - disable a gem in execParams for future users, implemented
//              - X disable a gem for specific acct as long as not currently held
// move()               - pay out to specified address
// call(amt)            - call user's account to start callTime
// close()/settle()?    - set tab = 0, either leave user balance or transfer it to claim() balances
//
////// User Functions:
// lock()           - add either gem or due tokens, implemented
// free()           - claim either gem or due tokens, as long as it stays safe
// setSafeOrder()
// cancelSafeOrder()?
// togglePal()      - approve/unapprove a pal, implemented
// trade()          - use 0x order to trade due or gem for new gem, as long as it stays safe. Also, delete jet
// claim()          - calls Vault.give(), pays out users, implemented   
//
////// Keeper Functions:
// accountId()      - implemented
// accountKeys()    - implemented
// bite()
//
////// Vault Functions:
// take()           - transfers tokens from user to vault
// give()           - transfers tokens from vault to user
// addClaim()       - updates a user's pull balance
//
////// Proxy Functions:
// deal()           - transfers tokens
//
////// Auction Functions:
//
////// Intermediate Functions:
// safe()