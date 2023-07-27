// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import "forge-std/Test.sol";
import "../src/Shelf.sol";
import "../src/TestToken.sol";
import "../src/InterestRateModel.sol";

contract ShelfTest is Test {
    Shelf public shelf;
    TestToken public tokenA;
    TestToken public tokenB;
    InterestRateModel public interestRateModel;

    address public tokenAAddress;
    address public tokenBAddress;
    address public interestRateModelAddress;

    // some users
    address public alice;
    address public bob;

    int256 constant TOKEN_DECIMAL_SCALAR = 10 ** 8;

    function setUp() public {
        tokenA = new TestToken("Token A", "TKNA", 8);
        tokenB = new TestToken("Token B", "TKNB", 8);
        interestRateModel = new InterestRateModelConstantImpl();

        tokenAAddress = address(tokenA);
        tokenBAddress = address(tokenB);
        interestRateModelAddress = address(interestRateModel);

        int256 marginRequirement = 300 * TOKEN_DECIMAL_SCALAR / 100; // 300% or 3x
        shelf = new Shelf(marginRequirement, interestRateModelAddress);

        // set up some users in the vm
        alice = vm.addr(1);
        bob = vm.addr(2);

        // the test contract, alice and bob all have some tokens
        tokenA.mint(address(this), uint256(1000 * TOKEN_DECIMAL_SCALAR));
        tokenB.mint(address(this), uint256(1000 * TOKEN_DECIMAL_SCALAR));
        tokenA.mint(alice, uint256(1000 * TOKEN_DECIMAL_SCALAR));
        tokenB.mint(alice, uint256(1000 * TOKEN_DECIMAL_SCALAR));
        tokenA.mint(bob, uint256(1000 * TOKEN_DECIMAL_SCALAR));
        tokenB.mint(bob, uint256(1000 * TOKEN_DECIMAL_SCALAR));

        int256 tokenAToUsdRate = 1 * TOKEN_DECIMAL_SCALAR; // $1
        int256 tokenBToUsdRate = 2 * TOKEN_DECIMAL_SCALAR; // $2

        shelf.addToken(tokenAAddress, tokenAToUsdRate);
        shelf.addToken(tokenBAddress, tokenBToUsdRate);
    }

    function testDeposit() public {
        tokenA.approve(address(shelf), uint256(500 * TOKEN_DECIMAL_SCALAR));
        tokenB.approve(address(shelf), uint256(500 * TOKEN_DECIMAL_SCALAR));

        shelf.deposit(tokenAAddress, 500 * TOKEN_DECIMAL_SCALAR);
        shelf.deposit(tokenBAddress, 500 * TOKEN_DECIMAL_SCALAR);

        assertEq(shelf.currentBalance(address(this), tokenAAddress), 500 * TOKEN_DECIMAL_SCALAR);
        assertEq(shelf.currentBalance(address(this), tokenBAddress), 500 * TOKEN_DECIMAL_SCALAR);
    }

    function testWithdrawEasyCase() public {
        tokenA.approve(address(shelf), uint256(500 * TOKEN_DECIMAL_SCALAR));

        shelf.deposit(tokenAAddress, 500 * TOKEN_DECIMAL_SCALAR);

        shelf.withdraw(tokenAAddress, 10 * TOKEN_DECIMAL_SCALAR);

        // check Shelf balance
        assertEq(shelf.currentBalance(address(this), tokenAAddress), 490 * TOKEN_DECIMAL_SCALAR);
        // check token A balance
        assertEq(tokenA.balanceOf(address(this)), uint256(510 * TOKEN_DECIMAL_SCALAR));
        // check token B balance to be sure
        assertEq(tokenB.balanceOf(address(this)), uint256(1000 * TOKEN_DECIMAL_SCALAR));
    }

    function testWithdrawTakeOutDebt() public {
        // alice deposits 500 of token A
        vm.prank(alice);
        tokenA.approve(address(shelf), uint256(500 * TOKEN_DECIMAL_SCALAR));
        vm.prank(alice);
        shelf.deposit(tokenAAddress, 500 * TOKEN_DECIMAL_SCALAR);

        // bob deposits 500 of token B
        vm.prank(bob);
        tokenB.approve(address(shelf), uint256(500 * TOKEN_DECIMAL_SCALAR));
        vm.prank(bob);
        shelf.deposit(tokenBAddress, 500 * TOKEN_DECIMAL_SCALAR);

        // alice borrows 100 of token B
        vm.prank(alice);
        shelf.withdraw(tokenBAddress, 1 * TOKEN_DECIMAL_SCALAR);

        // check the balances of alice on the shelf
        assertEq(shelf.currentBalance(alice, tokenAAddress), 500 * TOKEN_DECIMAL_SCALAR);
        assertEq(shelf.currentBalance(alice, tokenBAddress), -1 * TOKEN_DECIMAL_SCALAR);

        // check the balance for bob on the shelf
        assertEq(shelf.currentBalance(bob, tokenAAddress), 0);
        assertEq(shelf.currentBalance(bob, tokenBAddress), 500 * TOKEN_DECIMAL_SCALAR);

        // check the balances for alice in the token contracts
        assertEq(tokenA.balanceOf(alice), uint256(500 * TOKEN_DECIMAL_SCALAR));
        assertEq(tokenB.balanceOf(alice), uint256(1001 * TOKEN_DECIMAL_SCALAR));

        // check the balances for bob in the token contracts
        assertEq(tokenA.balanceOf(bob), uint256(1000 * TOKEN_DECIMAL_SCALAR));
        assertEq(tokenB.balanceOf(bob), uint256(500 * TOKEN_DECIMAL_SCALAR));
    }

    function testLiquidate() public {
        // re-using the scenario from testWithdrawTakeOutDebt
        this.testWithdrawTakeOutDebt();

        // now, the catch is that the value of the token B that Alice has borrowed
        //  has increased significantly enough so that her account is undercollateralized
        //  and needs to be liquidated

        // alice has $500 (500 tokens) on the platform to begin with of token A and $2 (1 token) of token B

        // our margin requirement is %300 we will update the exchange rate to be $250 for token B. Now, Alice
        //  has $500 of token A as collateral against $250 of token B debt. This is a 2:1 ratio, which is
        //  undercollateralized (200 < 300)
        shelf.updateExchangeRate(tokenBAddress, 250 * TOKEN_DECIMAL_SCALAR);
        // check the value of the collateralizationRatio
        assertEq(shelf.collateralizationRatio(alice), 2 * TOKEN_DECIMAL_SCALAR);

        // now, Bob will liquidate Alice's account
        vm.prank(bob);
        shelf.liquidate(alice);

        // check all the balances
        // on the shelf alice has nothing, bob has the total of what alice had before and what he started with
        assertEq(shelf.currentBalance(alice, tokenAAddress), 0);
        assertEq(shelf.currentBalance(alice, tokenBAddress), 0);
        assertEq(shelf.currentBalance(bob, tokenAAddress), 500 * TOKEN_DECIMAL_SCALAR);
        assertEq(shelf.currentBalance(bob, tokenBAddress), 499 * TOKEN_DECIMAL_SCALAR);
    }

    function testCompoundInterest() public {
        int256 indexBefore = shelf.getInterestIndex(tokenAAddress);
        shelf.compoundInterest(tokenAAddress);
        int256 indexAfter = shelf.getInterestIndex(tokenAAddress);
        // no time has passed so they should be the same
        assertEq(indexBefore, indexAfter);

        // now let's say one year has gone by
        vm.roll(block.number + uint256(shelf.BLOCKS_PER_YEAR()));

        // now let's compound the interest
        shelf.compoundInterest(tokenAAddress);
        indexAfter = shelf.getInterestIndex(tokenAAddress);

        // the constant interest rate model we are using is set to be 1% per year continuously compounded
        // we expect the index to be initialIndex * exp(r * dt) where initialIndex = 1 , r = 0.01 (set) and dt = 1 (year)
        // substituting we have 1*exp(0.01) = 1.0100502 but with our third order taylor series approximation we expect 1.01005016
        assertEq(indexAfter, 101005016);
    }
}
