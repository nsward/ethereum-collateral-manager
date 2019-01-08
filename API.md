# Contracts
open(): opens an account for the specified address

payout(): pays out specified amount to owedAddr. If specified amt not currently
held 


Contracts will have to call payoutAvailable(), then if true, follow normal logic and transfer. If false, call call() to trigger the call period and allow trader time to get collateral into owedToken

# Traders