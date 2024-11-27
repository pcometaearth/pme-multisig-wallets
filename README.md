# PME MultiSig Wallets

A collection of Solidity smart contracts designed to manage multi-signature wallet operations, including advanced time-lock functionality. This repository provides two contracts:

1. **MultiSigWallet**: A multi-signature wallet for securely managing funds and transactions.
2. **MultiSigTimeLockWallet**: An enhanced multi-signature wallet with a built-in token locking mechanism over a 10-year period.

---

## Contracts Overview

### 1. MultiSigWallet
The `MultiSigWallet` contract enables multi-signature wallet operations, allowing multiple signers to collectively manage funds and transactions. It supports the following operations:

- **Add Signer**: Add a new signer to the wallet using the `addSigner` function.
- **Remove Signer**: Remove an existing signer using the `removeSigner` function.
- **Change Required Signatures**: Adjust the number of required signatures with the `setRequiredSigs` function.
- **Withdraw Funds**: Initiate a fund withdrawal using the `withdraw` function.

#### Workflow:
1. A signer initiates a request (e.g., adding a new signer or initiating a withdrawal).
2. The request is recorded in the `pendingRequests` mapping with a unique request ID.
3. Other signers review and approve the request using the `signRequest` function.
4. Once the required number of signatures is met, the action is executed.

#### Key Functions:
- **`pendingRequests`**: View details of all pending requests, including their IDs.
- **`signRequest`**: Sign a pending request by providing its request ID.

---

### 2. MultiSigTimeLockWallet
The `MultiSigTimeLockWallet` extends the functionality of the `MultiSigWallet` by adding a time-lock mechanism for token management. It supports the same multi-signature operations as `MultiSigWallet` with an additional locking feature.

#### Key Features:
- **Token Locking**: Tokens are locked for 10 years, with 10% becoming releasable each year.
- **Unlock Balance**: Unlock the releasable balance for the current year by calling the `unlockBalance` function.
- **Multi-Signature Workflow**: Similar to `MultiSigWallet`, all critical actions require collective agreement among signers.

#### Workflow:
1. A signer unlocks the balance for the current year using the `unlockBalance` function.
2. Withdrawal requests are created and approved using the same multi-signature process as the `MultiSigWallet`.

#### Additional Functions:
- **`unlockBalance`**: Unlock the current year's releasable balance to make it available for withdrawal.

---

## Directory Structure

```plaintext
contracts/
├── MultiSigWallet.sol        # The core multi-signature wallet contract
├── MultiSigTimeLockWallet.sol # The multi-signature wallet with time-lock functionality
