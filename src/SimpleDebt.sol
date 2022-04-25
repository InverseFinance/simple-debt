//SPDX-License-Identifier: None

pragma solidity ^0.8.9;

import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";

interface IERC20Mintable is IERC20 {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;
}

interface IFed {
    function changeGov(address newGov_) external;

    function changeChair(address newChair_) external;
}

/**
 * @title Inverse Finance Simple Debt Contract
 * @notice Allows debtor to incur debt in underlying.
 *         Governance controls maximum debt.
 *         Anyone can repay debt.
 */

contract SimpleDebt {

    IERC20Mintable public underlying;
    address public gov;
    address public debtor;

    uint256 public outstandingDebt;
    uint256 public debtCeiling;

    event AddDebt(address debtor, uint256 amount, uint256 outstandingDebt);
    event ReduceDebt(address payor, uint256 amount, uint256 outstandingDebt);
    event AddDebtCeiling(address gov, uint256 amount, uint256 debtCeiling);
    event ReduceDebtCeiling(address gov, uint256 amount, uint256 debtCeiling);
    event ChangeDebtor(address gov, address oldDebtor, address newDebtor);

    constructor(address underlying_, address gov_) {
        underlying = IERC20Mintable(underlying_);
        gov = gov_;
    }

    modifier onlyGovernance() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    /**
     * @notice Allows governance to reassign governance
     * @param newGov_ The address of the debtor
     */
    function changeGov(address newGov_) public onlyGovernance {
        gov = newGov_;
    }

    /**
     * @notice Allows governance to reassign the debtor
     * @param newDebtor_ The address of the debtor
     */
    function changeDebtor(address newDebtor_) public onlyGovernance {
        emit ChangeDebtor(gov, debtor, newDebtor_);
        debtor = newDebtor_;
    }

    /**
     * @notice Allows governance to add to the debt ceiling
     * @param amount The amount to add to the debt ceiling
     */
    function addDebtCeiling(uint256 amount) public onlyGovernance {
        debtCeiling += amount;
        emit AddDebtCeiling(gov, amount, debtCeiling);
    }

    /**
     * @notice Allows governance to reduce the debt ceiling
     * @param amount The amount to remove from the debt ceiling
     */
    function reduceDebtCeiling(uint256 amount) public onlyGovernance {
        require(debtCeiling >= outstandingDebt, "CEILING < DEBT");
        debtCeiling -= amount;
        emit ReduceDebtCeiling(gov, amount, debtCeiling);
    }

    /**
     * @notice Allows debtor to accrue debt by minting underlying
     * @param amount The amount of debt to accrue
     */
    function accrueDebt(uint256 amount) public {
        require(msg.sender == debtor, "ONLY DEBTOR");
        underlying.mint(debtor, amount);
        outstandingDebt += amount;
        require(outstandingDebt <= debtCeiling, "TOO MUCH DEBT");
        emit AddDebt(debtor, amount, outstandingDebt);
    }

    /**
     * @notice Allows *ANYONE* to reduce debt by burning underlying
     * @param amount The amount of debt to reduce
     */
    function repayDebt(uint256 amount) public {
        require(amount <= outstandingDebt, "AMOUNT GREATER THAN DEBT");
        outstandingDebt -= outstandingDebt;
        emit ReduceDebt(msg.sender, amount, outstandingDebt);

        SafeERC20.safeTransferFrom(
            underlying,
            msg.sender,
            address(this),
            amount
        );

        underlying.burn(amount);
    }
}

/**
 * @title Inverse Finance Fed Debt Manager Contract
 * @notice Acts as an intermediary between Fed and Treasury to garnish
 *         profits to pay-off debt.
 */

contract FedDebtManager {
    uint256 public constant PAYBACK_RATIO_DENOMINATOR = 10000;

    IERC20Mintable public underlying;
    SimpleDebt public debt;
    address public gov;

    uint256 public paybackRatio;

    event DolaGarnishment(address gov, uint256 debtPayment, uint256 profit);

    constructor(address underlying_, address gov_) {
        underlying = IERC20Mintable(underlying_);
        gov = gov_;
    }

    modifier onlyGovernance() {
        require(msg.sender == gov, "ONLY GOV");
        _;
    }

    function changeDebt(SimpleDebt debt_) public onlyGovernance {
        debt = debt_;
    }

    function changeGov(address newGov_) public onlyGovernance {
        gov = newGov_;
    }

    function changeFedGov(IFed fed, address newFedGov_) public onlyGovernance {
        fed.changeGov(newFedGov_);
    }

    function changeFedChair(IFed fed, address newFedChair_)
        public
        onlyGovernance
    {
        fed.changeChair(newFedChair_);
    }

    function setPaybackRatio(uint256 amount) public onlyGovernance {
        require(amount <= PAYBACK_RATIO_DENOMINATOR, "amount too high");
        paybackRatio = amount;
    }

    /**
     * @notice Garnishes profits destined for treasury to pay off debt (if any).
     */
    function dolaGarnishment() public {
        uint256 profit = underlying.balanceOf(address(this));
        uint256 debtPayment;
        require(profit > 0, "no profit");

        if (paybackRatio > 0) {
            uint256 outstandingDebt = debt.outstandingDebt();

            debtPayment = Math.min(
                profit * paybackRatio / PAYBACK_RATIO_DENOMINATOR,
                outstandingDebt
            );

            profit -= debtPayment;

            if (debtPayment > 0) {
                SafeERC20.safeApprove(underlying, address(debt), debtPayment);
                debt.repayDebt(debtPayment);
            }
        }

        underlying.transfer(gov, profit);
        emit DolaGarnishment(gov, debtPayment, profit);
    }
    
    /**
     * @notice Allows Governance to make arbitrary function calls on behalf of this contract
     * @dev the data parameter can be calculated off chain, with the correct function selector
     * This function will be successful if calling an empty callback function, which can happen
     * if given a data parameter that doesnt correspond to any function.
     */
    function callExternal(address advancedFed, bytes memory data) public onlyGovernance{
        (bool success, ) = advancedFed.call(data);
        require(success);
    }
}
