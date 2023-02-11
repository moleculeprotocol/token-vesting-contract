[![Actions Status](https://github.com/schmackofant/token-vesting/workflows/main/badge.svg)](https://github.com/schmackofant/token-vesting/actions)
[![license](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# Token Vesting Contract

## Overview

On-Chain vesting scheme enabled by smart contracts.

The `TokenVesting` contract can release its token balance gradually like a typical vesting scheme, with a cliff and vesting period. The contract owner can create vesting schedules for different users, even multiple for the same person.

Vesting schedules are optionally revokable by the owner. Additionally the smart contract functions as an ERC20 compatible non-transferable virtual token which can be used e.g. for governance.

This work is based on the `TokenVesting` [contract](https://github.com/abdelhamidbakhta/token-vesting-contracts) by [@abdelhamidbakhta](https://github.com/abdelhamidbakhta) and was extended with the virtual token functionality and a few convenient improvements.

### What is a virtual token?

The amount of unvested tokens of an user are represented as a ERC20 balance (non-transferable, hence the term _virtual_ token) and can be used for governance (e.g. Snapshot). Inspired by the [vCOW](https://github.com/cowprotocol/token) token of CowSwap this allows DAOs and organizations to create vesting schedules for team, investors and contributors that vest linearly over time. While the tokens might be linearly vesting over a longer time period, the virtual token allows these people to participate in governance right away, which is a great way for DAOs to incentivize long term contributors.

## 🎭🧑‍💻 Security audits

- [Security audit](https://github.com/abdelhamidbakhta/token-vesting-contracts/blob/main/audits/hacken_audit_report.pdf) from [Hacken](https://hacken.io)

The original contract by [@abdelhamidbakhta](https://github.com/abdelhamidbakhta) was audited in 2021. This version leaves the core logic around creating and managing vesting schedules and the computation untouched and merely expands the contract with the virtual token functionality and a few minor changes.

## Important notes
- This contract is only compatible with native tokens that have 18 decimals. Deyploment will revert otherwise.
- You should never use this contract with a native token that is rebasing down as this could lead to calculation errors. E.g. if the token balance of the `TokenVesting` smart contract goes lower due to rebasing, the beneficiary can only release fewer tokens than expected (contract token balance could be smaller than the `amountTotal` of the schedule).

### 📦 Installation

To work with this repository you have to install Foundry (<https://getfoundry.sh>). Run the following command in your terminal, then follow the onscreen instructions (macOS and Linux):

`curl -L https://foundry.paradigm.xyz | bash`

The above command will install `foundryup`. Then install Foundry by running `foundryup` in your terminal.

(Check out the Foundry book for a Windows installation guide: <https://book.getfoundry.sh>)

Afterwards run this command to install the dependencies:

```console
$ forge install
```
### General config

- The deploy scripts are located in `script`
- Copy `.env.example` to `.env`

You can place required env vars in your `.env` file and run `source .env` to get them into your current terminal session or provide them when invoking the command.

### ⛏️ Compile

```console
$ forge build
```

This task will compile all smart contracts in the `contracts` directory.

### Deploy for local development

- Anvil is a local testnet node shipped with Foundry. You can use it for testing your contracts from frontends or for interacting over RPC.
- Run `anvil -h 0.0.0.0` in a terminal window and keep it running

To just deploy all contracts using the default mnemonic's first account, run `forge script script/Dev.s.sol:DevScript --fork-url $ANVIL_RPC_URL --broadcast -vvvv`

### 🌡️ Testing

```console
$ forge test -vv
```

## 📄 License

**Token Vesting Contracts** is released under the [Apache-2.0](LICENSE).
