pragma solidity ^0.5.0;

// OpenZeppelin SafeMath + revert strings
/**
 * @title SafeMath
 * @dev Unsigned math operations with safety checks that revert on error
 */
library SafeMath {
    /**
    * @dev Multiplies two unsigned integers, reverts on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "ecm-safemath-mul-overflow");

        return c;
    }

    /**
    * @dev Integer division of two unsigned integers truncating the quotient, reverts on division by zero.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "ecm-safemath-div-by-zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
    * @dev Subtracts two unsigned integers, reverts on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "ecm-safemath-sub-underflow");
        uint256 c = a - b;

        return c;
    }

    /**
    * @dev Adds two unsigned integers, reverts on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "ecm-safemath-add-overflow");

        return c;
    }

    /**
    * @dev Divides two unsigned integers and returns the remainder (unsigned integer modulo),
    * reverts when dividing by zero.
    */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "ecm-safemath-mod-by-zero");
        return a % b;
    }
}


library MathTools {

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
        uint RAY = 10 ** 27;
        z = n % 2 != 0 ? x : RAY;

        for (n /= 2; n != 0; n /= 2) {
            x = rmul(x, x);

            if (n % 2 != 0) {
                z = rmul(z, x);
            }
        }
    }

    // returns new principal with interest accrued
    function accrueInterest(uint principal, uint rate, uint age) internal pure returns (uint) {
        return rmul(principal, rpow(rate, age));
    }

    // returns the interest amount accrued
    function getInterest(uint principal, uint rate, uint age) internal pure returns (uint) {
        return SafeMath.sub(accrueInterest(principal, rate, age), principal);
    }

    // TODO:
    function convertBalance(uint balance, uint spotPrice) internal pure returns (uint) {
        return SafeMath.mul(balance, spotPrice);
    }

    // TODO: rethink the way we're taking the biteFee
    function getBiteCost(uint collateralValue, uint biteFee) internal pure returns (uint) {
        uint RAY = 10 ** 27;

        if (biteFee <= RAY) { return collateralValue; }

        return rmul(collateralValue, SafeMath.sub(biteFee, RAY));
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

    function k256(address _a) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_a));
    }

     // From OpenZeppelin's math library
     /**
    * @dev Returns the largest of two numbers.
    */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }
}