// Borrowed from MakerDAO's Spotter. Thanks, MakerDAO!
// https://github.com/makerdao/dss-deploy/blob/master/src/poke.sol
// One very important change: it does not incorporate mat into the spot 
// price like dai's spotter does. Note that the price function will be
// different for each spotter depending on the format of the medianizer

pragma solidity ^0.5.2;

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
    //bool      public inv;   // inverse oracle value?

    // --- Init ---
    constructor(address _chief, address _oracle, bytes32 _pair) public {
        chief = ChiefLike(_chief);
        oracle = OracleLike(_oracle);
        pair = _pair;
    }

    // --- Math ---
    // uint256 constant ONE = 10 ** 27;

    // function mul(uint x, uint y) internal pure returns (uint z) {
    //     require(y == 0 || (z = x * y) / y == x);
    // }

    // --- Administration ---
    function file(bytes32 what, address _oracle) public onlyOwner {
        if (what == "oracle") oracle = OracleLike(_oracle);
    }
    // function file(bytes32 what, bool _inv) public onlyOwner {
    //     if (what == "inv") inv = _inv;
    // }

    // function file(uint mat_) public onlyOwner {
    //     mat = mat_;
    // }

    // --- Update value ---
    // TODO: check
    function poke() public {
        (bytes32 val, bool ok) = oracle.peek();
        if (ok) { chief.file(pair, "spotPrice", price(uint(val))); }
    }

    // This 'price function' will be different for every spotter depending
    // on the format that the price feed is read from the medianizer in.
    // This function, for example, will take ETH.USD price feed and return
    // usd / 1 Eth
    function price(uint val) internal pure returns (uint) {
        return val;
    }
}