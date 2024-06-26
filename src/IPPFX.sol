// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

/**
 * @dev Interface of the PPFX contract
 */
interface IPPFX {
    event NewOperator(address indexed newOperatorAddress);
    event OperatorRemoved(address indexed operatorAddr);
    
    event NewTreasury(address indexed newTreasuryAddress);
    event NewAdmin(address indexed newAdminAddress);
    event NewInsurance(address indexed newInsuranceAddress);
    event NewWithdrawHook(address indexed newWithdrawHookAddress);
    event NewUSDT(address indexed newUSDTAddress);
    event NewMarketAdded(bytes32 market, string marketName);
    event NewWithdrawalWaitTime(uint256 newWaitTime);
    event NewMinimumOrderAmount(uint256 newMinOrderAmt);
    event TransferAdmin(address indexed newAdminAddress);

    event UserDeposit(address indexed user, uint256 amount);
    event UserWithdrawal(address indexed user, uint256 amount, uint256 withdrawAt);
    event UserClaimedWithdrawal(address indexed user, address recipient, uint256 amount, uint256 claimedAt);

    event PositionAdded(address indexed user, string market, uint256 size, uint256 fee);
    event PositionReduced(address indexed user, string market, uint256 size, uint256 fee);

    event OrderFilled(address indexed user, string market, uint256 fee);

    event OrderCancelled(address indexed user, string market, uint256 size, uint256 fee);

    event FundingSettled(address indexed user, string market, uint256 amount);
    event CollateralAdded(address indexed user, string market, uint256 amount);
    event CollateralDeducted(address indexed user, string market, uint256 amount);

    event Liquidated(address indexed user, string market, uint256 amount, uint256 fee);

    event BulkProcessFailedTxInvalidSignature(uint256 indexed txIndex, bytes sig);
    event BulkProcessFailedTxSelectorNotFound(uint256 indexed txIndex, bytes4 methodID);
    event BulkProcessFailedTxReverted(uint256 indexed txIndex, bytes data);

    event WithdrawalBalanceReduced(address indexed user, uint256 amount);

    /**
     * @dev Delegate Data used in withdrawForUser / claimPendingWithdrawalForUser
     * @param from signer address
     * @param delegate address delegating to
     * @param amount amount withdrawing, use 0 when claiming
     * @param deadline block timestamp on when the signature shouldn't be active anymore
     * @param signature signed getWithdrawHash() / getClaimHash()
     */
    struct DelegateData {
        address from;
        address delegate;
        uint256 amount;
        uint48 deadline;
        bytes signature;
    }

    /**
     * @dev Get Sender total trading balance.
     * @return Sum of sender's trading balance across all available markets.
     */
    function getTradingBalance(address target) external view returns (uint256);

    /**
     * @dev Get target address funding balance.
     * @return Target's funding balance.
     */
    function userFundingBalance(address target) external view returns (uint256);

    /**
     * @dev Get Sender total balance.
     * @return Sum of sender's sum of total trading balance and funding balance.
     */
    function totalBalance(address target) external view returns (uint256);

    /**
     * @dev Get total numbers of available markets.
     * @return The number of available markets.
     */
    function totalMarkets() external view returns (uint256);

    /**
     * @dev Get all available markets.
     */
    function getAllMarkets() external view returns (bytes32[] memory);

    /**
     * @dev Initiate a deposit.
     * @param amount The amount of USDT to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Initiate a withdrawal.
     * @param amount The amount of USDT to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Claim all pending withdrawal
     */
    function claimPendingWithdrawal() external;

    /**
     * @dev Initiate a deposit for user.
     * @param user The target address to deposit to
     * @param amount The amount of USDT to deposit
     */
    function depositForUser(address user, uint256 amount) external;

    /**
     * @dev Initiate a withdrawal for user.
     * @param delegate The delegated address to initiate the withdrawal
     * @param user The target address to withdraw from
     * @param amount The amount of USDT to withdraw
     * @param delegateData Delegate Data from the user
     */
    function withdrawForUser(address delegate, address user, uint256 amount, DelegateData calldata delegateData) external;

    /**
     * @dev Claim all pending withdrawal for target user
     * Throw if no available pending withdrawal / invalid delegate data / signature
     * @param delegate The delegated address to claim pending withdrawal
     * @param user The target address to claim pending withdrawal from
     * @param delegateData Delegate Data from the user
     */
    function claimPendingWithdrawalForUser(address delegate, address user, DelegateData calldata delegateData) external;
}