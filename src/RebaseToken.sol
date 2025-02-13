//SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RebaseToken
 * @author yawarasuuna
 * @notice This is a cross-chain rebase token that incentivizes users to deposit into a vault and gain interest in rewards
 * @notice The interest rate in this smart contract can only decrease
 * @notice Each user will have their own interest rate that is the global interest rate at the time of deposit
 * @dev totalSupply() returns the sum of minted tokens, but does not include unminted interest accrual.
 */
contract RebaseToken is ERC20 {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    uint256 private s_interestRate = 5e10;
    uint256 private constant PRECISION_FACTOR = 1e18;
    mapping(address user => uint256 interestRate) private s_userInterestRate;
    mapping(address user => uint256 timestamp) private s_userLastUpdatedTimestamp;

    event SetInterestRate(uint256 newInterestRate);

    constructor() ERC20("Rtoken", "rRBT") {}

    /**
     * @notice Set the interest rate in the contract
     * @param _newInterestRate The new interest rate to set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external {
        // set interest rate
        if (_newInterestRate < s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit SetInterestRate(_newInterestRate);
    }

    /**
     * @notice Get the principle balance of a user. This is the number of tokens that currently have been minted to the user, not including any interest that has accrued since the last time the user interacted with the protocol
     * @param _user The user to get the principle balance for
     * @return The principle balance of the user
     */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    /**
     * @notice Mint the user tokens when they deposit into the vault
     * @param _to The user to mint th tokens to
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = s_interestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice Burn the user tokens when they withdraw from the vault
     * @param _from The user to burn the tokens from
     * @param _amount The amount of tokens to burn
     */
    function burn(address _from, uint256 _amount) external {
        if (_amount == type(uint256).max) {
            // avoids dust
            _amount = balanceOf(_from);
        }
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    // super keyword finds function in the contract we are inheriting and call it, only works if it overrides another fx
    function balanceOf(address _user) public view override returns (uint256) {
        return (super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user)) / PRECISION_FACTOR;
    }

    /**
     * @notice Transfer tokens form one user to another
     * @param _recipient The user to transfer the tokens to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transfer(address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice Transfer tokens from one user to another
     * @param _sender The user to transfer the token from
     * @param _recipient The user to transfer the token to
     * @param _amount The amount of tokens to transfer
     * @return True if the transfer was successful
     */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0) {
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /**
     * @notice Calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest accumulated for
     * @return linearInterest The interest that has accumulated since the last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user)
        internal
        view
        returns (uint256 linearInterest)
    {
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        linearInterest = PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed);
    }

    /**
     * @notice Mint accrued interest to the user since the last time they interacted with the protocol, e.g. burn, mint, transfer
     * @param _user The user to min the accrued interest to
     */
    function _mintAccruedInterest(address _user) internal {
        uint256 previousPrincipalBalance = super.balanceOf(_user);
        uint256 currentBalance = balanceOf(_user);
        uint256 accruedInterestSinceLastUpdate = currentBalance - previousPrincipalBalance;
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, accruedInterestSinceLastUpdate);
    }

    /**
     * @notice Get the interest rate that is currently set for the contract. Any future depositors will receive this interest rate
     * @return The interes rate for the contract
     */
    function getInterestRate() external view returns(uint256) {
        return s_interestRate;
    }

    /**
     * @notice Get the interest rate for the user
     * @param _user The user to get the interest rate for
     * @return The interest rate for the user
     */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[address(_user)];
    }
}
