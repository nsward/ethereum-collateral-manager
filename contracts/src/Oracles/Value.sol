pragma solidity ^0.5.2;

// This will ultimately be a MakerDao medianizer contract:
// https://github.com/makerdao/medianizer/blob/master/src/medianizer.sol
// for now, it implements some of the DSValue functionality and allows
// us to manipulate the oracle for testing
contract Value {

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

    function peek() external view returns (bytes32, bool) {
        return (val, has);
    }

    function file(bytes32 what, uint data) public auth {
        if (what == "val") val = bytes32(data);
    }
    function file(bytes32 what, bool data) public auth {
        if (what == "has") has = data;
    }

    // TODO remove
    function foo() public view returns (uint) {return uint(val);}
    function bar() public pure returns (bytes32) {
        bytes32 baz = bytes32(uint(100));
        // return uint(baz);
        return baz;
    }
}