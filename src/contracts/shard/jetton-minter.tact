//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import "./jetton-wallet";
import "./messages";
import "./constants";
import "../utils";
import "./shard-utils";
import "./send";

// TODO: multisig for upgrades, lottery for treasury, jobCoins as separate contract
struct JettonMinterState {
    totalSupply: Int as coins;
    //treasurySurplus: Int as coins;
    //treasuryDeficits: Int as coins;
    mintable: Bool;
    adminAddress: Address;
    //tosHash: String = "";
    jettonContent: Cell;
    jettonWalletCode: Cell;
}

// struct JettonWalletCode {// nested store
//     version: Int as uint10;
//     code: Cell;
// }

contract JettonMinterSharded {
    totalSupply: Int as coins;
    population: Int as uint32 = 0;
    // treasurySurplus: Int as coins = 0;
    // treasuryDeficits: Int as coins = 0;
    owner: Address;
    jettonContent: Cell;
    jettonWalletCode: Cell;
    version: Int as uint10 = 0; // for network compatibility
    walletVersion: Int as uint10 = 0;
    mintable: Bool;
    //tosHash: String = "";
    //mbrpAmount: Int as coins,//TODO: change from coins, add fun to change, send message to all contracts on change
    publicWorks: map<Address, Int as uint10>; // TODO: coupons/nft cashed out at eligible accounts
    votes: map<Address, Int as uint20>;
    //crowdFund: map<Int as uint10, Int as uint10>;

    init(totalSupply: Int as coins, owner: Address, jettonContent: Cell, mintable: Bool) {
        self.totalSupply = totalSupply;
        self.owner = owner;
        self.jettonContent = jettonContent;
        self.mintable = mintable;
        self.jettonWalletCode = codeOf JettonWalletSharded;
    }

    // receive("updateMBRP") {
    //     //TODO: v2
    // }

    receive(msg: ProvideWalletAddress) {
        let ownerWorkchain: Int = parseStdAddress(msg.ownerAddress.asSlice()).workchain;

        let ownerShard = msg.ownerAddress.getShard();

        let hash = getJettonWalletInit(msg.ownerAddress).hash();

        // If owner is basechain address, we can calculate jettonWallet
        let targetJettonWallet: BasechainAddress = (ownerWorkchain == Basechain)
            ? BasechainAddress { hash: changeShard(hash, ownerShard) }
            : emptyBasechainAddress();

        MessageParameters {
            body: makeTakeWalletAddressMsg(targetJettonWallet, msg),
            to: sender(),
            value: 0,
            mode: SendRemainingValue,
        }.send();
    }

    receive(msg: JettonBurnNotification) {
        // let expectedAddress: Address = contractAddress(initOf TodoChild(myAddress(), msg.fromSeqno));

        // require(sender() == expectedAddress, "Access denied");
        // only the real children can get here

        // let wallet: StateInit = self.getInit(sender);
        // if (!(wallet.hasSameBasechainAddressWithoutShard(sender()))) {
        //     //TODO: master can't mint so remove and return
        //     throwUnless(700, self.minter == sender());
        // }

        let sender = parseStdAddress(sender().asSlice());
        let wallet = getJettonBasechainWalletByOwner(msg.sender);

        // Workchain 0 is basechain
        throwUnless(724, sender.workchain == Basechain && sender.address == wallet.hash!!); // unauthorized burn/sender

        if (msg.sender == emptyAddress()) { // custom use for mint notify
            self.totalSupply += msg.amount;
        } else {
            self.totalSupply -= msg.amount;
        }

        if (msg.responseDestination != null) {
            MessageParameters {
                to: msg.responseDestination!!,
                body: JettonExcesses { queryId: msg.queryId }.toCell(),
                value: 0,
                bounce: false,
                mode: SendRemainingValue | SendIgnoreErrors, // ignore errors, because supply has already been updated
            }.send();
        }
    }

    // Owner of this contract may be masterchain address,
    // however minting is possible only to basechain addresses
    // it is asserted inside the deploy function
    receive(msg: Mint) {
        throwUnless(700, sender() == self.owner); // incorrect sender
        throwUnless(730, self.mintable); // mint is closed

        checkEitherForwardPayload(msg.mintMessage.forwardPayload);

        let ctx = context();
        // we don't add compute fees for mint itself and reserve here
        // it's okay since it’s sent only by the admin and excesses will return back
        throwUnless(
            731,
            ctx.value >
            minTonsForStorage +
            msg.mintMessage.forwardTonAmount +
            ctx.readForwardFee() +
            getForwardFee(walletStateInitCells, walletStateInitBits, false) +
            2 * getComputeFee(gasForTransfer, false),
        );

        self.totalSupply += msg.mintMessage.amount; // + ton("1000"); // invitation by minter

        // basechain destination is calculated inside deploy function
        DeployParameters {
            value: 0, // ignore msg.tonAmount and use SendMode 64 instead
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: msg.mintMessage.toCell(),
            init: initOf JettonWalletSharded(msg.receiver, myAddress(), 0),
        }.toShard(msg.receiver.getShard()).send();
    }

    receive(msg: ClaimTON) {
        throwUnless(700, sender() == self.owner);
        nativeReserve(minTonsForStorage, ReserveExact | ReserveBounceIfActionFail);

        // we allow bounce here and don't handle it, if claim fails we just accept the TONs back
        MessageParameters {
            to: msg.receiver,
            value: 0,
            mode: SendRemainingBalance,
        }.send();
    }

    receive(msg: JettonUpdateContent) {
        throwUnless(700, sender() == self.owner); // incorrect sender
        if (msg.content != null) {
            self.jettonContent = msg.content!!;
            self.version = + 1;
        }
        if (msg.jettonWalletCode != null) {
            self.jettonWalletCode = msg.jettonWalletCode!!;
            self.walletVersion += 1;

            // auto upgrade owner jetton wallet code TODO:
            //self.sendUpgrade(getJettonBasechainWalletByOwner(self.owner));
        }

        cashback(sender());
    }

    receive(msg: RequestUpgradeCode) {
        //let code: Cell? = null;
        // let code = emptyCell();// it's different!

        if (msg.version < self.walletVersion) {
            //code = self.jettonWalletCode;
            self.sendUpgrade(sender());
        }
    }

    inline fun sendUpgrade(to: Address) {
        MessageParameters { // bounce for collecting fees back
            to,
            mode: SendRemainingValue | SendIgnoreErrors,
            bounce: false,
            value: 0,
            body: UpgradeCode {
                sender: myAddress(), //self.owner,
                code: self.jettonWalletCode,
            }.toCell(),
        }.send();
    }

    receive(msg: ChangeOwner) {
        throwUnless(700, sender() == self.owner);
        self.owner = msg.newOwner;
        cashback(sender());
    }

    receive(msg: CloseMinting) {
        throwUnless(700, sender() == self.owner);
        self.mintable = false;
        cashback(sender());
    }

    receive(msg: AccountGenerated) {
        // FIXME: checks
        self.population += 1;
        // we allow bounce here and don't handle it, if claim fails we just accept the TONs back
        // FIXME: emit event or tell connections in wallet's init
        //cashback(msg.deployer);// empty receiver significance?

        let msgValue: Int = context().value;
        let tonBalanceBeforeMsg = myBalance() - msgValue;
        nativeReserve(max(tonBalanceBeforeMsg, minTonsForStorage), ReserveAtMost);
        // 0xd53276db -- Cashback to the original Sender
        if (msgValue > 0) {
            MessageParameters {
                to: msg.deployer,
                value: msgValue, // NOTE: VALUE + remaining BALANCE?
                mode: SendRemainingBalance | SendIgnoreErrors,
                bounce: false,
                body: JettonExcesses { queryId: 0 }.toCell(),
            }.send();
        }
    }

    receive(msg: Slice) {} // fallback to accept value

    receive() {} // empty receiver to accept value

    receive(msg: ApplyGrant) {
        // FIXME: checks
        self.publicWorks.set(msg.sender, msg.amount);
        cashback(msg.sender);
    }

    receive(msg: VoteProposal) {
        // FIXME: checks
        self.votes.set(msg.proposer, msg.turnover);
        cashback(msg.sender);
    }

    bounced(msg: bounced<JettonTransferInternal>) {
        self.totalSupply -= msg.amount;
    }

    get fun state(): JettonMinterSharded {
        return self; // you do not have to list all fields of a contract for this
    }

    get fun get_jetton_data(): JettonMinterState { // don't touch it or explorers won't recognise as minter
        return JettonMinterState {
            totalSupply: self.totalSupply,
            mintable: self.mintable,
            adminAddress: self.owner,
            jettonContent: self.jettonContent,
            jettonWalletCode: codeOf JettonWalletSharded,
        };
    }

    get fun get_wallet_address(ownerAddress: Address): Address {
        return getJettonWalletByOwner(ownerAddress);
    }
}
inline fun getJettonWalletInit(address: Address): Cell {
    let init = initOf JettonWalletSharded(address, myAddress(), 0);

    return beginCell().storeShardedStateInit(init).endCell();
}

inline fun getJettonWalletByOwner(jettonWalletOwner: Address): Address {
    let init = getJettonWalletInit(jettonWalletOwner);

    let ownerShard = jettonWalletOwner.getShard();

    let expectedAddr = beginCell()
        .storeUint(4, 3) // addr_std$10, anycast: false
        .storeUint(0, 8) // workchain_id: 0
        .storeUint(changeShard(init.hash(), ownerShard), 256)
        .asSlice();

    return expectedAddr.loadAddress();
}

inline fun getJettonBasechainWalletByOwner(jettonWalletOwner: Address): BasechainAddress {
    let init = getJettonWalletInit(jettonWalletOwner);

    let ownerShard = jettonWalletOwner.getShard();

    return BasechainAddress { hash: changeShard(init.hash(), ownerShard) };
}
