pragma solidity ^0.4.24;

contract PriceOracleInterface {
    // The acutal oracles that we'll use, and therefore the way that oracles
    // is implemented, are TBD. For now, we'll assume that this contract will
    // interact with whatever oracles we choose to use and provide
    // this standard wrapper for other contracts to query

    // returns (uint buyAmt, uint sellAmt)
    // EX: getPrice(daiAddress, wethAddress) could return (100, 1) meaning 100 dai = 1 Eth
    // TODO: we probably want this to return 1 value, because we want to be
    // able to say   
    // if (getPrice(payoutToken, heldToken) * heldTokenAmt < payoutAmt * collatRatio) { validMarginCall(); }
    function getPrice(address buyToken, address sellToken) public view returns (uint, uint);
}