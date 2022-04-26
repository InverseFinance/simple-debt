// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "ds-test/test.sol";
import {Vm} from "forge-std/Vm.sol";
import {SimpleDebt, FedDebtManager} from "../SimpleDebt.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDola} from "../interfaces/IDola.sol";

interface IFed {
    function changeGov(address newGov_) external;

    function changeChair(address newChair_) external;

    function gov() external returns (address);
    function chair() external returns (address);
}

interface IYearnFed {
    function maxLossBpContraction() external returns (uint);
}

contract FedDebtManagerTest is DSTest {
    Vm public vm = Vm(HEVM_ADDRESS);

    IERC20 public DOLA = IERC20(0x865377367054516e17014CcdED1e7d814EDC9ce4);

    address public gov = 0x926dF14a23BE491164dCF93f4c468A50ef659D5B;
    address public twgPlaceholder = 0xfedCAD25E375EA259FC71aE834e302e501f8b20A;

    address public user = 0x69E30c9F6f6759aF33C19556b2d9Db65108637e5;

    address public anchorFed = 0x5E075E40D01c82B6Bf0B0ecdb4Eb1D6984357EF7;
    address public yearnFed = 0xcc180262347F84544c3a4854b87C34117ACADf94;

    SimpleDebt simpleDebt;
    FedDebtManager fedDebtManager;

    function setUp() public {
        simpleDebt = new SimpleDebt(address(DOLA), gov);
        fedDebtManager = new FedDebtManager(address(DOLA), gov);

        vm.startPrank(gov);
        simpleDebt.changeDebtor(twgPlaceholder);
        fedDebtManager.changeDebt(simpleDebt);
        // 25% payback
        fedDebtManager.setPaybackRatio(2500);

        //Set fedDebtManager as gov of anchorFed
        IFed(anchorFed).changeGov(address(fedDebtManager));

        //Add simpleDebt as minter
        IDola(address(DOLA)).addMinter(address(simpleDebt));
    }

    //Access Control Tests
    function testChangeDebtFromGov() public {
        vm.startPrank(gov);

        fedDebtManager.changeDebt(SimpleDebt(address(0)));
        require(address(fedDebtManager.debt()) == address(0));
    }

    function testFailChangeDebtFromNonGov() public {
        vm.startPrank(user);

        fedDebtManager.changeDebt(SimpleDebt(address(0)));
    }

    function testChangeGovFromGov() public {
        vm.startPrank(gov);

        fedDebtManager.changeGov(address(0));
        assert(fedDebtManager.gov() == address(0));
    }

    function testFailChangeGovFromNonGov() public {
        vm.startPrank(user);

        fedDebtManager.changeGov(address(0));
    }

    function testChangeFedGovFromGov() public {
        vm.startPrank(gov);

        fedDebtManager.changeFedGov(anchorFed, address(0));
        assert(IFed(anchorFed).gov() == address(0));
    }

    function testFailChangeFedGovFromNonGov() public {
        vm.startPrank(user);

        fedDebtManager.changeFedGov(anchorFed, address(0));
    }

    function testChangeFedChairFromGov() public {
        vm.startPrank(gov);

        fedDebtManager.changeFedChair(anchorFed, address(0));
        assert(IFed(anchorFed).chair() == address(0));
    }

    function testFailChangeFedChairFromNonGov() public {
        vm.startPrank(user);

        fedDebtManager.changeFedChair(anchorFed, address(0));
    }

    function testSetPaybackRatioFromGov() public {
        vm.startPrank(gov);

        fedDebtManager.setPaybackRatio(500);
        assert(fedDebtManager.paybackRatio() == 500);
    }

    function testFailSetPaybackRatioFromNonGov() public {
        vm.startPrank(user);

        fedDebtManager.setPaybackRatio(500);
    }

    function testCallExternalFromGov() public {
        vm.startPrank(gov);

        //Set yearn fed gov to fedDebtManager
        IFed(yearnFed).changeGov(address(fedDebtManager));

        bytes memory payload = abi.encodeWithSignature("setMaxLossBpContraction(uint256)", 100);
        fedDebtManager.callExternal(yearnFed, payload);

        assert(IYearnFed(yearnFed).maxLossBpContraction() == 100);
    }

    function testFailCallExternalFromNonGov() public {
        vm.startPrank(gov);

        //Set yearn fed gov to fedDebtManager
        IFed(yearnFed).changeGov(address(fedDebtManager));

        vm.startPrank(user);

        bytes memory payload = abi.encodeWithSignature("setMaxLossBpContraction(uint256)", 100);
        fedDebtManager.callExternal(yearnFed, payload);
    }

    //Sanity Tests
    function testDolaGarnishmentRespectsPaybackRatio() public {
        vm.startPrank(gov);

        //25% payback
        fedDebtManager.setPaybackRatio(2500);
        simpleDebt.addDebtCeiling(1000 * 10**18);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(1000 * 10**18);

        //Give 1,000 DOLA to fedDebtManager
        gibDOLA();

        uint256 prevOustandingDebt = simpleDebt.outstandingDebt();
        uint256 prevGovBalance = DOLA.balanceOf(gov);

        fedDebtManager.dolaGarnishment();

        //Assert 250/1000 (25%) of DOLA used for debt repayment, 750/1000 (75%) sent to gov
        assert(prevOustandingDebt - 250 * 10**18 == simpleDebt.outstandingDebt());
        assert(prevGovBalance + 750 * 10**18 == DOLA.balanceOf(gov));
    }

    function testFailDolaGarnishmentWith0UnderlyingBalance() public {
        vm.startPrank(gov);

        assert(DOLA.balanceOf(address(fedDebtManager)) == 0);

        fedDebtManager.dolaGarnishment();
    }

    function testDolaGarnishmentSendsAllFundsToGovAt0PaybackRatio() public {
        vm.startPrank(gov);

        //0% payback
        fedDebtManager.setPaybackRatio(0);
        simpleDebt.addDebtCeiling(1000 * 10**18);

        vm.startPrank(twgPlaceholder);
        simpleDebt.accrueDebt(1000 * 10**18);

        //Give 1,000 DOLA to fedDebtManager
        gibDOLA();

        uint256 prevOustandingDebt = simpleDebt.outstandingDebt();
        uint256 prevGovBalance = DOLA.balanceOf(gov);

        fedDebtManager.dolaGarnishment();

        //Assert 1000/1000 (100%) of DOLA is sent to GOV at 0 payback ratio
        assert(prevOustandingDebt == simpleDebt.outstandingDebt());
        assert(prevGovBalance + 1000 * 10**18 == DOLA.balanceOf(gov));
    }

    function testDolaGarnishmentGreaterThanOutstandingDebtSendsExcessToGov() public {
        vm.startPrank(gov);

        simpleDebt.addDebtCeiling(100 * 10**18);
        fedDebtManager.setPaybackRatio(2500);

        vm.startPrank(twgPlaceholder);

        simpleDebt.accrueDebt(100 * 10**18);

        gibDOLA();

        uint256 prevOustandingDebt = simpleDebt.outstandingDebt();
        uint256 prevGovBalance = DOLA.balanceOf(gov);

        fedDebtManager.dolaGarnishment();

        //100 DOLA should be used to pay the outstanding debts, with 900 being sent to gov since it's excess
        assert(prevOustandingDebt - 100 * 10**18 == simpleDebt.outstandingDebt());
        assert(prevGovBalance + 900 * 10**18 == DOLA.balanceOf(gov));
    }

    function testFailSetPaybackRatioAboveLimit() public {
        vm.startPrank(gov);

        fedDebtManager.setPaybackRatio(10001);
    }

    //Helper functions
    function gibDOLA() internal {
        address _fedDebtManager = address(fedDebtManager);

        //DOLA balances[fedDebtManager] slot
        bytes32 slot;
        assembly {
            mstore(0, _fedDebtManager)
            mstore(0x20, 0x6)
            slot := keccak256(0, 0x40)
        }
        
        vm.store(address(DOLA), slot, bytes32(uint256(1_000 * 10**18)));
        DOLA.balanceOf(address(fedDebtManager));
    }
}