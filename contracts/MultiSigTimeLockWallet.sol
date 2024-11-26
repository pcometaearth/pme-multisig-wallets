// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MultiSigTimeLockWallet
 * @dev This contract is designed to manage multi-signature wallet operations and locking duration.
 *
 * The contract supports four types of multi-sig requests:
 * - Adding a new signer using `addSigner` function.
 * - Removing a signer using `removeSigner` function.
 * - Setting (changing) the required signatures count using `setRequiredSigs` function.
 * - Withdrawal using `withdraw` function.
 *
 * To initiate a new request, one of the signers must call the corresponding function first.
 * This action adds the request to the `pendingRequests` mapping with a unique request ID.
 *
 * To sign a pending request, the remaining signer(s) must call the `signRequest` function, passing the request ID as an argument.
 * The request ID can be obtained by calling the `pendingRequests` function (the getter for the respective mapping), which provides details on all pending requests.
 *
 * The locking duration for tokens is set to 10 years, with 10% of the tokens becoming releasable each year until the end of the 10-year period.
 *
 * To make the balance available for withdrawal after each lock period (1 year at a time) before initiating a withdrawal request, a signer must call the `unlockBalance` function.
 * This unlocks the releasable balance for the respective year, making it available for withdrawal.
 */
contract MultiSigTimeLockWallet is
    Initializable,
    UUPSUpgradeable,
    OwnableUpgradeable
{
    /**
     * @dev Enum for defining the types of requests that can be made within the contract.
     * @param NULL Represents no request type.
     * @param ADD_SIGNER Represents a request to add a new signer.
     * @param REMOVE_SIGNER Represents a request to remove an existing signer.
     * @param SET_REQUIRED_SIGS Represents a request to change the required signatures.
     * @param WITHDRAWAL Represents a request to withdraw tokens.
     */
    enum RequestType {
        NULL,
        ADD_SIGNER,
        REMOVE_SIGNER,
        SET_REQUIRED_SIGS,
        WITHDRAWAL
    }

    /**
     * @dev Struct to represent a pending request within the contract.
     * @param requestId The unique identifier for the request.
     * @param requestType The type of request being made.
     * @param remainedSigs The number of signatures remaining to be collected.
     * @param amount The amount of tokens to be withdrawn (applicable for WITHDRAWAL requestType).
     * @param to The address to which tokens are to be withdrawn (applicable for WITHDRAWAL requestType).
     * @param signer The address of the signer to be added or removed (applicable for ADD_SIGNER and REMOVE_SIGNER requestTypes).
     * @param pastRequiredSigs The current number of required signatures (applicable for SET_REQUIRED_SIGS requestType).
     * @param newRequiredSigs The new number of required signatures (applicable for SET_REQUIRED_SIGS requestType).
     */
    struct PendingRequest {
        uint256 requestId;
        RequestType requestType;
        uint256 remainedSigs;
        // Applicable for WITHDRAWAL requestType
        uint256 amount;
        address to;
        // Applicable for ADD_SIGNER and REMOVE_SIGNER requestTypes
        address signer;
        // Applicable for SET_REQUIRED_SIGS requestType
        uint256 pastRequiredSigs;
        uint256 newRequiredSigs;
    }

    /**
     * @dev The name of the wallet.
     */
    string public walletName;

    /**
     * @dev The address of the PME token contract.
     */
    ERC20 public pmeToken;

    /**
     * @dev The start time of the vesting period.
     */
    uint256 public startTime;

    /**
     * @dev The end time of the vesting period, calculated as start time plus duration.
     */
    uint256 public endTime;

    /**
     * @dev The number of remaining releases, initially set to 10 and decreased by 1 each year.
     */
    uint64 public remainedReleases;

    /**
     * @dev The balance that can be withdrawn, initially set to 0 and increased by 10% each year.
     */
    uint256 public withdrawableBalance;

    /**
     * @dev Mapping of year numbers to releasable balances.
     */
    mapping(uint256 yearNumber => uint256 releasableBalance)
        public yearToReleasable;

    /**
     * @dev Array of addresses of all signers.
     */
    address[] public signers;

    /**
     * @dev The number of signatures required to execute a request.
     */
    uint256 public requiredSigs;

    /**
     * @dev The next pending request ID.
     */
    uint256 public nextPendingRequestId;

    /**
     * @dev Mapping of signer addresses to a boolean indicating if they are a signer.
     */
    mapping(address signer => bool) public isSigner;

    /**
     * @dev Mapping of request IDs to pending requests.
     */
    mapping(uint256 requestId => PendingRequest) public pendingRequests;

    /**
     * @dev Mapping of request IDs to mappings of signer addresses to a boolean indicating if they have signed the request.
     */
    mapping(uint256 => mapping(address => bool)) public signedBy;

    /**
     * @dev Emitted when a new request is added.
     * @param requestId The ID of the request.
     * @param signer The address of the signer who added the request.
     */
    event RequestAdded(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a request is signed.
     * @param requestId The ID of the request.
     * @param signer The address of the signer who signed the request.
     */
    event RequestSigned(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a request is removed.
     * @param requestId The ID of the request.
     * @param signer The address of the signer who removed the request.
     */
    event RequestRemoved(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a request is resolved.
     * @param requestId The ID of the request.
     * @param signer The address of the signer who resolved the request.
     */
    event RequestResolved(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a new signer is added.
     * @param signer The address of the new signer.
     */
    event SignerAdded(address indexed signer);

    /**
     * @dev Emitted when a signer is removed.
     * @param signer The address of the removed signer.
     */
    event SignerRemoved(address indexed signer);

    /**
     * @dev Emitted when the required signatures are changed.
     * @param pastRequiredSigs The previous number of required signatures.
     * @param newRequiredSigs The new number of required signatures.
     */
    event RequiredSigsChanged(
        uint256 pastRequiredSigs,
        uint256 newRequiredSigs
    );

    /**
     * @dev Emitted when the withdrawable balance is set after the lock time period ends.
     * @param withdrawableBalance The amount of the current withdrawable balance.
     */
    event WithdrawableBalanceSet(uint256 withdrawableBalance);

    /**
     * @dev Emitted when tokens are withdrawn.
     * @param to The address to which tokens are withdrawn.
     * @param amount The amount of tokens withdrawn.
     */
    event Withdrawn(address indexed to, uint256 amount);

    /**
     * @dev Modifier to check if the caller is a signer.
     */
    modifier onlySigner() {
        require(isSigner[msg.sender], "Invalid signer");
        _;
    }

    /**
     * @dev Initializes the wallet with the given parameters.
     *
     * This function sets up the wallet by assigning the PME token address,
     * adding initial signers, setting the required signatures for withdrawals,
     * and configuring the locking period.
     *
     * @param _walletName The name of the wallet.
     * @param _pmeToken The address of the PME token.
     * @param _signers The initial list of signers for the multi-signature wallet.
     * @param _requiredSigs The number of signatures required to execute a request.
     * @param _lockStartTime The time (in days) after which locking starts.
     * @param _lockDurationYears The duration (in years) of the entire locking period.
     * @param _releasesCount The number of releases during the locking period.
     * @param _totalBalance The total balance for setting releasable amounts during unlock times.
     */
    function initialize(
        string memory _walletName,
        address _pmeToken,
        address[] memory _signers,
        uint256 _requiredSigs,
        uint256 _lockStartTime, // the days after this time
        uint256 _lockDurationYears, // 10 years   --> end = start + 10 years   |
        uint64 _releasesCount, // 10 times    releasePercentage = 100 / releasesCount = 10 %
        uint256 _totalBalance
    ) public initializer {
        require(_pmeToken != address(0), "PME token address cannot be zero");
        require(_signers.length >= 2, "At least two signers are required");
        require(_requiredSigs >= 2, "At least two signatures are required");

        // Initializes the contract with the owner address
        __Ownable_init(msg.sender);

        // Set the wallet name
        walletName = _walletName;

        // Sets the PME token address
        pmeToken = ERC20(_pmeToken);

        // Adds initial signers to the wallet
        for (uint256 i = 0; i < _signers.length; i++) {
            isSigner[_signers[i]] = true;
            signers.push(_signers[i]);
        }

        // Sets the required signatures for withdrawals
        requiredSigs = _requiredSigs;

        // Calculates the start and end times of the locking period
        startTime = block.timestamp + _lockStartTime * 1 days;
        endTime = startTime + _lockDurationYears * 365 days;
        remainedReleases = _releasesCount;
        // Calculates the releasable balance for each year
        uint256 _releasableBalance = _totalBalance / _releasesCount;

        // Sets the releasable balance for each year
        for (uint256 i = 1; i <= _lockDurationYears; i++) {
            yearToReleasable[i] = _releasableBalance;
        }

        // Initializes the next pending request ID
        nextPendingRequestId = 1;
    }

    /**
     * @dev Adds a new signer to the multi-signature wallet.
     * This function is only accessible by existing signers and creates a new pending request for adding a signer.
     * @param _signer The address of the signer to add.
     */
    function addSigner(address _signer) external onlySigner {
        // Check if the signer already exists to prevent duplicates
        require(!isSigner[_signer], "Signer already exists");

        // Generate a new pending request ID and increment the counter
        uint256 _pendingRequestId = nextPendingRequestId++;
        // Mark the current signer as signed for the pending request
        signedBy[_pendingRequestId][msg.sender] = true;

        // Initialize the pending request with the necessary details
        pendingRequests[_pendingRequestId].requestId = _pendingRequestId;
        pendingRequests[_pendingRequestId].requestType = RequestType.ADD_SIGNER;
        pendingRequests[_pendingRequestId].remainedSigs = requiredSigs - 1;
        pendingRequests[_pendingRequestId].signer = _signer;

        // Emit an event to notify of the new request
        emit RequestAdded(_pendingRequestId, msg.sender);
    }

    /**
     * @dev Initiates the process of removing a signer from the multi-signature wallet.
     * This function is only accessible by existing signers and creates a new pending request for removing a signer.
     * @param _signer The address of the signer to remove.
     */
    function removeSigner(address _signer) public onlySigner {
        // Verify that the signer to be removed exists and there are more than 2 signers
        require(signers.length > 2, "Signers count cannot be less than 2");
        // Ensure that removing a signer would not result in less than requiredSigs signers
        require(
            signers.length > requiredSigs,
            "Removing a signer would leave less than requiredSigs signers"
        );
        // Verify that the signer to be removed exists
        require(isSigner[_signer], "Signer does not exist");
        // Generate a new pending request ID and increment the counter
        uint256 _pendingRequestId = nextPendingRequestId++;
        // Mark the current signer as signed for the pending request
        signedBy[_pendingRequestId][msg.sender] = true;

        // Initialize the pending request with the necessary details
        pendingRequests[_pendingRequestId].requestId = _pendingRequestId;
        pendingRequests[_pendingRequestId].requestType = RequestType
            .REMOVE_SIGNER;
        pendingRequests[_pendingRequestId].remainedSigs = requiredSigs - 1;
        pendingRequests[_pendingRequestId].signer = _signer;

        // Emit an event to notify of the new request
        emit RequestAdded(_pendingRequestId, msg.sender);
    }

    /**
     * @dev Initiates the process of setting a new required signatures count for the wallet.
     * This function is only accessible by existing signers and creates a new pending request for setting required signatures.
     * @param _requiredSigs The new required signatures count.
     */
    function setRequiredSigs(uint256 _requiredSigs) external onlySigner {
        // Verify that the new required signatures count is valid
        require(
            _requiredSigs >= 2,
            "Required signatures count must be more than 2"
        );
        // Ensure required signatures count is not less than the number of signers
        require(
            _requiredSigs <= signers.length,
            "Required signatures count must be less than or equal to the number of signers"
        );
        // Verify that the new required signatures count is different from the current one
        require(_requiredSigs != requiredSigs, "Already set");

        // Generate a new pending request ID and increment the counter
        uint256 _pendingRequestId = nextPendingRequestId++;
        // Mark the current signer as signed for the pending request
        signedBy[_pendingRequestId][msg.sender] = true;

        // Initialize the pending request with the necessary details
        pendingRequests[_pendingRequestId].requestId = _pendingRequestId;
        pendingRequests[_pendingRequestId].requestType = RequestType
            .SET_REQUIRED_SIGS;
        pendingRequests[_pendingRequestId].remainedSigs = requiredSigs - 1;
        pendingRequests[_pendingRequestId].pastRequiredSigs = requiredSigs;
        pendingRequests[_pendingRequestId].newRequiredSigs = _requiredSigs;

        // Emit an event to notify of the new request
        emit RequestAdded(_pendingRequestId, msg.sender);
    }

    /**
     * @dev Initiates a withdrawal request from the contract's token balance.
     * This function is only accessible by existing signers and creates a new pending request for withdrawal.
     * @param _to The address to which tokens are to be withdrawn.
     * @param _amount The amount of tokens to be withdrawn.
     */
    function withdraw(address _to, uint256 _amount) external onlySigner {
        // Verify that the withdrawable balance is sufficient for the requested amount
        require(
            withdrawableBalance >= _amount,
            "Insufficient withdrawable balance"
        );
        // Verify that the recipient address is not the zero address
        require(_to != address(0), "Invalid recipient address");

        // Generate a new pending request ID and increment the counter
        uint256 _pendingRequestId = nextPendingRequestId++;
        // Mark the current signer as signed for the pending request
        signedBy[_pendingRequestId][msg.sender] = true;

        // Initialize the pending request with the necessary details
        pendingRequests[_pendingRequestId].requestId = _pendingRequestId;
        pendingRequests[_pendingRequestId].requestType = RequestType.WITHDRAWAL;
        pendingRequests[_pendingRequestId].remainedSigs = requiredSigs - 1;
        pendingRequests[_pendingRequestId].amount = _amount;
        pendingRequests[_pendingRequestId].to = _to;

        // Emit an event to notify of the new request
        emit RequestAdded(_pendingRequestId, msg.sender);
    }

    /**
     * @dev Signs a pending request, potentially resolving it if enough signatures are collected.
     * This function is only accessible by existing signers and updates the state of a pending request.
     * @param _requestId The ID of the pending request to sign.
     */
    function signRequest(uint256 _requestId) external onlySigner {
        // Verify that the request ID exists
        require(
            pendingRequests[_requestId].requestId == _requestId,
            "Pending request id does not exist"
        );
        // Ensure the signer hasn't already signed the request
        require(
            !signedBy[_requestId][msg.sender],
            "Signer has already signed the request"
        );

        // Load the pending request details into memory
        PendingRequest memory pendingRequest = pendingRequests[_requestId];

        // Check if the request is ready to be resolved (i.e., only one signature is missing)
        if (pendingRequest.remainedSigs == 1) {
            // Resolve the request based on its type
            if (pendingRequest.requestType == RequestType.WITHDRAWAL) {
                _withdraw(pendingRequest.to, pendingRequest.amount);
            } else if (pendingRequest.requestType == RequestType.ADD_SIGNER) {
                _addSigner(pendingRequest.signer);
            } else if (
                pendingRequest.requestType == RequestType.REMOVE_SIGNER
            ) {
                _removeSigner(pendingRequest.signer);
            } else if (
                pendingRequest.requestType == RequestType.SET_REQUIRED_SIGS
            ) {
                _setRequiredSigs(
                    pendingRequest.pastRequiredSigs,
                    pendingRequest.newRequiredSigs
                );
            } else {
                revert();
            }
            // Mark the current signer as signed for the pending request
            signedBy[_requestId][msg.sender] = true;

            // Emit an event to notify of the request resolution
            emit RequestResolved(_requestId, msg.sender);
            // Remove the request from the mapping
            delete pendingRequests[_requestId];
        } else {
            // Mark the current signer as signed for the pending request
            signedBy[_requestId][msg.sender] = true;
            // If the request is not yet resolved, decrement the remaining signatures count
            pendingRequests[_requestId].remainedSigs -= 1;
            // Emit an event to notify of the request signing
            emit RequestSigned(_requestId, msg.sender);
        }
    }

    /**
     * @dev Removes a pending request from the wallet.
     * This function is only accessible by existing signers and emits an event to notify of the request removal.
     * @param _requestId The ID of the pending request to remove.
     */
    function removeRequest(uint256 _requestId) external onlySigner {
        // Verify that the request ID exists
        require(
            pendingRequests[_requestId].requestId == _requestId,
            "Request id does not exist"
        );

        // Only allow the signer who added the request to remove it
        require(
            signedBy[_requestId][msg.sender],
            "Only the signer who added the request can remove it"
        );

        // Emit an event to notify of the request removal
        emit RequestRemoved(_requestId, msg.sender);
        // Delete the pending request
        delete pendingRequests[_requestId];
    }

    /**
     * @dev Sets the withdrawable balance based on the current time and the vesting schedule.
     * This function is accessible only by signers and updates the withdrawable balance.
     */
    function unlockBalance() external onlySigner {
        // Get the current timestamp
        uint256 _currentTime = block.timestamp;

        // Calculate the year number based on the elapsed time since the start
        uint256 _yearNumber = (_currentTime - startTime) / uint256(365 days);
        // Ensure the current time is after the start time to set the withdrawable balance
        require(
            _currentTime > startTime && _yearNumber >= 1,
            "Cannot set withdrawable balance yet"
        );
        // Ensure that there is a non-zero amount allocated for the current year
        require(
            yearToReleasable[_yearNumber] > 0,
            "Withdrawable balance is unlocked before"
        );

        // Initialize a variable to accumulate the withdrawable balance
        uint256 _withdrawableBalance;

        // Loop to update the withdrawable balance for each year with a non-zero allocation
        while (yearToReleasable[_yearNumber] > 0) {
            // Decrement the number of remaining releases
            remainedReleases--;
            // Add the releasable balance for the current year to the total withdrawable balance
            _withdrawableBalance += yearToReleasable[_yearNumber];
            // Set the releasable balance for the current year to zero
            yearToReleasable[_yearNumber] = 0;

            // Move to the previous year for the next iteration
            _yearNumber--;
        }

        // Update the total withdrawable balance
        withdrawableBalance += _withdrawableBalance;

        // Emit an event to notify of the updated withdrawable balance
        emit WithdrawableBalanceSet(withdrawableBalance);
    }

    /**
     * @dev Internal function to add a new signer to the wallet.
     * This function updates the signer status, adds the signer to the list of signers,
     * removes the corresponding pending request, and emits an event to notify of the addition.
     * @param _signer The address of the signer to add.
     */
    function _addSigner(address _signer) internal {
        // Mark the signer as active
        isSigner[_signer] = true;
        // Add the signer to the list of signers
        signers.push(_signer);

        // Emit an event to notify of the signer addition
        emit SignerAdded(_signer);
    }

    /**
     * @dev Internal function to remove a signer from the wallet.
     * This function updates the signer status, removes the signer from the list of signers,
     * removes the corresponding pending request, and emits an event to notify of the removal.
     * @param _signer The address of the signer to remove.
     */
    function _removeSigner(address _signer) internal {
        // Mark the signer as inactive
        isSigner[_signer] = false;
        // Find and remove the signer from the list of signers
        for (uint256 i = 0; i < signers.length; i++) {
            if (signers[i] == _signer) {
                // Replace the signer with the last signer in the list and remove the last signer
                signers[i] = signers[signers.length - 1];
                signers.pop();
                break;
            }
        }

        // Emit an event to notify of the signer removal
        emit SignerRemoved(_signer);
    }

    /**
     * @dev Internal function to set the required signatures for a request.
     * This function updates the required signatures, removes the corresponding pending request,
     * and emits an event to notify of the change.
     * @param _pastRequiredSigs The previous amount of required signatures.
     * @param _newRequiredSigs The new amount of required signatures.
     */
    function _setRequiredSigs(
        uint256 _pastRequiredSigs,
        uint256 _newRequiredSigs
    ) internal {
        // Update the required signatures to the new amount
        requiredSigs = _newRequiredSigs;

        // Emit an event to notify of the change in required signatures count
        emit RequiredSigsChanged(_pastRequiredSigs, _newRequiredSigs);
    }

    /**
     * @dev Executes a withdrawal request by transferring tokens to the specified address.
     * This function is internal and can only be called by the contract itself.
     * @param _to The address to which the tokens will be transferred.
     * @param _amount The amount of tokens to be transferred.
     */
    function _withdraw(address _to, uint256 _amount) internal {
        // Update the withdrawable balance by subtracting the amount to be withdrawn
        withdrawableBalance -= _amount;
        // Execute the transfer of the specified amount of tokens to the recipient
        pmeToken.transfer(_to, _amount);

        // Notify of the successful withdrawal through an event
        emit Withdrawn(_to, _amount);
    }

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @dev This function is used by the UUPS upgradeability pattern to authorize upgrades to the contract's implementation.
     * @param newImplementation The address of the new implementation contract.
     * @dev Only an account with the `DEFAULT_ADMIN_ROLE` can authorize upgrades.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
