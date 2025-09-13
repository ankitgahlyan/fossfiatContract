//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import {toNano, TonClient, WalletContractV4, fromNano} from "@ton/ton"
import {getHttpEndpoint} from "@orbs-network/ton-access"
import {mnemonicToPrivateKey} from "@ton/crypto"
// import {storeMint} from "../output/Jetton_JettonMinter"
import {JettonUpdateContent, JettonMinterSharded} from "../output/Shard_JettonMinterSharded"

import {printSeparator} from "../utils/print"
import "dotenv/config"
import {getJettonHttpLink, getNetworkFromEnv} from "../utils/utils"
import {buildJettonMinterFromEnv} from "../utils/jetton-helpers"

import {Address} from "@ton/core"
import {createInterface} from "readline/promises"
// import {JettonWalletSharded} from "../output/Shard_JettonWalletSharded"
// import {displayContentCell} from "../utils/jetton-helpers"
// import chalk from "chalk"

const main = async () => {
    const mnemonics = process.env.MNEMONICS
    if (mnemonics === undefined) {
        console.error("Mnemonics is not provided, please add it to .env file")
        throw new Error("Mnemonics is not provided")
    }
    if (mnemonics.split(" ").length !== 24) {
        console.error("Invalid mnemonics, it should be 24 words")
        throw new Error("Invalid mnemonics, it should be 24 words")
    }

    const network = getNetworkFromEnv()

    const endpoint = await getHttpEndpoint({network})
    const client = new TonClient({
        endpoint: endpoint,
    })
    const keyPair = await mnemonicToPrivateKey(mnemonics.split(" "))
    const secretKey = keyPair.secretKey
    const workchain = 0 // we are working in basechain.
    const deployerWallet = WalletContractV4.create({
        workchain: workchain,
        publicKey: keyPair.publicKey,
    })

    const deployerWalletContract = client.open(deployerWallet)

    const readContractAddress = async () => {
        const readline = createInterface({
            input: process.stdin,
            output: process.stdout,
        })

        while (true) {
            try {
                const walletAddress = await readline.question("Enter minter address: ")
                const address = Address.parse(walletAddress)
                readline.close()
                return address
            } catch (_e) {
                console.error("Invalid minter address, please try again.")
            }
        }
    }

    // const walletAddress = await readContractAddress()
    const minterAddress = await readContractAddress()
    const jettonMinter = client.open(JettonMinterSharded.fromAddress(minterAddress))
    const jettonMinterNew = await buildJettonMinterFromEnv(deployerWalletContract.address, "shard")
    // const wallet = client.open(JettonWalletSharded.fromAddress(walletAddress))
    const deployAmount = toNano("0.2")

    // const supply = toNano(Number(process.env.JETTON_SUPPLY ?? 1000000000)) // 1_000_000_000 jettons
    // const supply = toNano(parseFloat("0.1")) // 1_000_000_000 jettons
    const msg: JettonUpdateContent = {
        $$type: "JettonUpdateContent",
        queryId: 0n,
        content: jettonMinterNew!!.init!!.code,
        jettonWalletCode: null,
    }

    const seqno: number = await deployerWalletContract.getSeqno()
    console.log(`Running UPGRADE script for ${network} network and for Minter`)
    console.log(
        "🛠️Preparing new outgoing massage from deployment wallet. \n" +
            deployerWalletContract.address,
    )
    console.log("Seqno: ", seqno + "\n")
    printSeparator()

    // Get deployment wallet balance
    const balance: bigint = await deployerWalletContract.getBalance()

    console.log("Current deployment wallet balance = ", fromNano(balance).toString(), "💎TON")
    if (balance < deployAmount) {
        console.error("Not enough balance to deploy the contract")
        throw new Error("Not enough balance to deploy the contract")
    }

    printSeparator()
    // ============================
    await jettonMinter.send(
        deployerWalletContract.sender(secretKey),
        {value: deployAmount, bounce: true},
        msg,
    )
    // await deployerWalletContract.sendTransfer({
    //     seqno,
    //     secretKey,
    //     messages: [
    //         internal({
    //             to: jettonMinter!!.address,
    //             value: deployAmount,
    //             init: {
    //                 code: jettonMinter!!.init?.code,// change this to old
    //                 data: jettonMinter!!.init?.data,
    //             },
    //             body: msg,
    //         }),
    //     ],
    // })
    console.log("====== UPGRADE message sent to =======\n", jettonMinter!!.address)
    const link = getJettonHttpLink(network, jettonMinter!!.address, "tonviewer")
    console.log(`You can soon check your upgraded contract at ${link}`)
}

void main()
