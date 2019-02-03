// Borrowed from MakerDAO's Spotter. Thanks, MakerDAO!
// https://github.com/makerdao/dss-deploy/blob/master/src/poke.sol
// One very important change: it does not incorporate mat into the spot 
// price like dai's spotter does. Note that the price function will be
// different for each spotter depending on the format of the oracle
// return value

pragma solidity ^0.5.3;

import "../../lib/DSMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

contract ChiefLike {
    function file(bytes32, bytes32, uint) external;
}

contract OracleLike {
    function peek() public returns (bytes32, bool);
}

contract Spotter is Ownable, DSMath {
    ChiefLike public chief;
    OracleLike public oracle;
    bytes32   public pair;

    // --- Init ---
    constructor(address _chief, address _oracle, bytes32 _pair) public {
        chief = ChiefLike(_chief);
        oracle = OracleLike(_oracle);
        pair = _pair;
    }

    // --- Update spot price for token pair in chief contract ---
    function poke() public {
        (bytes32 val, bool ok) = oracle.peek();
        if (ok) { chief.file(pair, "spotPrice", price(uint(val))); }
    }

    // This 'price function' will be different for every spotter depending
    // on the format that the price feed is read from the medianizer in.
    function price(uint val) internal pure returns (uint) {
        return val;
    }

    // --- Administration ---
    function file(bytes32 what, address _oracle) public onlyOwner {
        if (what == "oracle") oracle = OracleLike(_oracle);
    }
}