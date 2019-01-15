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

contract ValueLike {
    function peek() public returns (bytes32, bool);
}

contract Scout is Ownable, DSMath {
    ChiefLike public chief;
    ValueLike public value;
    bytes32   public pair;
    //bool      public inv;   // inverse oracle value?

    // --- Init ---
    constructor(address _chief, address _value, bytes32 _pair) public {
        chief = ChiefLike(_chief);
        value = ValueLike(_value);
        pair = _pair;
    }

    // --- Math ---
    // uint256 constant ONE = 10 ** 27;

    // function mul(uint x, uint y) internal pure returns (uint z) {
    //     require(y == 0 || (z = x * y) / y == x);
    // }

    // --- Administration ---
    function file(bytes32 what, address _value) public onlyOwner {
        if (what == "value") value = ValueLike(_value);
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
        (bytes32 spot, bool ok) = value.peek();
        if (ok) { chief.file(pair, "val", price(uint(spot))); }
    }

    // This 'price function' will be different for every spotter depending
    // on the format that the price feed is read from the medianizer in.
    // This function, for example, will take ETH.USD price feed and return
    // usd / 1 Eth
    function price(uint spot) internal pure returns (uint) {
        return spot;
    }
}