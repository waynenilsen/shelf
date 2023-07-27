# Shelf

## Introduction

Shelf is a decentralized finance protocol designed to handle various tokens, providing deposit, withdrawal and liquidation services. It employs an interest rate model to balance supply and demand, providing incentives for deposits and loans.

## Key Features

- Shelf allows the deposit of any supported ERC20 token into the protocol.
- It calculates interest rates based on an imported Interest Rate Model.
- Users can withdraw their deposits, also generating debt if they withdraw more than their deposit (given sufficient collateral).
- The protocol supports liquidations if an account becomes undercollateralized.

## Smart Contract Overview

The Shelf contract contains a struct for token data and mappings for token balances and user balances. The contract provides functions for adding tokens, updating exchange rates, depositing, withdrawing, and liquidation.

The protocol calculates interest using a compounding model, with rates determined by an external interest rate model. User balances and obligations are adjusted based on this rate.

The protocol also provides view functions for checking the collateralization of accounts, the balance of a user, the current exchange rate of a token, and more.

### Admin Functions

- `addToken`: Add a token to the allowed tokens on the shelf.
- `updateExchangeRate`: Update the exchange rate of a token to USD.
- `compoundInterest`: Compound interest for a token. Updates the interest rate and applies it to the index.

### User Functions

- `deposit`: Deposit tokens to the shelf.
- `withdraw`: Withdraw tokens from the shelf. More tokens than deposited can be withdrawn if there's sufficient collateral in other tokens.
- `liquidate`: Liquidate an account. The liquidatee must be undercollateralized and the calling account must be in good standing.

### View Functions

- `currentBalance`: Returns the current balance of a user on Shelf in today's value.
- `currentUsdValue`: Returns the current balance of a user on Shelf in today's value in USD.
- `getUtilization`: Get the current utilization of a token.
- `collateralizationRatio`: Compute the collateralization ratio for a given account.

## Testing

Shelf is a Solidity smart contract, intended to be deployed on any EVM blockchain. This repository uses foundry.

To run the test use 

```
forge test
```

If something is broken, use the `-vvv` flag. Change the number of `v`s to update the verbosity.

## Deployment 

TODO

## Usage

TODO

## Contributing

If you have suggestions for improvements, or want to report a bug, please open an issue or submit a pull request.

## License

Shelf is licensed under the MIT license. See the LICENSE file for details.
