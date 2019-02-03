pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

library MathTools {

    // using SafeMath for uint256;

    // From DappHub's DSMath, but uses SafeMath instead of DSMath overflow checks
    function rmul(uint x, uint y) internal pure returns (uint z) {
        // z = add(mul(x, y), RAY / 2) / RAY;
        // z = x.mul(y).add(RAY / 2).div(RAY);
        uint RAY = 10 ** 27;
        z = SafeMath.div(SafeMath.add(SafeMath.mul(x, y), RAY / 2), RAY);
    }

    // From Dapphub's DSMath, with the small modification of RAY not being
    // read from storage
    // This famous algorithm is called "exponentiation by squaring"
    // and calculates x^n with x as fixed-point and n as regular unsigned.
    //
    // It's O(log n), instead of O(n) for naive repeated multiplication.
    //
    // These facts are why it works:
    //
    //  If n is even, then x^n = (x^2)^(n/2).
    //  If n is odd,  then x^n = x * x^(n-1),
    //   and applying the equation for even x gives
    //    x^n = x * (x^2)^((n-1) / 2).
    //
    //  Also, EVM division is flooring and
    //    floor[(n-1) / 2] = floor[n / 2].
    //
    function rpow(uint x, uint n) internal pure returns (uint z) {
        uint RAY;
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }


    // Go from wad (10**18) to ray (10**27)
    function wadToray(uint256 wad) internal pure returns (uint) {
        return SafeMath.mul(wad, 10 ** 9);
    }

    // // Go from wei to ray (10**27)
    // function weiToRay(uint _wei) internal pure returns (uint) {
    //     return SafeMath.mul(_wei, 10 ** 27);
    // } 

    // could make this public for ease of use?
    function accrueInterest(uint principal, uint rate, uint age) internal pure returns (uint) {
        return rmul(principal, rpow(rate, age));
    }

    // Returns the value of a partial fill given an implied price (makerAmt / takerAmt)
    // and the fill amt
    function getPartialAmt(uint makerAmt, uint takerAmt, uint fillAmt) 
        internal 
        pure 
        returns (uint) 
    {
        return SafeMath.div(SafeMath.mul(makerAmt, fillAmt), takerAmt);
    }

    function k256(address _a, address _b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_a, _b));
    }
}