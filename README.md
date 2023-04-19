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

### Working with a large number of vesting schedules

If your organization already knows the vesting schedules (or at least a big part of them) ahead of deployment and it's a large number of schedules, calling `createVestingSchedule` a hundred times is cumbersome and not very gas efficient. Instead you can use the `TokenVestingMerkle` contract, which is a wrapper around the `TokenVesting` contract that allows you to deploy a large number of vesting schedules easily by submitting a Merkle tree of the vesting schedules when deploying the contract.

The beneficiaries can later claim their schedules by providing a Merkle proof of their schedule.

Please make sure you validate the different vesting schedule inputs (duration, amount, etc.), before you create your Merkle Tree. Calling `claimSchedule` with invalid inputs will revert and render the vesting schedule unclaimable for the beneficiary.

## 🎭🧑‍💻 Security audit

This repository's smart contracts underwent an audit in April 2023, and the audit report is available [here](https://github.com/pashov/audits/blob/master/solo/MoleculeVesting-security-review.md) and in the "[audits](/audits)" folder of the repository.

## ⚠️ Important notes and caveats
Please read the following notes carefully before using this contract. They are important to understand the limitations of this contract and how to use it properly.

- In general the DAO or organization deploying this contract has to do the due diligence on the native token they want to use. This contract only supports standard ERC20 implementations. If the native token is not a standard ERC20 implementation (e.g. restricting or modifying transfer functions, implementing transfer blocklists, being a rebase token, etc.), the contract might not work as expected and it is strongly recommended to not use this contract with such a token.
- This contract is only compatible with native tokens that have 18 decimals. Deyploment will revert otherwise.
- You should never use this contract with a native token that is rebasing down as this could lead to calculation errors. For example, if the `TokenVesting` smart contract's token balance decreases due to rebasing, the beneficiary might be able to release fewer tokens than anticipated. This occurs when the contract's token balance becomes smaller than the total amount specified in the vesting schedule.
- The contract is tested with and allows a schedule duration `<= 50 years` and a token amount `<= 2^200` (approx. 1.6 Tredecillion tokens). If your requirements are more extreme than that, you should probably not use this contract and instead implement a custom solution.

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

To just deploy all contracts using the default mnemonic's first account, run:

```console
forge script script/Dev.s.sol:DevScript --fork-url $ANVIL_RPC_URL --broadcast -vvvv
```

### Testnet

- Make sure you have set your environment variables in `.env`
- Important: Don't forget to set `NATIVE_TOKEN_ADDRESS` in `.env` to the address of the native token you want to use for vesting.
- Run the command below to deploy to Goerli testnet:

```console
forge script script/Deploy.s.sol:DeployScript --rpc-url goerli --broadcast --verify -vvvv
```

- The Etherscan verification will only work if you have set your API key in `.env`.

You can of course also deploy to Sepolia testnet as well, e.g. by using `--rpc-url sepolia`. Just remember to set the ENV variables in `.env` accordingly.

## 📄 License

**Token Vesting Contract** is released under the [Apache-2.0](LICENSE).
