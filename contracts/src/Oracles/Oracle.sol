pragma solidity ^0.5.3;

// This can ultimately be any oracle contract that the community decides
// is trustworthy, and we can use different oracles for different token
// pairs simply by deploying spotters with different price functions
// and interfaces with the oracle. For now, this contract mimics the 
// interface of the MakerDAO medianizer contracts and allows us to
// manipulate the value for testing purposes
// https://github.com/makerdao/medianizer/blob/master/src/medianizer.sol
contract Oracle {

    bytes32 val;
    bool public has;

    // auth
    mapping (address => uint) public wards;
    function rely(address guy) public auth { wards[guy] = 1;  }
    function deny(address guy) public auth { wards[guy] = 0; }
    modifier auth { require(wards[msg.sender] == 1); _; }

    // --- Init ---
    constructor(uint _val, bool _has) public {
        wards[msg.sender] = 1;
        val = bytes32(_val);
        has = _has;
    }

    // returns the price value and a bool indicating the validity of the price
    function peek() external view returns (bytes32, bool) {
        return (val, has);
    }

    // For testing. Set the price value and the validity bool
    function file(bytes32 what, uint data) public auth {
        if (what == "val") val = bytes32(data);
    }
    function file(bytes32 what, bool data) public auth {
        if (what == "has") has = data;
    }
}