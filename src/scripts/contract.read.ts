//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import "dotenv/config"
import {getHttpEndpoint} from "@orbs-network/ton-access"
import {Address} from "@ton/core"
import {createInterface} from "readline/promises"
import {TonClient} from "@ton/ton"
// import {JettonMinter} from "../output/Jetton_JettonMinter"//base
// import {JettonMinterSharded} from "../output/Shard_JettonMinterSharded" // shard
import {JettonWalletSharded} from "../output/Shard_JettonWalletSharded"
// import {displayContentCell} from "../utils/jetton-helpers"
// import chalk from "chalk"
import {getNetworkFromEnv} from "../utils/utils"

const readContractAddress = async () => {
    const readline = createInterface({
        input: process.stdin,
        output: process.stdout,
    })

    while (true) {
        try {
            const walletAddress = await readline.question("Enter wallet address: ")
            const address = Address.parse(walletAddress)
            readline.close()
            return address
        } catch (_e) {
            console.error("Invalid address, please try again.")
        }
    }
}

const main = async () => {
    const network = getNetworkFromEnv()

    const endpoint = await getHttpEndpoint({network})
    const client = new TonClient({
        endpoint: endpoint,
    })

    const walletAddress = await readContractAddress()
    // const minter = client.open(JettonMinterSharded.fromAddress(minterAddress))
    const wallet = client.open(JettonWalletSharded.fromAddress(walletAddress))

    // const walletData = await wallet.send
    const walletAllData = await wallet.getState()

    console.log("\nWallet data")
    // console.log(`friends: ${chalk.yellowBright(walletData.friends)}`)
    // console.log(`followers: ${chalk.underline(walletData.followers)}`)
    // console.log(`followings: ${chalk.underline(walletData.followings)}`)
    // console.log(`invited: ${chalk.underline(walletData.invited)}`)
    // console.log(`debts: ${chalk.underline(walletData.debts)}`)
    // console.log(`pendingRequests: ${chalk.underline(walletData.pendingRequests)}`)
    // console.log(`reports: ${chalk.underline(walletData.reports)}`)
    // console.log(
    //     `Is mintable: ${walletData.mintable ? chalk.greenBright("Yes") : chalk.redBright("No")}`,
    // )
    // await displayContentCell(walletData.jettonContent)
    console.log(walletAllData)
}

void main()
