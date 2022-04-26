// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SimpleDebt} from "../SimpleDebt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDola} from "../interfaces/IDola.sol";

contract SimpleDebtTest is DSTest {
    Vm public vm = Vm(HEVM_ADDRESS);

    IERC20 public DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);
    address public dolaOperator = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public twgPlaceholder = 0xfedCAD25E375EA259FC71aE834e302e501f8b20A;

    address public user = 0x69E30c9F6f6759aF33C19556b2d9Db65108637e5;

    SimpleDebt simpleDebt;

    function setUp() public {
        simpleDebt = new SimpleDebt(address(DOLA), gov);

        vm.startPrank(dolaOperator);
        IDola(address(DOLA)).addMinter(address(simpleDebt));
    }

    // Access Control Tests
    function testChangeGovFromGov() public {
        vm.startPrank(gov);

        simpleDebt.changeGov(user);
        assert(simpleDebt.gov() == user);
    }

    function testFailChangeGovFromNonGov() public {
        vm.startPrank(user);

        simpleDebt.changeGov(user);
    }

    function testChangeDebtFromGov() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(user);
        assert(simpleDebt.debtor() == user);
    }

    function testFailChangeDebtFromNonGov() public {
        vm.startPrank(user);

        simpleDebt.changeDebtor(user);
    }

    function testAddDebtCeilingFromGov() public {
        vm.startPrank(gov);

        uint256 prevCeiling = simpleDebt.debtCeiling();

        simpleDebt.addDebtCeiling(100);
        assert(prevCeiling + 100 == simpleDebt.debtCeiling());
    }

    function testFailAddDebtCeilingFromNonGov() public {
        vm.startPrank(user);

        simpleDebt.addDebtCeiling(100);
    }

    function testReduceDebtCeilingFromGov() public {
        vm.startPrank(gov);

        simpleDebt.addDebtCeiling(100);
        simpleDebt.reduceDebtCeiling(100);
        assert(simpleDebt.debtCeiling() == 0);
    }

    function testFailReduceDebtCeilingFromNonGov() public {
        vm.startPrank(gov);

        simpleDebt.addDebtCeiling(100);

        vm.startPrank(user);

        simpleDebt.reduceDebtCeiling(100);
    }

    function testAccrueDebtFromDebtor() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(100);

        vm.startPrank(twgPlaceholder);

        uint256 prevDolaBal = DOLA.balanceOf(twgPlaceholder);

        simpleDebt.accrueDebt(100);

        assert(prevDolaBal + 100 == DOLA.balanceOf(twgPlaceholder));
        assert(simpleDebt.outstandingDebt() == 100);
    }

    function testFailAccrueDebtFromNonDebtor() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(100);

        vm.startPrank(user);

        simpleDebt.accrueDebt(100);
    }

    // Sanity Tests
    function testFailReduceDebtCeilingWhileOutstandingDebtGTNewCeiling() public {
        vm.startPrank(gov);

        simpleDebt.addDebtCeiling(100);
        simpleDebt.reduceDebtCeiling(101);
    }

    function testReduceDebtCeilingToExactlyOutstandingDebt() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(200);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(100);

        vm.startPrank(gov);
        simpleDebt.reduceDebtCeiling(100);

        assert(simpleDebt.debtCeiling() == 100);
        assert(simpleDebt.outstandingDebt() == 100);
    }

    function testAccrueDebtMintsDolaEqualToDebtAmount() public {
        vm.startPrank(gov);
        
        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(100);

        uint256 prevOutstandingDebt = simpleDebt.outstandingDebt();
        uint256 prevDolaBal = DOLA.balanceOf(twgPlaceholder);

        vm.startPrank(twgPlaceholder);

        simpleDebt.accrueDebt(100);

        assert(prevOutstandingDebt + 100 == simpleDebt.outstandingDebt());
        assert(prevDolaBal + 100 == DOLA.balanceOf(twgPlaceholder));
    }

    function testFailAccrueDebtAboveDebtCeiling() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(100);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(101);
    }

    function testFailRepayDebtAboveOutstandingDebt() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(200);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(100);

        DOLA.approve(address(simpleDebt), type(uint256).max);

        simpleDebt.repayDebt(101);
    }

    function testRepayDebtBurnsUnderlyingEqualToDebtRepaid() public {
        vm.startPrank(gov);

        simpleDebt.changeDebtor(twgPlaceholder);
        simpleDebt.addDebtCeiling(100);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(100);

        DOLA.approve(address(simpleDebt), type(uint256).max);
        uint256 prevDolaSupply = DOLA.totalSupply();
        uint256 prevOutstandingDebt = simpleDebt.outstandingDebt();

        simpleDebt.repayDebt(100);

        assert(prevDolaSupply - 100 == DOLA.totalSupply());
        assert(prevOutstandingDebt - 100 == simpleDebt.outstandingDebt());
    }
}
