pragma solidity ^0.5.3;

import "ds-test/test.sol";

import "./EthereumCollateralManagerDapptools.sol";

contract EthereumCollateralManagerDapptoolsTest is DSTest {
    EthereumCollateralManagerDapptools dapptools;

    function setUp() public {
        dapptools = new EthereumCollateralManagerDapptools();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
