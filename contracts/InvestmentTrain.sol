// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract InvestmentTrain {
    struct Investor {
        address payable investorAddress;
        uint256 investedAmount;
        uint256 dividendAmountPayed;
        uint256 dividendAmountAvailable;
        uint256 lastDividendClaimed;
    }

    struct Train {
        uint256 startDate;
        uint256 totalEquity;
        uint256 minimumEquityForStart;
        uint256 dividendsAnnualInterestRate; // 4 digits, e.g., 3000 for 30%
        bool isPending;
        bool isStarted;
        bool isCompleted;
    }

    address public admin;
    IERC20 public usdtToken;
    bool public isEarlyWithdrawEnabled = false;

    uint256 public nextTrainId = 1;
    mapping(uint256 => Train) public trains;
    mapping(uint256 => Investor[]) public trainInvestors;

    uint256 public constant MIN_EQUITY = 500000 * 10 ** 6; // Adjusted for USDT (6 decimals)
    uint256 public constant LOCK_PERIOD = 365 days;
    uint256 public constant ANNUAL_INTEREST_RATE = 30;
    uint256 public constant DIVIDEND_INTERVAL = 30 days;

    event EarlyWithdrawalStatusChanged(address admin, bool status);
    event NewInvestment(uint256 trainId, address investor, uint256 amount);
    event InvestmentTrainStarted(uint256 trainId, uint256 startWithEquity, address admin);
    event InvestmentTrainCompleted(uint256 trainId, address admin);

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can call this function.");
        _;
    }

    constructor(address _usdtToken) {
        admin = msg.sender;
        usdtToken = IERC20(_usdtToken);
    }

    function setEarlyWithdrawEnabled(bool enabled) external onlyAdmin {
        isEarlyWithdrawEnabled = enabled;
        emit EarlyWithdrawalStatusChanged(msg.sender, enabled);
    }

    function invest(uint256 trainId, uint256 usdtAmount) external {
        require(
            trains[trainId].startDate == 0,
            "Train has already started. Wait for the next one."
        );
        require(
            trains[trainId].isPending,
            "Train hasn't activated for investment. Wait for the next one."
        );

        // Transfer USDT from investor to contract
        require(
            usdtToken.transferFrom(msg.sender, address(this), usdtAmount),
            "USDT transfer failed"
        );

        // Check for existing investor in the specified trainId
        bool isInvestorExisting = false;
        for (uint i = 0; i < trainInvestors[trainId].length; i++) {
            if (trainInvestors[trainId][i].investorAddress == msg.sender) {
                trainInvestors[trainId][i].investedAmount += usdtAmount;
                isInvestorExisting = true;
                break;
            }
        }

        if (!isInvestorExisting) {
            trainInvestors[trainId].push(
                Investor({
                    investorAddress: payable(msg.sender),
                    investedAmount: usdtAmount,
                    dividendAmountPayed: 0,
                    dividendAmountAvailable: 0,
                    lastDividendClaimed: block.timestamp
                })
            );
        }

        trains[trainId].totalEquity += usdtAmount;
        emit NewInvestment(trainId, msg.sender, usdtAmount);
    }

    function createNewTrain(
        uint256 minimumEquityForStart,
        uint256 dividendsAnnualInterestRate
    ) external onlyAdmin returns (uint256) {
        trains[nextTrainId] = Train(
            0,
            0,
            minimumEquityForStart,
            dividendsAnnualInterestRate,
            true,
            false,
            false
        );
        nextTrainId++;
        return nextTrainId - 1;
    }

    function startTrain(uint256 trainId) external onlyAdmin {
        require(
            trains[trainId].totalEquity >= trains[trainId].minimumEquityForStart,
            "Minimum equity not reached."
        );
        require(trains[trainId].isPending, "Train is not in a pending state.");

        trains[trainId].startDate = block.timestamp;
        trains[trainId].isStarted = true;
        trains[trainId].isPending = false;
        emit InvestmentTrainStarted(trainId, trains[trainId].totalEquity, msg.sender);
    }

    function completeTrain(uint256 trainId) external onlyAdmin {
        require(trains[trainId].isStarted, "Train has not started.");
        require(
            !trains[trainId].isCompleted,
            "Train has already been completed."
        );

        trains[trainId].isCompleted = true;
        emit InvestmentTrainCompleted(trainId, msg.sender);
    }

    function claimDividends(uint256 trainId) external {
        Train storage train = trains[trainId];

        // Ensure the train is started but not completed
        require(
            train.isStarted && !train.isCompleted,
            "Train is not in the correct state for dividends."
        );

        // Initialize dividend amount
        uint256 dividendAmount = 0;

        // Loop through the investors of the train to find the matching investor
        for (uint i = 0; i < trainInvestors[trainId].length; i++) {
            if (trainInvestors[trainId][i].investorAddress == msg.sender) {
                Investor storage investor = trainInvestors[trainId][i];

                // Calculate the number of months since the last dividend claim
                uint256 monthsSinceLastClaim = (block.timestamp - investor.lastDividendClaimed) / DIVIDEND_INTERVAL;

                // Calculate monthly dividend
                uint256 monthlyDividend = ((train.dividendsAnnualInterestRate / 12) * investor.investedAmount) / 10000;

                // Calculate total dividend
                dividendAmount = monthsSinceLastClaim * monthlyDividend;

                // Update last dividend claimed timestamp
                investor.lastDividendClaimed = block.timestamp;
                investor.dividendAmountPayed += dividendAmount;

                // Transfer the dividends
                require(
                    usdtToken.transfer(msg.sender, dividendAmount),
                    "Dividend transfer failed."
                );

                break;
            }
        }

        require(
            dividendAmount > 0,
            "No dividends to claim or you are not an investor in this train."
        );
    }

    function withdraw(uint256 trainId) external {
        require(trains[trainId].isStarted || isEarlyWithdrawEnabled, "Train has not started.");
        require(
            block.timestamp - trains[trainId].startDate >= LOCK_PERIOD || isEarlyWithdrawEnabled,
            "Cannot withdraw during locked period."
        );

        uint256 withdrawalAmount = 0;
        for (uint i = 0; i < trainInvestors[trainId].length; i++) {
            if (trainInvestors[trainId][i].investorAddress == msg.sender) {
                withdrawalAmount = trainInvestors[trainId][i].investedAmount;
                trainInvestors[trainId][i].investedAmount = 0;

                require(
                    usdtToken.transfer(msg.sender, withdrawalAmount),
                    "Withdrawal transfer failed."
                );
                break;
            }
        }

        require(
            withdrawalAmount > 0,
            "Nothing to withdraw or you are not an investor."
        );
    }

    function getTotalEquity(uint256 trainId) external view returns (uint256) {
        require(!trains[trainId].isStarted, "Train has already started.");
        return trains[trainId].totalEquity;
    }

    function getTotalAvailableDividends(
        uint256 trainId,
        address investorAddress
    ) public view returns (uint256) {
        Train storage train = trains[trainId];

        // Ensure the train is started but not completed
        require(
            train.isStarted && !train.isCompleted,
            "Train is not in the correct state for dividends."
        );

        // Loop through the investors of the train to find the matching investor
        for (uint i = 0; i < trainInvestors[trainId].length; i++) {
            if (trainInvestors[trainId][i].investorAddress == investorAddress) {
                Investor storage investor = trainInvestors[trainId][i];

                // Calculate the number of months since the last dividend claim
                uint256 monthsSinceLastClaim = (block.timestamp - investor.lastDividendClaimed) / DIVIDEND_INTERVAL;

                // Calculate monthly dividend (((3000 / 12)*2000)/10000)*12
                uint256 monthlyDividend = ((train.dividendsAnnualInterestRate / 12) * investor.investedAmount) / 10000;

                // Return total available dividends
                return monthsSinceLastClaim * monthlyDividend;
            }
        }

        revert("Investor not found in this train.");
    }
}
