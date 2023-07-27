pragma solidity ^0.8.4;

interface InterestRateModel {
    function getCurrentInterestRate(
        int256 currentUtilization,
        int256 idealUtilization,
        uint256 blockDeltaSinceLastUpdate,
        int256 currentInterestRate
    ) external view returns (int256);
}

contract InterestRateModelConstantImpl is InterestRateModel {
    int256 constant INTERNAL_SCALAR = 10 ** 8;

    function getCurrentInterestRate(
        int256, /*currentUtilization*/
        int256, /*idealUtilization*/
        uint256, /*blockDeltaSinceLastUpdate*/
        int256 /*currentInterestRate*/
    ) external pure returns (int256) {
        return 1 * INTERNAL_SCALAR / 100; // 1% interest always
    }
}
