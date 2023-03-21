[![Actions Status](https://github.com/schmackofant/token-vesting/workflows/main/badge.svg)](https://github.com/schmackofant/token-vesting/actions)
[![license](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

# Token Vesting Contract

## Overview

On-Chain vesting scheme enabled by smart contracts.

The `TokenVesting` contract can release its token balance gradually like a typical vesting scheme, with a cliff and vesting period. The contract owner can create vesting schedules for different users, even multiple for the same person.

Vesting schedules are optionally revokable by the owner. Additionally the smart contract functions as an ERC20 compatible non-transferable virtual token which can be used e.g. for governance.

This work is based on the `TokenVesting` [contract](https://github.com/abdelhamidbakhta/token-vesting-contracts) by [@abdelhamidbakhta](https://github.com/abdelhamidbakhta) and was extended with the virtual token functionality and a few convenience features.

### What is a virtual token?

A virtual token refers to the representation of an individual's unvested tokens as a non-transferable ERC20 balance, which can be utilized for governance purposes (such as Snapshot). Drawing inspiration from CowSwap's [vCOW](https://github.com/cowprotocol/token) token, virtual tokens enable decentralized autonomous organizations (DAOs) and other entities to establish vesting schedules for team members, investors, and contributors, which linearly vest over a predetermined timeframe.

Even though the tokens may vest linearly over an extended period, virtual tokens grant individuals the ability to participate in governance immediately. This feature provides an effective means for DAOs to incentivize and reward long-term contributors, fostering increased commitment and collaboration.

#### Real world example

- Alice is a core contributor for FoobarDAO. FoobarDAO has deployed this smart contract to reward contributors with a vested allocation of their FOO governance token. 
- FoobarDAO creates a vesting schedule (`createVestingSchedule`) for Alice, granting her 100,000 FOO tokens that will linearly vest over a four-year period without a cliff.
- Upon the creation of this schedule Alice immediately receives a balance of 100,000 vFOO, which she can use to participate in FoobarDAO governance. These virtual tokens are non-transferable.
- Two years into the vesting period, Alice releases the first portion of tokens by calling `release`. As a result, 50,000 FOO tokens are transferred to her address, and her vFOO balance is reduced from 100,000 to 50,000. Consequently, her overall voting power consists of 50,000 vFOO and 50,000 FOO tokens.
- Once the four-year vesting period comes to an end, Alice releases the remaining tokens, which zeroes out her vFOO balance and transfers an additional 50,000 FOO tokens to her address.

## 🎭🧑‍💻 Security audits

- [Security audit](https://github.com/abdelhamidbakhta/token-vesting-contracts/blob/main/audits/hacken_audit_report.pdf) from [Hacken](https://hacken.io)

The original contract by [@abdelhamidbakhta](https://github.com/abdelhamidbakhta) was audited in 2021. This version leaves the core logic around creating and managing vesting schedules and the computation untouched (see [diff](https://github.com/schmackofant/token-vesting/compare/1407a87...0819c09#diff-c1f2ee83cfe329d4820d59fb7e1762e3777d08287ef8766d891323ef98d5b65c)) and merely expands the contract with the virtual token functionality and a few minor changes. 

## ⚠️ Important notes and caveats
- This contract is only compatible with native tokens that have 18 decimals. Deyploment will revert otherwise.
- You should never use this contract with a native token that is rebasing down as this could lead to calculation errors. E.g. if the token balance of the `TokenVesting` smart contract goes lower due to rebasing, the beneficiary can only release fewer tokens than expected (contract token balance could be smaller than the `amountTotal` of the schedule).

## 📦 Installation

To work with this repository you have to install Foundry (<https://getfoundry.sh>). Run the following command in your terminal, then follow the onscreen instructions (macOS and Linux):

`curl -L https://foundry.paradigm.xyz | bash`

The above command will install `foundryup`. Then install Foundry by running `foundryup` in your terminal.

(Check out the Foundry book for a Windows installation guide: <https://book.getfoundry.sh>)

Afterwards run this command to install the dependencies:

```console
forge install
```
## General config

- The deploy scripts are located in `script`
- Copy `.env.example` to `.env`

You can place required env vars in your `.env` file and run `source .env` to get them into your current terminal session or provide them when invoking the command.

## ⛏️ Compile

```console
forge build
```

This task will compile all smart contracts in the `contracts` directory.

## 🌡️ Testing

```console
forge test -vv
```

## 🚀 Deployment

### Local development

- Anvil is a local testnet node shipped with Foundry. You can use it for testing your contracts from frontends or for interacting over RPC.
- Run `anvil -h 0.0.0.0` in a terminal window and keep it running

To just deploy all contracts using the default mnemonic's first account, run (remember to run `source .env` beforehand): 

```console
forge script script/Dev.s.sol:DevScript --fork-url $ANVIL_RPC_URL --broadcast -vvvv
```

### Testnet

- Make sure you have set your environment variables in `.env`
- Take a look at `script/deploy.s.sol` and set the address of the native token that you want to use for your token vesting contract (`nativeToken`)
- Run the command below to deploy to Goerli testnet:

```console
forge script script/Deploy.s.sol:DeployScript --rpc-url goerli --broadcast --verify -vvvv
```

- The Etherscan verification will only work if you have set your API key in `.env`. 

## 📄 License

**Token Vesting Contract** is released under the [Apache-2.0](LICENSE).
