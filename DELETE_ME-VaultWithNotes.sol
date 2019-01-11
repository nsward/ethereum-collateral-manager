pragma solidity ^0.4.24;

// TODO: SHIT NEEDS TO RUN IN CONSTANT TIME / GAS COST

// pairs
    // accts
    // mamas
    // accti
    // radar
    
    // track
    // radar
    // paths
    // trail
    // rails
    // tails
    // bills
// TODO: how can keepers (and everyone else) find this?
    //  - store managing contract address in Account
    //  address mom will either be 0 (set account-specific params) or the
    //  address of the managing contract, which will be the key in moms mapping
    mapping (address => Gem) mamas;

    // Option B is to store mapping(accountIds => struct) where the struct contains the two addresses
    // increment account ids and store hash(managing_contract, user) in accountIds mapping
    uint accti; // For keepers to find accounts
    mapping (uint => bytes32) radar;   // For keepers to find accounts
    // mapping (address => mapping(address => Account)) public accounts;
    mapping (bytes32 => Account) public accts;


// TODO: Dai purple paper defines wad as 18decimal precision and ray as 36 decimal precision.
// did ray change?

// TODO: look up counterparty risk and ... (risk of missing out on a better opportunity)
// Is there a situation where a managing contract would want to pay the interest to one
// party and the owedAmt to another? If so, is there an easy way for them to implement currently
// or should we take an interestAddr too? onERC20 receipt?
// -- return totalPaid from the payout() function, then contracts that want to 
// manage interest separately can call 
// uint total = CollateralBank(payAmt);
// uint interest = total - payAmt;
// -- Also, provide an interest on X amt public pure function, b/c contracts are likely
//  going to want to alter any state (such as paymentChannel.owedInterest) before calling
//  a state-altering function outside of their contract

// How to manage interest when multiple payments are going out and/or the trader
// holds 100% of owedAmt in owedToken?
// One option is to store a running tally of interest time and last block from which
// to calc interest. So anytime there was 100% of owedAmt in owedToken, no interest would
// accrue. Also could just make interest a constant thing 


import "./openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "../lib/Interest.sol";
// import "./openzeppelin-solidity/contracts/ownership/Ownable.sol";

// ** hard code external contract address so that everyone knows you did not maliciously
// use incorrect adresses in the constructor

// Basic version: automatically transfers any funds to a dai interest gaining acccount
// Allows contract to either inherit the functionality, or use this contract as it's store of funds
// (inheritance is probably prefereable as it would reduce the 'honeypot effect')
// Additionally, it could use a design pattern similar to dydx's margin trading (submitting
// a buy/sell order from any DEX triggers the taking of that order) to allow users to 
// 'invest' their stored funds in any ERC20 token. Would only work with ERC20's (and maybe
// only approved ERC20's) so would have to use WETH. Other user or the contract itself could
// margin call the user.
// Actually, the Dai Savings Rate thing differs significantly from the 'investment'
// idea. Maybe it would be an extension i.e. if the user decided to 'invest' their
// funds in the contract in Dai, then it would automatically be put in savings mode
// to accrue the DSR.



contract CollateralVault is Interest {

    // dexo
    struct Order {

    }


    // type, caste, asset
    // rule, param, kind, Pack, Club, Laws, Clan
    // mug, jug, can, jar
    struct Account {
        // pal, who, bud
        address owedAddr;   // Address to payout to. Can be the managing contract
        // owe, due, gem
        address owedToken;  // Address of the ERC20 token to pay out in
        // tab
        uint owedAmt; // Max payout amt 
        // mat
        uint mcr;   // Minimum Collateralization Ratio MCR, mat in dai-speak
        // fee, or tax?
        uint rate;
        // rho, age
        uint lastAccrual;    // Time of last interest update. Every time an interest
        // own, mug, somethings about this being the drink, ale, joe, gem, pot/pan, bin/bag
        // this is what refers to the mug with the fee, mat, yes - refers to the object
        address heldToken;
        // bal, val, ?, amount of 
        uint heldTokenBalance;
// bag, sac, 
        // could make heldToken = gem, owedToken = due (bc more similar to dai)
        
        // bed, net, ?
        // TODO: how do we actually store this?
        uint defaultOrder;

        // owns? gems?
        mapping (address => bool) menu; 
        // mapping (address => uint) balances; // Holder's token balances

        mapping(address => mug) mugs;

        uint axe;   // also win
        
    }
    //gem_specs, gem_type, gem_rules, GemLaw
    // gem => gemParams gems if gem ~ dai gem
    // asset, token, class, trade, position, 
    // commodity
    // ore
    // coin, token, collateral, 
    // col
    // pod
    // tea pot
    // item choice 
    // ties
    // bev
    // sip
    // Tea
    // different things you can put in your jug
    // holds risk parameters for each holding
    // Ilk
    struct Mug {
        bool yes; // use?, aye, appproved
        uint fee;
        uint mat;
    }




contract CollateralVault is Interest {
    
    // Let's do this in the context of a simple 1 to 1 escrow for now
    // But, the inheriting contract will be in charge of handling the
    // logic of when to pay out, transfer funds to a participant, etc.

    // Only working with OasisDex at first

    // ***** External Keepers
    // This makes the contract applicable to the general case. Instead of
    // every contract inheriting the Bank logic, every contract actually 
    // stores their funds in the Bank. Each individual contract can handle
    // the buy/sell 'investments' of it's user's funds in the contract,
    // but external keepers patrol every position in the contract and make sure
    // that it stays above the collateralization ratio (say, 150% of payout).
    // If a keeper sees that the price of the heldToken on all markets has
    // dropped such that a collateral position has fallen to 140% of payoutAmt 
    // (denominated in payoutToken), the keeper margin calls the position.
    // If the holder of the position submits a buy order for > 150% of payoutAmt
    // before the end of the margin call period (say, 24 hrs.), this means that
    // either the market for the heldToken has gone back up or the keeper made
    // a 'false' margin call, so the keeper is penalized by taking some
    // portion of their stake 
    // On the other hand, if the holder submits a buy order for < 150% of
    // payoutAmt, or doesn't submit one at all -- in which case either a keeper
    // or the counterparty (via the o.g. escrow contract) can submit one (both
    // would be incentivized to submit a buy order >= payoutAmt). If the ultimately
    // submitted buy order is > payoutAmt and < 1.5 * payoutAmt, the keeper (or
    // whoever called the margin, b/c recipients would be incentivized to stake
    // and become a keeper for their own channel) is awarded either the difference
    // between the payoutAmt and the collateral amt, or some other pre-determined
    // amt. TODO: how would this work if someone decided to top up their collateral
    // position -- would they have to pay keeper some amount?

    // TODO: what happens to the stakes taken from the keepers? -- maybe goes
    // toward paying out for late margin calls, i.e. if the channel becomes
    // undercollateralized than up to payoutAmt can be paid out from this
    // confiscated keeper-stake fund

    // Give some interest to the counterparty for allowing you to use the
    // bank, which adds obvious risk over a simple stake of collateral?


    // ** This is actually pretty interesting. If you had an on-chain matching
    // market with enough liquidity that automatically matched new orders to 
    // existing orders, then you would be able to use submitted buy orders as
    // a "market price", because in order to submit a fake order, it would
    // have to not satisfy any existing orders on the dex. i.e. Tim can't 
    // try to tell this contract that the market price of xcoin is 10 ether if
    // it's actually 1 ether, b/c someone else would immediately fill his order

    // TODO: make sure the holder of the token is not incentivized to buy 
    // their own token, thus automatically penalizing the keeper and 
    // disincentivizing keepers from margin calling.
    // One way to do this would be to allow only on-chain orders, which would
    // force the backer of that order to 'put their money where there mouth is'
    // and a fake order to buy your own tokens at significantly more than market
    // value would run the risk of someone else taking you up on the order before
    // you can buy your own tokens. But, you could probably do the two things atomically
    // via a proxy contract? which would negate the risk of selling your tokens to
    // someone else at a bad price, but what would your gain be?
    // Options:
    // - Could use an oracle to determine validity of margin call?
    // - No disincentive for a bad margin call or incentive for a valid margin
    // call. This would mean only the counterparty would be incentivized to
    // margin call a position, complicating things for the general case
    // i.e. many to many collateral situations like Augur
    // - Need to make it so that there is no difference in incentives for
    // the holder of the position. So, if a keeper margin calls a position,
    // the holder can not gain (or lose less) by submitting a fake order
    // and taking the other end of their own trade that makes it look as
    // if a bad margin call was made

    // TODO --> does this also solve the problem of fake orders in a matching
    // margin market?

    // Things you should be able to invest in:
    // - DSR

    // TODO: this needs to be extended because contracts will be depositing
    // funds in many different forms (Dai, Weth, etc.)
    // Track the balance that each contract deposits for each user
    // contract address => user address => balance

    // struct position {
    //     bool approved;
    //     uint balance;
    // }

    // How does DyDx's dutch auction work on the blockchain? If I'm willing to pay
    // x amount for assets ( x > y), can't I just wait as the price falls below x
    // until I see someone else submit a tx for y, then front-run their trade and buy
    // the assets for y?

    // TODO:
    // test the gas options for different organization of this struct/structs

    // TODO: Need to set a max owed amt, because after a certain point the account
    // balance will be overflowed and everything will fail?

    struct Account {
        // uint[] balances;
        
        // address owedAddr;   // Address to payout to. Can be the managing contract
        // Could also get rid of this and allow the managing contract to say who
        // to pay out to so that this contract just holds a total owed amt and the
        // managing contract can deal with whats owed to who without needing a double
        // transfer every time
        // owed_gem, tab_gem, tab_token
        // gem = collateral token
        address owedToken;  // Address of the ERC20 token to pay out in
        uint owedAmt; // Max payout amt 
        // tab?
        
        //uint collatRatio;   // ** Must be > 1, also stored as a ray w/ 1+ratio (150% collat -> wadToRay(1.5 ether))
                             // TODO: should this be a global constant? a per-contract constant?
                            // How does this impact keepers and channel participants?
                            // liquidation_limit, liquidation_ratio
        uint mcr;   // Minimum Collateralization Ratio MCR, mat in dai-speak

        //uint interestRate;   // stored as a ray, 1 + int_rate_per_second
        // "A royalty is a payment made by one party, the licensee or franchisee to another that owns a particular asset, the licensor or franchisor for the right to ongoing use of that asset. "
        // equivalent to rhi? in dai-speak, or way? is the holder fee
        uint rate;

        // lastAccrual, accruedInt, cashFlows, period

        // termStart, born
        // uint lastInterestUpdate;
        // Can be uint128?
        // rho is dai time of last drip, or tau? time of last prod
        // last_tally
        // Do we need to update the tab at all, or is it cheaper just to calculate
        // it every time? XX Nope. We need this to track interest when the amount
        // of gem that interest is charged on changes (tab - total balance denominated in gem)
        uint lastAccrual;    // Time of last interest update. Every time an interest
                            // update is prompted or postions in the account are moved, the
                            // time and accruedInterest will be updated based on the
                            // amt of owedToken outstanding below owedAmt
        // uint accruedInterest; , accruedAmt
        // uint accrued;   // Total accrued interest from position open to lastAccrual;
            // Might not even need this, could just add to owedAmt

        // I don't think owed_token needs to be in here
        // positions ?
        // address[] held_tokens;   // Makes positions enumerable
        //address[] positions;    // ** see ERC721 enumerable for useful dynamic array methods

        //address[] liquidation_order;    // Optional, only set by trader.

        address heldToken;

        // TODO: how do we actually store this?
        uint defaultOrder;

        // does owedToken need to be on the menu?
        mapping (address => bool) menu; // These must all be an approved token
                                                // pair with payoutToken, as determined
                                                // by the globallyApprovedTokenPairs

        // total balance is analogous to dai's ink
        // Cheaper to store balances or just query token contracts over and over?
        mapping (address => uint) balances; // Holder's token balances
        // mapping (address => Position) positions;

        // add an approved addresses options? to have someone manage your shit

        bool useContractGlobalParams; // in case the managing contract wants to
            // override a contractGlobalParam with 0, this can be set to true
            // and we will check contract globals, we'll just use zeroes
            // (reverse logic so it doesn't have to be set every time)
            // TODO: reverse logic only saves about 118 gas (for no set)
            // - 180 gas (for setting to false) from just setting
            // to true most times. So make this straight up (i.e. true 
            // is do use, false is dont)

    }

    // called by the managing contract
    function open(
        address _holder, 
        address _owedToken, 
        uint _owedAmt,
        uint _rate,
        uint _mcr,           // Minimum collateralization ratio, as a ray
        bool useContractGlobalParams,
        address[] _menu
    )
        public returns (bool) 
    {
        // Check that account doesn't exist
        require(accounts[msg.sender][_holder].mcr == 0 && accounts[msg.sender][holder].useContractGlobalParams == false, "collateral-vault-open-account-exists");
        
        // Owed token cannot be 0
        require(_owedToken != address(0), "collateral-vault-open-owed-token-invalid");

        // Check validity of mcr
        // TODO: how much greater does this need to be?
        // TODO; I think the reason dai's 13% is 1.13ether is bc they already added RAY
        // but see if they're subtracting that 1 before using the value
        require(mcr > add(RAY, axe), "collateral-vault-open-mcr-invalid");

        // Check that interest < max
        require(rate < usury, "collateral-vault-open-rate-invalid");

        // Check that owed_amt under limit
        require(owed_amt < cap, "collateral-vault-open-owed-amt-invalid");

        // TODO: Is this safe? unbounded loop sketches me out, but if it fails,
        // nothing bad happens?
        // TODO: If no approved tokens submitted, will menu be an empty array?
        for (uint i = 0; i < menu.length; i++) {
            // hash menu and owed token, make sure it's in token_pairs
            // TODO: does the order of this matter? Will we ever have a token
            // pair that only works one way? If not, do we need to set and check 
            // both orders in the hash? Is there a better way than that?
            // -> Yes, this can be one way. I never need to sell my owed_token
            // for the held_token, only ever sell held_token for owed_token.
            // So, there could be a situation where a market is very one-sided
            // bytes32 pair = keccak256(abi.encodePacked(owed_token, menu[i]));
            // Should token_pairs just be address => adress??
                // From maker_otc matching market. Means I should use double mapping
                // if sticking with one-way approvals
    // modifier isWhitelist(ERC20 buy_gem, ERC20 pay_gem) {
    //     require(_menu[keccak256(buy_gem, pay_gem)] || _menu[keccak256(pay_gem, buy_gem)]);
    //     _;
    // }
            // require(
            //     token_pairs[keccak256(abi.encodePacked(owed_token, menu[i]))], 
            //     "collateral-vault-open-menu-invalid"
            // );
            require(token_pairs[owed_token][menu[i]], "collateral-vault-open-menu-invalid");

            // add menu[i] to the account menu
        }

        // Confirm that the position is safe before finalizing
        // Can owedAmt be 0? and then could just be topped up later?
        // Check that approvedTokens < max number of approved tokens
        // Check that each approved token is an approved pair with owedToken
        // regardless of how many _approvedTokens, initialize approvedTokens[](maxHeldTokens) ? -> So they can always add to them
        // check that interest < maxInterest
        // check that 1 < collatRatio < maxCollatRatio
        // Also, collatRatio needs to be > 1 + liquidationPenalty;
        // transfer owedAmt of tokens from holderAddr to this contract
        // Return true on success
        // This function should always end with exactly 100% of owedAmt held in owedToken, and no other positions

        // TODO: need to implement some method of 'not at risk of liquidation'
        //  most likely: as long as owedAmt held in owedToken, nothing else matters, position is safe

        // Note that no matter how many different channels a user has open with
        // a managing contract, it is all stored within one 'account' here. Therefore,
        // the managing contract might have to manage payouts in another way
    }

    // TODO: traders should be able to deposit a token other than owedToken, as long
    // as it is an approved token pair with owedToken

    // function names:
    // lock - called by holder (lad), add collateral to position - new collateral is accepted
        // in any token on the menu (or tab token / gem) as long as it does not make the position unsafe
        // (i.e. if I have only tab amt of gem in account, i can't put in a non-gem token that doesn't
        // get me above the mcr / mat)
        // lock used to deposit owed token would be more like dai's wipe
    // free - withdraw excess collateral up to safe point (safe point refers to any point where
        // total balance > tab denominated in gem, or there is 100% of tab held in gem)
    // safe - determine if account / cup is safe


    // allow managing contract to add more to required collateral, but must also include a
    // successful transfer of said collateral increase ?
    function top() public {}

    // Just Dai and Weth for now
    // uint public max_held_tokens = 2; // fill, plate, position_limit, max_positions 
    //uint public max_positions = 1;  // 1 if the owed_token doesn't count
    // Do we even need this? Shouldn't this be automatically enforced by token_pairs?
    // stairs? bc max number of positions that can add up to the cap
    uint max_positions_count; // We need this to limit the length of the posiitions[]
    // array. If we are going to iterate through it every time a liquidation occurs, then
    // there needs to be a guarantee that we aren't hitting out of gas or block gas limits.
    // Also, the idea of iterating through a potentially unbounded array complicates things a lot
    // for managing contracts. We need to prevent a trader from holding lots of small
    // positions to make liquidations super expensive

    uint public menuCap;

    // prevent: https://github.com/livnev/auction-grinding/blob/master/grinding.pdf
    // ^^^ also has some info on setting the penalty
    // Stored as ray. 13% penalty -> wadToRay(1.13 ether)
    // uint public liquidation_penalty = wadToRay(1.13 ether); // axe
    // TODO: look at how dai uses their axe value, becuase I dont think this
    // is really 13% as I've been using ray percentages
    // TODO: if wadToRay is used on any user input, need to add overflow check
    // in dai system, axe * tab = new tab. axe is +1 because it acts as a multiplier
    // An equivalent approach would be to subtract an axe fraction of the collateral
    // that is returned to the attacker at the end
    uint public axe = wadToRay(1.13 ether);

    // win
    // uint public keeper_reward;  // ray -> % of the liquidation penalty that keepers take
    uint public win;    // Keeper reward

    // TODO: what should this be?
    // uint public max_rate = wadToRay(2 ether);   // usury, shark
    // Even if not set for the purpose of protecting users, this will prevent
    // a 'rapid undercollateralization' attack, where someone could take their
    // own debt, then set the interest rate so high it would quickly become undercollateralized,
    // and they could potentially be paid a reimbursement > 
    uint public usury = wadToRay(2 ether);

    // TODO: what should this be? - see what the dai debt ceiling (cap) is
    uint public cap = uint(-1);    // max owed_amt, after a certain point
        // the owed_amt + interest could overflow, breaking everything. This
        // should be included in the safe() function -- i.e. being over the cap
        // after interest is accrued means you can be liquidated

    // Because the interest rate and collatRatio depend on the tokens that the
    // trader can trade in (tokens with more volatiliity mean more risk of
    // the trader becoming undercollateralized before being margin called),
    // the best design at this point seems to be specifying all of these parameters
    // on a per accouunt basis

    // Limit max balance. This is hard to enforce, though, because every time
    // a trader tops up their account, we can't go to all the oracles, determine
    // the total value of their position in payoutTGovernance decides which external tokens are valid as collateral, and creates different deposit classes, or "CDP types", each with different parameters such as maximum dai issuance, minimum collateral ratio, and so on.oken, then decide if it's
    // under the limit. Also, what token do we denominate maxDeposit in?
    // uint public maxDeposit;

    mapping (address => mapping(address => Account)) public accounts;
    // mapping (address => mapping(address => address)) public balanceUnits;


    // The token pairs approved for trading for the entire contract. 
    // These are based on the availability of sufficently accurate and 
    // decentralized oracles and the liquidity of the market. Managing
    // contracts can further restrict the available tokens for users to
    // trade based on their own system (for some contracts) tokens have enough liquidity.
    // Note that buy/sell orders do not have to swap an approved token pair, the only
    // requirement is that both tokens are approved token pairs with the payoutToken.
    // Would need to check that swap does not undercollateralize, b/c they could
    // take their own swap order, leaving tiny amt of collateral in account,
    // which would then obviously be liquidated but they would get out of
    // the collateral commitment 
    // mapping (bytes32 => bool) public token_pairs;   // trading_pairs, trade_pairs
    // gems
    mapping (address => mapping(address => bool)) public token_pairs;


    // Allows contracts to only set some params once. Always check account params
    // first. If zero, check contract globals, if those are zero too, follow
    // whatever logic 0 entails
    struct ContractGlobalParams {

    }
    mapping (address => ContractGlobalParams) contractParams

    // Not sure which of these to use. Depends how we want to implement 
    // the oracle functionality
    // mapping (bytes32 => bool) globallyApprovedTokenPairs;
    // mapping (address => bool) approvedTokens;
    // Establish oracles for each token pair. Could also allow each managing
    // contract or account to set their own oracles, but I think oracles
    // are something safer to determine once because they would be fairly
    // easy to trick a naive user into accepting a situation with a bad oracle
    // TODO: might also need some sort of an inversion method (i.e. if we
    // have an oracle for Dai/Weth but not Weth/Dai, we need to convert this
    // rate to match our situation)
    // This will be implemented in the PriceOracleInterface contract
    // mapping (bytes32 => address) oracles; 


    // The 'managing' contract (i.e. the payment channel) should pass in approved
    // tokens or token pairs, b/c each contract will manage these differently
    // (i.e. in a payment channel, the two channel participants need to agree
    // on approved tokens, but in a many-to-many collateral situation like Augur,
    // the entire governance system needs to agree on it). But, once the approved
    // tokens are in our contract, an individual user should be able to shift their
    // positions freely, assuming they do not undercollateralize themselves

    ////// When a deposit is made, the contract must pass in:
    // approved token contract(s)
    // interest % - amt that payoutAmt should be increased over time, can be 0%
    // payoutAmt
    // payoutToken
    // payerAddress - address to transfer the initial deposit from. Could be contract or the sender in a payment channel
    // payoutAddress - this might be the contract itself, or the other user in a payment channel

    
    ////// Functions:
    // Deposit - the contract=>user balance
    // Pay - pay the payout amt (or some portion of it) from the contract=>user balance in the payout token
    // Trade - called by the user, needs to include a DEX order
    // TopUp - called by the user, adds funds to avoid becoming undercollateralized
        // Should there be a similar function callable from the contract?
        // For now, let's say the managing contract only deposits 100% of payout amt.
        // Any additional deposits or interactions are done by the trader
    
    // Some function by which the account can be closed entirely without paying all
    // of the collateral to the payoutAddress. Either the managing contract should be able
    // to submit a tx claiming all the funds, or they should be able to send a function
    // to transfer x amt to payoutAddress and the remainder to the trader. Also
    // need to consider how this all works in the context of a many-to-many collateral
    // situation. Either the managing contract submits it's own address as the payout
    // address and then distributes the funds according to it's liking or 
    // some other function is implemented

    // Some function that trader can close all his positions, reduce deposit to 100% of
    // payoutAmt as long as it is all held in payoutToken. Basically, you shouldn't
    // need to have any excess collateral in the contract if all of your holdings are
    // in payoutToken, because payoutAmt of payoutToken is guaranteed to always 
    // be = to payoutAmt of payoutToken

    // TODO: Is it worth it to even have a payoutAddress, or should we just send
    // all payout funds to the managing contract and let them deal with it?

    // TODO: Should each contract be able to set their own collateralization
    // ratio?

    // TODO: If iniitial deposit is 100% of payout amt, how do we make sure that
    // postions can't be automatically liquidated? Something like bool initialized
    // to see whether trader has interacted with it yet? or require managing contract
    // to transfer 


    // How does this apply to insurance contracts?

    
    // 

    // ===============
    // Owner Functions:
    // ===============

    // TODO: add owner functions to add and remove approved tokens and their respective oracles
    // - add owner functions to change the collateralization ratio and other parameters
    // - add a check that contract conforms to ERC20 standard before it is added to approvedTokens list
    // These will eventually be based on some sort of governance system
}