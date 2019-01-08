# Ideas / Design Decisions

"If I had more time, I would have written a shorter letter." - Blais Pascal

* Need a new name for CollateralVault
investing vault, some play on a double life, relevant words in a different language
- kind of equivalent to the collateral 'tub' in dai system?

## LIquidations
Should only liquidate the minimum amount of assets required to 'cover the debt' by getting owed_amt + penalty of owed_token. Now the position is safe until the holder makes another swap. But, how do we determine which of the held tokens to try to sell first?

- Can we allow traders to set the order that their positions will be sold off in the event of a liquidation or a request for the collateral by the managing contract?

- How reasonable is it to allow the managing contract to initiate an immediate liquidation of assets by requesting owed_amt? Ideally these managing contracts are providing some type of warning to holders, and we can't really dictate that all managing contracts have to allow 24 hours to get to the collateral that is theirs to manage.

liquidation_order[] -> The trader can optionally set this order. In the abscense of this order, the default order is simply iterating through the positions array
* The size of this array also needs to be limited by max_positions, for the same reason

The gas costs of auctioning multiple types of collateral make this very difficult. Also, how do we manage the time requirement of auctions of collateral for managing contracts? maybe there has to be some sort of time delay before a managing contract can access their collateral. Giving time for the trader to sell at her price and for auctions to be initiated not all in the same transaction? OR maybe we can auction all collateral at the same time (see dai's tend and dent phase auctions). Maybe we can have 'keeper' types bid on all of the collateral in the same bid, denominated in owed_token. Assuming owed_amt of owed_token is covered, then people bid on the minimum amt of collateral they will take in exchange for that amt of owed_token

- Should contracts be able to call a liquidate() function on any account to 'prepare' it for a payout? This seems to be an unreasonable power, but theoretically the contract already has the power to do whatever it wants with the collateral

- There doesn't actually have to be a keeper penalty for false liquidations, becuase all we do is check the value of total collateral against the mcr, and if its safe then the keeper loses out on the gas and nothing else happens

- If you have to buy all the collateral at once, is there a posibility for an attacker with sufficient capital to price all other bidders out of the market?

- Can liquidation penalty just equal keeper reward and then we can 

// TODO: SHIT NEEDS TO RUN IN CONSTANT TIME / GAS COST - this means a better method
// than iterating over an arbitrary length array of assets - see dai's drip, feel, and prod
// Maybe each account and/or account class (i.e. the contract can set certain parameters
// for all of the accounts in it) can specify a max number of assets, then they know that
// the cost of any claim on the owed_token will be < the cost of initiating an auction for each
// of those assets

- Do we auction all collateral together or each asset separately?

- We cannot have a penalty-free liquidation of collateral on call for payment by the managing contract because this would be succeptible to an auction grinding attack. But, we can't penalize a user if the managing contract calls for a payment without warning. Maybe if the gem balance covers the payment, payout immediately. Else, payout after x amount of time for user to sell tokens

- What if we allow contracts to set a max_payment value for the account. Then, the user must be required to keep max_payment value in payout_token? This is pointless for contracts that are going to pay out entire owed_amt at once (i.e. at the conclusion of a bet)

- Managing contract should also be able to include a buy order signed by the trader with a call for payout? And can send a buy order at any time during a keeper-induced auction or after the call time period for a payment has expired, buying at a specified price.

- In dydx, if a trader does not respond to a margin call within the call time period, the entire quantity of held token belongs to the loan offerer. This could work for us, but we likely still need to pay out in owedToken, and we need to be as fair as possible to traders. Could just give a contract to specify whether to auction on call time expiration?

- Research dutch auction vs. dai-style auction and benefits of both

- If we are going to require a multi-call, time-delayed claim on 

- Trader could set a default 0x offer (value > owedAmt), and any time the position is called for a payment, that offer (or combination of offers), is taken and payment is made atomically. This prevents multi-call method. If offer fails, liquidate w/ penalty? Could have a validOfferAvailable() function for contracts to interface with, which checks offer parameters and 0x cancelled orders and returns bool. Theoretically this 0x offer would be made by the trader themselves and would just be a way to prevent liquidation in the event of a payment call. Could not be used in the event of an undercollateralization, because that would take away keepers' incentive to bite. Maybe if offer not valid, could make market offer on oasisDex with minSellAmount == owedAmt, but we can't guarantee that we wouldn't run out of gas or fail to get owedAmt for the collateral, which would both cause reverts. Could also liquidate with penalty immediately under the assumption that the holder was (hopefully) warned about payment by the managing contract and had 0x order as fallback.


## Undercollateralization
(When auctioned collateral < tab) -> should we create a system to insure against this, or can we just payout less than the tab, putting the burden on managing contracts to effectively set the risk parameters?
- If we cover the difference, this value (the insurance money, basically) flows either to the winner of the auction collateral (she got a deal on the collateral) or to the trader (she let the value of the collateral fall below tab and it got covered by someone else) or a combination of both. an 'auction grinding attack' seeks to exploit this in the event that the auction winner and the trader are the same person (but even the managing contract could be that same person)
- if we don't cover the difference, the trader is still sort of 'getting away with one'. But the real loser is likely the payout address. This is a good reason why they are getting interest to allow the collateral to be traded

## var names
tar, zap, par, lip, sip, vat, pit, bin, jet, hit, wan, rim, kin, fob, pod, jug, box, 

- dir for managing contract and lad for trader / holder?
- increasing `tab` by the managing contract would be similar to `draw` in dai, increasing the amount due on the collateral

## DAI and Collateral Vault
In the dai system, the only reason to lock up collateral is the desire to go long on a crypto asset. So, what happens if every crypto asset crashes so consistently (or, ironically, stays so stable?) that no one wants a long position anymore. What if the collateral locked up in the dai system could be the same collateral you're promising as payment in another smart contract? i.e. my payment channel deposit also serves as collateral to mint dai? This is a really fuzzy link, but there seems to be some potential connection with dai here.

## Price feeds and updates
From dai purple paper: (Tag refers to the data associated with each approved gem)
data Tag = Tag {
  Latest token market price (denominated in SDR)
  · tag :: Wad,
  Timestamp after which price should be considered stale
  · zzz :: Sec
} 

## Price differences
The difference in gas costs between storing value in your own contract and using the Collateral Vault is dependent on a ton of factors, including:  
-> the design of your own contract (or, specifically, the optimal design of the contract if you don't use CB). 
    - the amount of data you would otherwise need to store. i.e. do you determine owed_token on a per-user basis, or is your owed_token parameter global, meaning that you would not need to write it for every user that puts up collateral if you weren't using cB

-> how often you interact with the CB. the more you update interest accrual and other parameters, the more significant the gs difference becomes (probably, should look into this)
 
## Determining the global parameters
`axe`, `win`, `cap`, `usury`
unless there is another reason for the implementation of cap and usury, they should just be set such that the max cap at max usury does not compound fast enough to overflow before having a reasonable amount of time to get liquidated. Note, though, that there are two different integer overflows to worry about here (Note that 'overflow' here actually refers to safe math operations failing and 'locking up' the contract functions. i.e. every function that requires accruing interest to owed_amt would fail if owed_amt + accrued interest fails bc of overflow checks):

From dai purple paper:
"Governance decides which external tokens are valid as collateral, and creates different deposit classes, or "CDP types", each with different parameters such as maximum dai issuance, minimum collateral ratio, and so on."
-> ** maybe the parameters should be different for each asset class
mapping(address=>mapping(address=>Token_pair)) token_pairs, where Token_pair
is a struct with bool approved,  `cap`, `max_rate` etc? could also set a global mcr for each asset token pair class ** see dai's Ilk

- owed_amt -> could overflow if user's owed_amt is initially set very high along with a high interest rate. The only things that effect this value is the managing contract setting/raising/lowering owed_amt and the account interest rate
- overflow of the 'total balance' uint is based on the amount held in all tokens, so a spike in value of a held token can cause this to overflow

- ^ This is an important thing for a user to be aware of. If you have too much in your account and the value of your assets skyrocket, you might be forced to sell before you want to or risk being liquidated for being over the max total balance

- Should `cap` serve as the max owed amt and the max total balance? or should these be different?

- * Maybe we could implement some sort of overflow lockup preventer, where if interest + owed amount overflows, do something to mitigate the effect

## Alternative Design Patterns
- No keepers. Each contract decides for itself whether to leave it up to individual users to track their counterparty's collateralization or implements their own incentivization scheme for keepers. Some function notifies the contract of who liquidated the account (or contracts are required to implement a standard function we can call). Maybe we even transfer all the collateral to the contract and let them deal with the liquidation logic

## Crucial Points
- It is Crucial that any user of a contract verify THIS contract's address (CollateralBank) before approving this contract to take custody of ERC20 tokens or interacting with another contract that claims to use the CollateralBank. As you probably know, in solidity, any address can be cast as a particular contract, even if the code contained at that address does not match the code of the contract it is now pretending to be. It would be easy for a malicious collateral-holding contract to pretend to use our contract while passing the constructor of their own contract the address of a malicious contract in place of our contract address. This also highlights why we should all demand that contracts store external contract addresses as public state variables so that these external addresses can be easily verified.

## Account Parameters
For clarity, account parameters are things like the payoutAmt, approvedTokens,
collateralization ratio, etc. Some of these make perfect sense to define on a
per-account basis (e.g. payoutAmt), and others are less clear. There should 
definitely be some debate around which parameters should be defined on a per-account
basis, which should be 'global' constants set hopefully through a future 
governance structure, and which should be defined by each managing contract but
not for each account individually. Obviously, setting each of these parameters for
each account individually increases gas costs, and this can be unnecessary for
managing contracts that have all of their managed accounts set with the same paramters
anyway. But, for contracts like general payment channels, the members of the payment
channels might want to determine their own parameters, in which case the payment channels
contract (a.k.a the 'managing' contract) would want to be able to pass these 
params to the CollateralBank contract for each individual account.

## Global vs. Contract vs. Account scope parameters
The parameters for using collateral to 'invest' in ERC20 tokens include things
like which tokens should you be able to trade for, what the minimum collateralization
ratio should be, and how to determine that ratio for an account. Some of these parameters
should be defined 'globally', or for the entire CollateralBank contract, some should be
defined by each managing contract, and some should be defined for each individual
account. The scope at which these parameters should be defined is largely debateable,
so I have provided a little bit about what these parameters are, how they're currently
defined, and benefits of different ways they could be defined.

### Approved Tokens
While I hate to see the word "approved" in any smart contract, as it usually indicates
either a point of centralization or the need for a complex governance system, it's
pretty clear that allowing collateral to be traded for any ERC20 token under the sun
is a bad idea. Token value could be excessively volatile, it could be a scam ICO token
for which no market even exists, or it could be a "<a href="https://medium.com/spankchain/we-got-spanked-what-we-know-so-far-d5ed3a0f38fe">malicious contract masquerading as an ERC20 token</a>." Additionally, as the system is currently designed, the market for
a token pair needs to be liquid enough to provide fair market prices most of the time, and there needs to be an accurate and sufficiently decentralized oracle available to determine the market price for a token pair.  
  
Even if these conditions are satisfied, the volatility of the tokens being traded have a huge influence on the reasonable values for other parameters, such as collateralization ratio. If an asset's value typically tracks the value of the owedToken relatively closely (a high <a href="https://www.investopedia.com/terms/b/beta.asp">Beta</a> relative to the owedToken), then the risk of default or undercollateralization before the margin call process can be carried out is relatively low. But, if the asset's value varies wildly relative to the owedToken, the risk of undercollateralization would be much higher for the same collateralization ratio. Therefore, the managing contract or the counterparty who is owed the collateral might demand a much higher interest rate or collateralization ratio for allowing a trader to trade in this riskier token.  
  
Currently, approved tokens are defined at two different levels. Approved token pairs are defined globally for the entire CollateralBank contract. These token pairs will be based on the liquidity of markets and quality of oracles available and will ideally be decided via a robust governance system (yet to be implemented).  
  
In addition, each individual account has a set of approved tokens, which must also be an approved token pair with the owedToken for the account. For example, if token X and token Y are not a globally approved token pair, then a managing contract can not approve an account to trade token X if token Y is the account's owedToken. This allows the risk-related parameters of each account to be determined on an individual basis. The downside is that many-to-many managing contracts (such as the Augur platform) that might want to define these parameters as constants for all collateral held in the contract need to spend additional gas to set the exact same parameters for each account that is opened. This would be avoided if the approved tokens were set at the managing contract level so they would only need to be set once per managing contract.

### Interest



## Managing interest separately from principal payments
- Note that managing interest and principal separately was not built into the contract under the assumption that the desire to do this would too infrequent to justify the added gas costs of extra state storage and double the transfers for every other contract. This assumption may turn out to be false, in which case the logic could be separated out. In it's current form, managing contracts that wish to do this could use the following design pattern:  
uint totalPayment = CollateralBank.payout(payAmt);
uint interest = totalPayment.sub(payAmt);
OR
{calling pure function (or including it in their own code) to calc. interest on payAmt, then doing bascally the same shit without the external call in between}

- Transferring separately:
    - 2 transfers per payment (principal and interest)
    - 1 extra transfer for contracts that don't implement
- Transferring all together (current impl):
    - 1 transfer per payment
    - 3 transfers total for contracts that want to separate principal and interes (1 to their
        contract, 1 from them to principalReceiver, 1 from them to intReceiver, but only 1 extra from if our contract implemented.)
-*** But, you could just store principalReceiver and interestReciever, then:
    if (account.principalRecipAddress == account.interestRecipAddress) {
        1 transfer
    } else { 2 separate transfers }

** ^^ This might be the way to go, but ERC20 transfers are expensive, and may frequently cost more in gas than the interest payout would be worth


## The Reason for the 'Honeypot' system design
- To aggregate keepers. The existence of well-functioning and incentivized keepers is essential to limiting the risk of default. If the accounts were all distributed among many addresses, it would be momre difficult for keepers to keep track of all the addresses implementing the standard and the keeper system might not function well. On the other hand, if there was a way to effectively track this, then it would be ideal to make this a library or inheritable contract so that contracts could implement the logic without making external contract calls or aggregating all of the tokens in one contract. Obviously, if the current system design stands, extremely thorough auditing and consideration of incentives would need to be done.
- One idea for changing this design would be to create one contract that maintains a 'list' of all the addresses implementing the CollateralBank logic, giving keepers a central place to find opportunities to liquidate/margin call accounts with the same logic. However, there would need to be a way to ensure that these contracts implemented the exact same logic, not just the same function names (maybe this exists, need to look into it). It would be unsustainable for keepers to thoroughly audit every single contract with the same function names when there may only be a small number of accounts (which might never become undercollateralized) in each contract. But, if only the function names were verified in the 'list' contract, it would be relatively simple to sneak some malicious logic into a contract that stole the keepers deposits or otherwise cheated system participants.

## Getting Rid of Oracles

### Two-party accounts
This really only works in the context of one-to-one (and maybe many-to-one)
collateral situations. Basically, no keepers or oracles are used, so the only
incentive for someone to 'margin call' an account is that they are the one owed
the money, so they need to watch and make sure it stays properly collateralized.
This would be analogous to what dy/dx does with margin trading. When margin called,
the trader can either top up with the requested amount, or submit a buy order and sell
their positions for payoutToken. This means that recipients of the funds would
need some sort of reputation or a high interest rate on their payoutAmt
so that they aren't just margin calling their counterparty all the time 
and defeating the purpose of the collateral bank. Also,
in a many-to-many collateral situation such as Augur, I think there are too many parties
involved to make this work. Addresses could margin call everyone in the Augur market
without a second thought because they have no real reason not too. On the other
side, their could be a 'tragedy of the commons' situation where there's so many
people in the Augur market that no one is more incentivized than anyone else to
monitor the collateral of the many other addresses in the Augur market, so no
one does and the market runs the risk of becoming undercollateralized.

Another advantage of this design would be the elimintation of the central storage of
funds and the need for external contract calls to the CollateralBank contract. Because
there would be no keepers, there would be no need to keep all the accounts in one place,
and any contracts that wanted the functionality could just inherit a contract that
makes it easy to manage the same logic that the CollateralBank contract handles right now
while maintaing custody of all tokens and avoiding external calls to the CollateralBank
contract. Perhaps this is also possible with the existing design, but each contract
that uses it would need to have enough usage for keepers to be incentivized to pay
attention to the accounts.

### Matching-Market Buy Orders
The same logic of the Oracle can be maintained by a matching-market order in
a special situation. First, why the need for the Oracle in the first place
instead of just the dy/dx method of requiring a DEX buy order on margin call?
Any individual can create their own 0x or other DEX order offering to buy the
held asset at much higher than market price, then submit it to our contract and
take their own order. In the context of dy/dx or the 'Two-party accounts' discussed
above, the trader has no real incentive to do this, as they aree still paying
for their own order and it's a net-zero operation for them. But, if you have keepers
tracking the collateral in the market (useful in a many-to-many collateral situation
as discussed above), then you need to incentivize them for valid margin calls
and disincentivize them from making bad margin calls. To do this, you need to determine
when a margin call is valid or invalid, which means you need to determine a market
price for the held asset denominated in payoutToken. Additionally, to disincentivize
allowing the value of your collateral to drop below the required collateralization 
ratio, it makes sense to pay this reward to the keeper from a penalty assessed
to the trader. But, you can't use the dy/dx method of market price determination
(to be fair, dy/dx is not actually using this mechanism to determine the market
price, they are just cleverly bypassing the need to determine a market price),
because the trader is now incentivized to create a fake buy order at higher than
market price to make it look like the keeper made a bad margin call and avoid
paying the penalty for being margin called.

A naive solution is only taking on-chain orders, with the assumption that in order
to take their own fake order, they would have to submit it on-chain, risking that 
someone else might take their order before they can take it to close their position,
and they would have to pay above market price for the asset that they already own.
But, they could deploy an 'atomic transsactions' smart contract and do both at the same
time, without the opportunity for anyone else to jump in and take their fake order.
But, if you had a matching market contract with enough liquidity that automatically
matched orders on submission, then you could know for sure that any artificially-high
buy order would be automatically taken by the other side of the market, and because 
the trader is already incentivized to submit the highest buy order they can find, you
could accurately say that the submitted buy order (if it is still valid and is marked
as a 'match-me-automatically' order) is the market price of the asset.

The issue: Auto-matching orders (and having on-chain order books in general) 
is very gas-intensive, so any markets that match this design pattern seem
like they would be unlikely to have the liquidity necessary to make this a valid
solution.



## Upgradeability
Reasons why contract are not upgradeable
- Makes it more time-consuming to understand the system (and therefore to contribute)
- My own lack of time, and it's not high on the priority list for a POC