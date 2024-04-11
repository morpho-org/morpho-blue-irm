// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/adaptive-curve-irm/interfaces/IAdaptiveCurveIrm.sol";
import "../../src/fixed-rate-irm/interfaces/IFixedRateIrm.sol";

import {IMorpho, MarketParams} from "../../lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MathLib} from "../../lib/morpho-blue/src/libraries/MathLib.sol";
import {MarketParamsLib} from "../../lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {ORACLE_PRICE_SCALE} from "../../lib/morpho-blue/src/libraries/ConstantsLib.sol";

import "../../lib/forge-std/src/Test.sol";
import {ERC20Mock} from "../../lib/morpho-blue/src/mocks/ERC20Mock.sol";
import {OracleMock} from "../../lib/morpho-blue/src/mocks/OracleMock.sol";

contract BlueTest is Test {
    using MathLib for uint256;
    using MarketParamsLib for MarketParams;

    event BorrowRateUpdate(Id indexed id, uint256 avgBorrowRate, uint256 rateAtTarget);

    uint256 internal constant MIN_TEST_AMOUNT = 100;
    uint256 internal constant MAX_TEST_AMOUNT = 1e28;
    uint256 internal constant MIN_TIME_ELAPSED = 10;
    uint256 internal constant MAX_TIME_ELAPSED = 315360000;
    uint256 internal constant DEFAULT_TEST_LLTV = 0.8 ether;

    address internal OWNER = makeAddr("Owner");
    address internal SUPPLIER = makeAddr("Supplier");
    address internal BORROWER = makeAddr("Borrower");

    IMorpho internal morpho = IMorpho(deployCode("Morpho.sol", abi.encode(OWNER)));
    ERC20Mock internal loanToken;
    ERC20Mock internal collateralToken;
    OracleMock internal oracle;

    IAdaptiveCurveIrm internal adaptiveCurveIrm =
        IAdaptiveCurveIrm(deployCode("AdaptiveCurveIrm.sol", abi.encode(address(morpho))));
    IFixedRateIrm public fixedRateIrm = IFixedRateIrm(deployCode("FixedRateIrm.sol"));

    function setUp() public {
        SUPPLIER = makeAddr("Supplier");
        BORROWER = makeAddr("Borrower");

        loanToken = new ERC20Mock();
        vm.label(address(loanToken), "LoanToken");

        collateralToken = new ERC20Mock();
        vm.label(address(collateralToken), "CollateralToken");

        oracle = new OracleMock();

        oracle.setPrice(ORACLE_PRICE_SCALE);

        morpho.enableIrm(address(adaptiveCurveIrm));
        morpho.enableIrm(address(fixedRateIrm));
        morpho.enableLltv(DEFAULT_TEST_LLTV);

        vm.prank(SUPPLIER);
        loanToken.approve(address(morpho), type(uint256).max);

        vm.startPrank(BORROWER);
        loanToken.approve(address(morpho), type(uint256).max);
        collateralToken.approve(address(morpho), type(uint256).max);
        vm.stopPrank();
    }

    /* TESTS */

    function testAdaptiveCurveIrm(uint256 amountSupplied, uint256 amountBorrowed, uint256 timeElapsed) public {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, amountSupplied);
        timeElapsed = bound(timeElapsed, MIN_TIME_ELAPSED, MAX_TIME_ELAPSED);

        MarketParams memory marketParams = MarketParams(
            address(loanToken), address(collateralToken), address(oracle), address(adaptiveCurveIrm), DEFAULT_TEST_LLTV
        );
        morpho.createMarket(marketParams);

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amountBorrowed.wDivUp(DEFAULT_TEST_LLTV);
        collateralToken.setBalance(BORROWER, collateralAmount);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.warp(timeElapsed);

        morpho.accrueInterest(marketParams);
    }

    function testFixedRateIrm(uint256 amountSupplied, uint256 amountBorrowed, uint256 fixedRate, uint256 timeElapsed)
        public
    {
        amountSupplied = bound(amountSupplied, MIN_TEST_AMOUNT, MAX_TEST_AMOUNT);
        amountBorrowed = bound(amountBorrowed, MIN_TEST_AMOUNT, amountSupplied);
        fixedRate = bound(timeElapsed, 1, fixedRateIrm.MAX_BORROW_RATE());
        timeElapsed = bound(timeElapsed, MIN_TIME_ELAPSED, MAX_TIME_ELAPSED);

        MarketParams memory marketParams = MarketParams(
            address(loanToken), address(collateralToken), address(oracle), address(fixedRateIrm), DEFAULT_TEST_LLTV
        );
        fixedRateIrm.setBorrowRate(marketParams.id(), fixedRate);
        morpho.createMarket(marketParams);

        loanToken.setBalance(SUPPLIER, amountSupplied);
        vm.prank(SUPPLIER);
        morpho.supply(marketParams, amountSupplied, 0, SUPPLIER, hex"");

        uint256 collateralAmount = amountBorrowed.wDivUp(DEFAULT_TEST_LLTV);
        collateralToken.setBalance(BORROWER, collateralAmount);

        vm.startPrank(BORROWER);
        morpho.supplyCollateral(marketParams, collateralAmount, BORROWER, hex"");
        morpho.borrow(marketParams, amountBorrowed, 0, BORROWER, BORROWER);
        vm.stopPrank();

        vm.warp(timeElapsed);

        morpho.accrueInterest(marketParams);
    }
}
