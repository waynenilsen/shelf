pragma solidity ^0.8.4;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {InterestRateModel} from "./InterestRateModel.sol";

struct TokenStorage {
    ERC20 theContract;
    // exchange rate to USD, 6 decimals
    int256 exchangeRate;
    // this is an interest index, it starts from 1 and increases over time
    int256 index;
    // when the token was added
    uint256 blockStart;
    // protocol debt level
    int256 debt;
    // protocol total deposits
    int256 totalDeposits;
    // last interest rate
    int256 currentInterestRate;
}

contract Shelf {
    // token data
    mapping(address => TokenStorage) public tokenData;
    // all token array
    address[] public allTokens;
    // all user balances by token - these are time zero balances
    mapping(address => mapping(address => int256)) public balances;

    // margin percentage
    int256 public marginRequirement;

    // all calculations use 8 decimals within the contract
    uint256 public constant INTERNAL_DECIMALS = 8;
    // the scalar for internal calculations
    int256 public constant INTERNAL_SCALAR = int256(10 ** INTERNAL_DECIMALS);
    // this is a rough estimate of the number of blocks per year, obviously this can vary
    int256 public constant BLOCKS_PER_YEAR = 7140 * 365;

    // temporary admin key will upgrade to gov or dao but this is for proof of concept
    address public admin;

    InterestRateModel public interestRateModel;

    // constructor
    constructor(int256 _marginRequirement, address _interestRateModel) {
        admin = msg.sender;
        marginRequirement = _marginRequirement;
        interestRateModel = InterestRateModel(_interestRateModel);
    }

    /**
     * @notice adds a token to the allowed tokens on the shelf
     * @param _token the token to add
     * @param _exchangeRate the exchange rate of the token to USD, 6 decimals
     */
    function addToken(address _token, int256 _exchangeRate) external {
        require(msg.sender == admin, "only admin");
        require(tokenData[_token].index == 0, "token already added");
        TokenStorage memory storageToken =
            TokenStorage(ERC20(_token), _exchangeRate, INTERNAL_SCALAR, block.number, 0, 0, 0);
        tokenData[_token] = storageToken;
        allTokens.push(_token);
    }

    /**
     * @notice updates the exchange rate of a token, eventually we will have to decentralize of course
     * @param _token the token to update
     * @param _exchangeRate the new exchange rate of the token to USD, 6 decimals
     */
    function updateExchangeRate(address _token, int256 _exchangeRate) external {
        require(msg.sender == admin, "only admin");
        require(tokenData[_token].index != 0, "token not added");
        tokenData[_token].exchangeRate = _exchangeRate;
    }

    /**
     * @notice deflates a token amount to time zero
     * @param _token the token to deflate
     * @param amount the amount to deflate
     */
    function deflate(address _token, int256 amount) external view returns (int256) {
        require(tokenData[_token].index != 0, "token not added");
        return amount * INTERNAL_SCALAR / tokenData[_token].index;
    }

    /**
     * @notice inflates a token amount from time zero to current time
     * @param _token the token to inflate
     * @param amount the amount to inflate
     */
    function inflate(address _token, int256 amount) external view returns (int256) {
        require(tokenData[_token].index != 0, "token not added");
        return amount * tokenData[_token].index / INTERNAL_SCALAR;
    }

    /**
     * @notice converts a token amount to USD
     * @param _token the token to convert
     * @param amount the amount to convert
     */
    function toUsd(address _token, int256 amount) external view returns (int256) {
        require(tokenData[_token].index != 0, "token not added");
        return amount * tokenData[_token].exchangeRate / int256(int8(tokenData[_token].theContract.decimals()));
    }

    /**
     * @notice Returns the current balance of a user on Shelf in today's value.
     * @param _user the user to get the balance for
     * @param _token the token to get the balance for
     */
    function currentBalance(address _user, address _token) external view returns (int256) {
        return this.inflate(_token, balances[_token][_user]);
    }

    /**
     * @notice Returns the current balance of a user on Shelf in today's value in USD, 6 decimals.
     * @param _user the user to get the balance for
     * @param _token the token to get the balance for
     */
    function currentUsdValue(address _user, address _token) external view returns (int256) {
        return this.toUsd(_token, this.currentBalance(_user, _token));
    }

    /**
     * @notice deposit tokens to the shelf
     * @param _token the token to deposit
     * @param _amount the amount to deposit
     */
    function deposit(address _token, int256 _amount) external {
        require(tokenData[_token].index != 0, "token not added");
        require(_amount > 0, "amount must be positive");

        balances[_token][msg.sender] += _amount;
        tokenData[_token].totalDeposits += _amount;

        require(
            tokenData[_token].theContract.transferFrom(msg.sender, address(this), uint256(_amount)), "transfer failed"
        );
    }

    /**
     * @notice get the current utilization of a token
     * @param _token the token to get the utilization for
     * @return the utilization of the token, 18 decimals
     */
    function getUtilization(address _token) external view returns (int256) {
        require(tokenData[_token].index != 0, "token not added");

        if (tokenData[_token].totalDeposits == 0) {
            return 0;
        }

        return tokenData[_token].debt * INTERNAL_SCALAR / tokenData[_token].totalDeposits;
    }

    /**
     * @notice calculate the function exp, only works well in the vacinity of x = 0
     * @param x the input to the exp function
     * @param scalar the number of decimals used in the fractional representation of x
     */
    function exp(int256 x, int256 scalar) internal pure returns (int256) {
        // use a 3 term taylor series expansion, do not forget to divide by the scalar as you go
        return scalar + x + x * x / (2 * scalar) + x * x * x / (6 * scalar * scalar);
    }

    /**
     * @notice compound interest for a token updates the interest rate and applies it to the index
     * @param _token the token to compound interest for
     */
    function compoundInterest(address _token) external {
        // valid token check
        require(tokenData[_token].index != 0, "token not added");
        // admin only check
        require(msg.sender == admin, "only admin");
        // interest rate model check
        require(address(interestRateModel) != address(0), "interest rate model not set");

        int256 currentUtilization = this.getUtilization(_token);
        int256 nextInterestRate = interestRateModel.getCurrentInterestRate(
            currentUtilization,
            8 * INTERNAL_SCALAR / 10,
            block.number - tokenData[_token].blockStart,
            tokenData[_token].currentInterestRate
        );
        uint256 changeInBlocks = block.number - tokenData[_token].blockStart;
        int256 rateTimesTime = nextInterestRate * int256(changeInBlocks) / BLOCKS_PER_YEAR;
        // e^{r\delta t}
        int256 multiplier = Shelf.exp(rateTimesTime, INTERNAL_SCALAR);
        // update the interest index
        tokenData[_token].index = tokenData[_token].index * multiplier / INTERNAL_SCALAR;
        // update the interest rate
        tokenData[_token].currentInterestRate = nextInterestRate;
        // update the block start
        tokenData[_token].blockStart = block.number;
    }

    function getInterestIndex(address _token) external view returns (int256) {
        require(tokenData[_token].index != 0, "token not added");

        return tokenData[_token].index;
    }

    /**
     * @notice This function computes the collateralization ratio for a given account.
     * @param _user the user to compute the collateralization ratio for
     * @param _tokenToChange the token to change the balance of (if any, supply 0x0 for no change)
     * @param _amountToChange the amount to change the balance of (if any, supply 0 for no change)
     */
    function collateralizationRatio(address _user, address _tokenToChange, int256 _amountToChange)
        external
        view
        returns (int256)
    {
        int256 totalCollateralValue = 0;
        int256 totalDebtValue = 0;

        for (uint256 i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];
            int256 userCurrentBalance = this.currentBalance(_user, token);
            // if it is the token to change, bump the balance
            if (token == _tokenToChange) {
                userCurrentBalance += _amountToChange;
            }

            int256 tokenValue = this.toUsd(token, userCurrentBalance);
            if (tokenValue > 0) {
                totalCollateralValue += tokenValue;
            } else {
                totalDebtValue += -1 * tokenValue;
            }
        }

        // if the account has no debt return the margin requirement, the account has permission to do as it pleases
        if (totalDebtValue == 0) {
            return marginRequirement;
        }

        return totalCollateralValue * INTERNAL_SCALAR / totalDebtValue;
    }

    /**
     * @notice This function computes the collateralization ratio for a given account.
     * @param _user the user to compute the collateralization ratio for
     */
    function collateralizationRatio(address _user) external view returns (int256) {
        return this.collateralizationRatio(_user, address(0), 0);
    }

    /**
     * @notice withdraw tokens from the shelf. You can withdraw more than you have deposited if you have sufficient collateral in the other token(s). In
     *  this case you take out debt against the protocol and you will be required to pay interest.
     * @param _token the token to withdraw
     * @param amount the amount to withdraw
     */
    function withdraw(address _token, int256 amount) external {
        require(tokenData[_token].index != 0, "token not added");
        require(amount > 0, "amount must be positive");
        require(
            this.collateralizationRatio(msg.sender, _token, -1 * amount) >= marginRequirement, "undercollateralized"
        );

        balances[_token][msg.sender] -= this.deflate(_token, amount);
        int256 _currentBalance = this.currentBalance(msg.sender, _token);

        if (_currentBalance >= amount) {
            tokenData[_token].totalDeposits -= amount;
        } else {
            tokenData[_token].totalDeposits -= _currentBalance;
            tokenData[_token].debt += amount - _currentBalance;
        }

        bool ok = tokenData[_token].theContract.transfer(msg.sender, uint256(amount));
        // this can happen when the protocol is underwater
        //  we should consider this state and allow for a protocol unwind state
        require(ok, "transfer failed");
    }

    /**
     * @notice liquidate an account, the liquidatee must be undercollateralized and the calling account must be in good standing
     * @param _user the user to liquidate
     */
    function liquidate(address _user) external {
        // this account must be in good standing
        require(this.collateralizationRatio(msg.sender) >= marginRequirement, "liquidator is undercollateralized");
        // the liquidatee must be undercollateralized
        require(this.collateralizationRatio(_user) < marginRequirement, "the liquidatee is not undercollateralized");

        for (uint256 i = 0; i < allTokens.length; i++) {
            address token = allTokens[i];
            balances[token][msg.sender] += balances[token][_user];
            balances[token][_user] = 0;
        }

        // ensure that after having taken over the account, the liquidator is in good standing
        require(
            this.collateralizationRatio(msg.sender) >= marginRequirement,
            "liquidator is undercollateralized after taking over the account"
        );
    }
}
