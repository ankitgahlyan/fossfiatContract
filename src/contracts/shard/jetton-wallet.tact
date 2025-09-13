//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

import "./messages";
import "./constants";
import "./shard-utils";
import "./send";
import "../utils";

contract JettonWalletSharded {
    // TODO: nest related stores like insurance
    //STOP incoming tokens txn after transferredTo nominee
    //id token: signed payload by master
    // CONTRACT_PERSISTENT_STORE =============================================================================================
    // Group: Identity & access control
    owner: Address;
    ownerAfterRecovery: Address; // for social recovery
    minter: Address; //map for multiple peer contracts, treat as treasury + sudo(unbacked minting & force transfer like in governance), use dao address
    nominee: Address = address("EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c");
    invitor: Address?; //guarantor/offchain-contact responsible for kyc + education + proposal, propagator,TODO: nominee is appointed for all invited after it's demise; inactive account if null(no ops allowed perhaps)
    invitor0: Address?; // to complain about invitor etc and getting blocked

    // Group: Financial state
    balance: Int as coins; // TODO: as uint20 - 1billion, rest is wealth taxed to treasury, coz every fortunate(birth, marriage) & unfortunate(accidents,health,death) are covered by treasury
    turnover: Int as coins = 0; // for txnFee/taxes, votes in public works
    debts: map<Address, Int as coins>; //uint20>; //1,048,576, mbrp*maxConnections(friends+follower+following)
    insurance: Insurance = Insurance { emi: 0, startStop: 0 };

    // Group: Connections & relationship maps
    invited: map<Address, Int as coins>; // kyc friends, TODO: need counter/check?or default exitCode5isEnough
    friends: map<Address, Int as coins>;
    closeFriends: map<Address, Bool>; // for social recovery TODO: don't go beyond 16
    closeFriendsCount: Int as uint4 = 0; // 16
    recoveryValidatorsCount: Int as uint4 = 0;
    pendingRequests: map<Address, Int as uint12>;
    followers: map<Address, Int as coins>;
    followings: map<Address, Int as coins>; //4096 TODO: use max 255 coz of !storage/msg constraints

    // Group: Reporting & disputes
    reports: map<Address, Bool>; //TODO: consider reporter side data store then support and dispute there for less txns,tradeoff -> only one report at aTime
    reportReason: Bool = false; // true for genuineClosingOnDeath, false for fraud/duplicateIdsAccounts
    reporterCount: Int as uint10 = 0; //TODO: delegate2dao/admin handles out of range complaints
    disputerCount: Int as uint10 = 0; //1024
    reportResolutionTime: Int as uint32 = 0; //4,294,967,296

    // Group: Connection counters & flags
    connections: Int as uint8 = 0; //256
    terminated: Bool = false; // TODO: to stop incoming txn maybe or use other approach
    //bloacklist: map<Address, Int as uint8>;//blocklist+blacklist
    //adminOps
    // Dynamically adjustable configuration parameters
    frozen: Bool = true;
    initTime: Int as uint32; // accountAge for trustScore, max age suspicious etc
    recentTxnTime: Int as uint32 = 0; // for insurance emi calculate

    //stores coz of chain/design constraints
    lastMsgTo: Address = address("EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"); //U..JKZ,k..HTW,0..CkT, for reversing bounced msg// TODO: use stack or circular buffer for multimsg usecase

    profession: Int as uint10 = 0; // not aplicable

    version: Int as uint10 = 0;

    //======================================================INIT
    init(owner: Address, minter: Address, balance: Int as coins) { //TODO: take coordinates
        self.owner = owner;
        self.ownerAfterRecovery = owner;
        self.minter = minter;
        self.initTime = now();
        self.balance = balance;
        //self.nominee = sender();
        if (minter == sender()) { // or just do as everyone else or send enquire msg here
            self.frozen = false; // unfrozened by invitor0 for others
            self.invitor = owner;
            self.invitor0 = owner;
            // nominee?
            //self.balance = mbrpAmount; // FIXME
            self.connections += 1;

            MessageParameters { //TODO: fees
                value: ton("0.004"),
                mode: SendPayFwdFeesSeparately,
                to: self.minter,
                body: AccountGenerated { deployer: self.owner, newAccount: owner }.toCell(), // or sender()? free give to receiver
            }.send(); // sender() or sender's owner
        } //else {
        //     self.balance = balance;
        //     //closureWait+=1000;
        // } // ? minter setting some state directly calling receivers
    }

    // bounced(msg: bounced<AccountGenerated>) {
    //     //FIXME:
    // }

    // redundant already by account activation by invitor0
    // receive(msg: AccountGenerated) {
    //     MessageParameters {
    //         value: ton("0.004"), // need? to send
    //         mode: SendPayFwdFeesSeparately,
    //         to: self.invitor!!,
    //         body: CitizenAdded { sender: self.owner, newAccount: msg.newAccount }.toCell(),
    //     }.send();
    // }

    //====================================================RECEIVERS
    receive(msg: JettonTransfer) {
        let sender = sender(); //TODO: Check whole callChain if var is used? thrice?
        let receiver = msg.destination;
        let amount = msg.amount;
        let mbrp = mbrpAmount;
        let body = JettonTransferInternal {
            queryId: msg.queryId,
            amount,
            version: self.version,
            sender,
            responseDestination: msg.responseDestination,
            forwardTonAmount: msg.forwardTonAmount,
            forwardPayload: msg.forwardPayload,
        }.toCell();

        throwUnless(700, sender == self.owner);
        throwUnless(701, !self.terminated); //rootCanRestoreInFutureJustInCase TODO:
        // throwUnless(702, self.invitor != null);// freeze check is enough
        throwUnless(722, !self.frozen || amount == ton("0.101")); // for social recovery by uninvited self account
        forceBasechain(receiver);

        checkEitherForwardPayload(msg.forwardPayload);
        //require(msg.forwardPayload.bits() >= 1, "Invalid forward payload");

        // TODO: redundant ? as everyone knows how much fees to send
        let ctx = context();
        let fwdCount = 1 + sign(msg.forwardTonAmount); // msg.forwardTonAmount is coins, so it's positive TODO: other more than one forwards fee?
        throwUnless(
            703,
            ctx.value >
            msg.forwardTonAmount +
            fwdCount * ctx.readForwardFee() +
            getForwardFee(walletStateInitCells, walletStateInitBits, false) + // TODO:
            (2 * getComputeFee(gasForTransfer, false) + minTonsForStorage),
        );

        if (amount < ton("1")) {
            if (amount == ton("0.1")) { //invite
                self.invite(receiver, 2 * mbrp);
                body = InviteInternal {
                    queryId: msg.queryId,
                    amount, // 0.1
                    sender,
                    invitor: self.invitor!!,
                    responseDestination: msg.responseDestination,
                    forwardTonAmount: msg.forwardTonAmount,
                    forwardPayload: msg.forwardPayload,
                }.toCell();
            } else if (amount == ton("0.2")) { //send friendRequest
                self.friendRequest(2 * mbrp, msg);
                return;
            } else if (amount == ton("0.3")) {
                self.confirmFRequest(receiver, msg);
                return;
            } else if (amount == ton("0.14")) {
                self.unfriend(receiver, msg);
                return;
            } else if (amount == ton("0.6")) { // 0.2 token - report tosViolate
                self.report(sender, receiver, mbrp, true, msg);
                return;
            } else if (amount == ton("0.7")) { // 0.5 token - report onDeath
                self.report(sender, receiver, mbrp, false, msg);
                return;
            } else if (amount == ton("0.8")) { // 0.3 token - dispute
                self.dispute(sender, mbrp, receiver, msg);
                return;
            } else if (amount == ton("0.9")) { // 0.4 token - process report
                self.reportResolution(receiver, msg);
                return;
            } else if (amount == ton("0.4")) { // 0.4 token - process report
                //self.nominee = receiver;
                self.changeNominee(receiver);
                return; //maybe notify msg.destination
            } else if (amount == ton("0.5")) { // 0.1 token - invite/follow/unfollow
                self.follow(receiver, mbrp, msg); //TODO: location params from custom payload forwardPayload
                return;
            } else if (amount == ton("0.12")) {
                self.unfollow(receiver, mbrp, msg);
                return;
            } else if (amount == ton("0.11")) { //clean requests to free contract storage
                self.clearAllRequests();
                return;
            } else if (amount == ton("0.13")) { //clean requests to free contract storage
                self.unInvite(receiver, msg);
                return; // centralised approach, use report tosViolate instead that'll freeze account instantly
            } else if (amount == ton("0.02")) { // reserved for invite
                throwUnless(704, false); //invite(mbrp),burn, reward(2x mbrp)
                // } else if (amount == ton("0.22")) {
                //     self.updateInvitor0();
                //     return;
            } else if (amount == ton("0.98")) { // kind of burn
                self.burn(ton("101"));
            } else if (amount == ton("0.99")) {
                self.closeFriends.set(receiver, true);
                self.closeFriendsCount += 1;
                return;
            } else if (amount == ton("0.101")) { // social recovery FIXME not here maybe
                //amount = ton("100");// refunded later if genuine recovery/noWorries going to your account
                self.burn(ton("100")); // below burn also
            } else if (amount == ton("0.102")) {
                let _ = self.closeFriends.del(receiver);
                return;
            } else if (amount == ton("0.999")) {
                self.requestUpgrade(self.minter); // redundant when p2p
                return;
            } else if (amount == ton("0.501")) {
                self.voteProposal(receiver);
                return;
            } else if (amount == ton("0.401")) {
                self.insurance(amount);
                return;
            } else if (amount == ton("0.402")) {
                self.insurance(amount);
                return;
            } else if (amount == ton("0.404")) {
                self.insurance(amount);
                return;
            }
            // else if (amount == ton("0.21")) { // getterOps
            //     let invitorNominee = self.get_invitor_nominee();//FIXME:
            //     self.getterCall(invitorNominee);
            //     return;
            // } else if (sender == self.minter) { // Admin operations (minter only)
            //     self.adminAction(msg);
            // }
        } else if (receiver == self.minter) { // for getting funding for public works, TODO: have open pubkey acc if minter doesn't work in frontend
            self.burn(muldivc(amount, 5, 100)); // stake 5% of demanded amount, returned if resolution passed or adjust/beSatisfied in funds provided
            MessageParameters {
                value: 0,
                to: self.minter,
                body: ApplyGrant {
                    sender: self.owner,
                    amount,
                }.toCell(),
            }.send();
            return;
        } else {
            self.burn(amount);
        }
        DeployParameters {
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail, // ok?
            body,
            init: self.getInit(receiver),
        }.toShard(receiver.getShard()).send();
    }

    receive(msg: JettonTransferInternal) {
        let sender = msg.sender;
        self._correctSender(sender);
        let amount = msg.amount;
        // let queryId = msg.queryId;
        // let forwardTonAmount = msg.forwardTonAmount;
        // let forwardPayload = msg.forwardPayload;
        // let responseDestination = msg.responseDestination;

        //throwUnless(732, msg.version == self.version);
        //auto upgrade both sides, not sent by default to reduce payload size (upgrades r few anyways when stable)
        if (msg.version == self.version) { // optimistic
            //continue;
        } else if (msg.version > self.version) {
            // request from peer (scalable)
            self.requestUpgrade(sender());
            return;
        } else {
            // send upgrade to peer
            self.sendUpgrade();
            return;
        }

        //self.checkInternal(sender, amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);
        if (amount < ton("1")) {
            if (amount == ton("0.23") && sender == self.invitor0!!) {
                self.frozen = false;
            } else if (amount == ton("0.24") && sender == self.invitor0!!) { // redundant? use reports instead
                self.frozen = true;
            } else if (amount == ton("0.02")) { // TODO: avoid sending from minter
                self.burnForce(sender, mbrpAmount); // TODO: notity minter
            } else if (amount == ton("0.98")) {
                //self.mintInternal(ton("101"));// recovery topup
                self.balance += ton("100"); // no need to check
                return;
            } else if (amount == ton("0.101")) {
                self.startRecovery(sender);
                self.mintInternal(ton("100"));
            } else if (amount == ton("0.103")) { // validateRecovery
                self.validateRecovery(sender);
            }
            //     //else if (senderJWC == self.minter && amount == ton("0.1")) { //TODO: use for other rootOps
            //     self.inviteInternal(sender, mbrpAmount); // 0 gives misti error
            // }
        } else {
            self.mintInternal(amount);
        }

        let ctx: Context = context();
        let msgValue: Int = ctx.value;
        let tonBalanceBeforeMsg = myBalance() - msgValue;

        if (msg.forwardTonAmount > 0) {
            let fwdFee: Int = ctx.readForwardFee();
            msgValue -= msg.forwardTonAmount + fwdFee; // FIXME: this is not updated on init
            MessageParameters {
                to: self.owner,
                value: msg.forwardTonAmount,
                mode: SendPayGasSeparately,
                bounce: false,
                body: JettonNotification { // 0x7362d09c -- Remind the new Owner
                    queryId: msg.queryId,
                    amount: msg.amount,
                    sender: msg.sender,
                    forwardPayload: msg.forwardPayload,
                }.toCell(),
            }.send();
        }

        nativeReserve(max(tonBalanceBeforeMsg, minTonsForStorage), ReserveAtMost);
        // 0xd53276db -- Cashback to the original Sender
        if (msg.responseDestination != null && msgValue > 0) {
            MessageParameters {
                to: msg.responseDestination!!,
                value: msgValue, // NOTE: VALUE + REM BALANCE?
                mode: SendRemainingBalance | SendIgnoreErrors,
                bounce: false,
                body: JettonExcesses { queryId: msg.queryId }.toCell(),
            }.send();
        }
    }

    //====================================================INTERNAL_FUNCTIONS==================================================
    // AUTOMATED THROUGH INVITE MSG
    // inline fun updateInvitor0() {
    //     MessageParameters {
    //         to: contractAddress(self.getInit(self.invitor!!)),
    //         value: 0,
    //         mode: SendRemainingValue, // SendIgnoreErrors or bounceOnActionFail
    //         body: EnquireInvitor {
    //             sender: self.owner,
    //         }.toCell(),
    //     }.send();
    // }

    // receive(msg: EnquireInvitor) {
    //     throwUnless(700, self.invited.exists(msg.sender)); // TODO: connection()exists
    //     MessageParameters {
    //         to: sender(),
    //         value: 0,
    //         mode: SendRemainingValue,
    //         body: TakeInvitor {
    //             sender: self.owner,
    //             invitor: self.invitor!!,
    //         }.toCell(),
    //     }.send();
    // }

    // receive(msg: TakeInvitor) {
    //     throwUnless(700, msg.sender == self.invitor!!);
    //     self.invitor0 = msg.invitor;
    // }

    inline fun invite(receiver: Address, amount: Int) {
        self.connection(receiver);
        //self.friends.set(receiver, amount);
        self.invited.set(receiver, amount);
        self.lastMsgTo = receiver;
        self.connections += 1;
        self.mintInternal(amount); // 2x, NOTE: now what do i care(minter is informed on init of acc)
        if (self.nominee == self.invitor) { // TODO: bounce and sender invitor as nominee
            self.nominee = receiver;
        }

        //  // now notify external or to connections TODO: redundant coz invitor approves anyways
        // MessageParameters {
        //     value: ton("0.1"),
        //     mode: SendPayFwdFeesSeparately,
        //     to: self.invitor!!,
        //     body: AccountGenerated { deployer: self.owner, newAccount: receiver }.toCell(), // polymorphism
        // }.send();
    }

    bounced(msg: bounced<InviteInternal>) {
        let _ = self.invited.del(self.lastMsgTo);
        self.connections -= 1;
        //self.lastMsgTo = null;
        //self.balance -= msg.amount; // safe? can other txn race?
        self.burnForce(self.lastMsgTo, 2 * msg.amount); //2x mbrp//bounce debtBurnToMinter
    }

    receive(msg: InviteInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 1, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.inviteInternal(msg.sender, msg.invitor, mbrpAmount); //msg.amount); TODO: Clean it code

        // MessageParameters {
        //     value: ton("0.004"),
        //     mode: SendPayFwdFeesSeparately,
        //     to: self.minter,
        //     body: AccountGenerated { deployer: msg.sender, newAccount: self.owner }.toCell(),
        // }.send();
    }

    inline fun inviteInternal(sender: Address, invitor: Address, amount: Int) {
        throwUnless(723, self.invitor == null || self.frozen);
        self.invitor = sender;
        self.nominee = sender;
        self.invitor0 = invitor;

        self.mintInternal(amount);
        // self.frozen = false;//true on init, invitor's invitor can unfreeze
        // self.frozen ? false : false;
        // self.lastMsgTo = sender;// used for bounced
        // if (self.frozen) {// recursion
        //     foreach (invitee, amount in self.invited) {
        //         MessageParameters {// TODO: fees paid by receivers
        //             to: contractAddress(self.getInit(invitee)),
        //             value: 0,
        //             mode: SendRemainingValue | SendBounceIfActionFail,
        //             body: ReInviteInternal {
        //                 queryId: msg.queryId,
        //                 amount,//FIXME: internal?
        //                 sender: self.owner,
        //                 responseDestination: msg.responseDestination,
        //                 forwardTonAmount: msg.forwardTonAmount,
        //                 forwardPayload: msg.forwardPayload,
        //             }.toCell(),

        //         }.send();
        //     }
        // }
    }

    // receive(msg: ReInviteInternal) {//for chain Unfreeze
    //      let queryId = msg.queryId;
    //     let forwardTonAmount = msg.forwardTonAmount;
    //     let forwardPayload = msg.forwardPayload;
    //     let responseDestination = msg.responseDestination;
    //     self.checkInternal(msg.sender, msg.amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);

    //     throwUnless(721, self.invitor!! == msg.sender);
    //     self.invitor = msg.sender;
    //     self.frozen = false;
    // }

    // bounced(msg: bounced<ReInviteInternal>) {//FIXME:
    //     let _ = self.invited.del(self.lastMsgTo!!);
    //     self.burnForce(self.lastMsgTo!!, msg.amount);
    // }

    inline fun unInvite(receiver: Address, msg: JettonTransfer) { // TODO: just use reports for control n inviter for whereabouts
        throwUnless(721, self.invited.del(receiver));
        let amount = self.invited.get(receiver)!!; // TODO: move line up?
        //self.burnForce(receiver, amount);
        self.burn(amount);

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: UnInviteInternal {
                queryId: msg.queryId,
                amount: amount / 2,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        self.lastMsgTo = receiver;
        self.connections -= 1;
    }

    bounced(msg: bounced<UnInviteInternal>) {
        let amount = 2 * msg.amount;
        self.invited.set(self.lastMsgTo, amount);
        //self.mintInternal(amount);
        self.balance += amount;
        self.connections += 1;
    }

    receive(msg: UnInviteInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 2, queryId, forwardTonAmount, forwardPayload, responseDestination);

        throwUnless(721, self.invitor == msg.sender); //redundant bothSide check for unBounced s
        self.frozen = true;
        //maybe no burns if coz someone will reinvite eventually, don't mint THEN
        self.burnForce(msg.sender, msg.amount);
    }

    inline fun friendRequest(amount: Int, msg: JettonTransfer) {
        self.connection(msg.destination);
        //throwUnless(715, msg.amount <= mbrpAmount);//TODO:
        MessageParameters {
            to: contractAddress(self.getInit(msg.destination)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: FriendRequestInternal {
                queryId: msg.queryId,
                amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();
    }

    receive(msg: FriendRequestInternal) {
        throwUnless(714, self.invitor != null);
        throwUnless(250, self.connections < 250);

        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.pendingRequests.set(msg.sender, msg.amount);
    }

    inline fun confirmFRequest(receiver: Address, msg: JettonTransfer) {
        throwUnless(706, self.pendingRequests.exists(receiver));

        let amount = self.pendingRequests.get(receiver)!!;
        self.mintInternal(amount);

        self.friends.set(receiver, amount);

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: ConfirmRequestInternal {
                queryId: msg.queryId,
                amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        self.lastMsgTo = receiver;
        let _ = self.pendingRequests.del(receiver);
        self.connections += 1;
    }

    bounced(msg: bounced<ConfirmRequestInternal>) {
        let last = self.lastMsgTo;
        let _ = self.friends.del(last);
        //self.balance -= msg.amount;
        self.burnForce(last, msg.amount); //FIXME: whatIf was in followers?update otherSide following

        self.pendingRequests.set(last, msg.amount);
        self.connections -= 1;
    }

    receive(msg: ConfirmRequestInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 1, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.mintInternal(msg.amount);
        self.friends.set(msg.sender, msg.amount);
        self.connections += 1;
    }

    inline fun unfriend(receiver: Address, msg: JettonTransfer) {
        throwUnless(720, self.friends.exists(receiver));
        let amount = self.friends.get(receiver)!!;
        let _ = self.friends.del(receiver);
        self.burnForce(receiver, amount);

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: UnfriendInternal {
                queryId: msg.queryId,
                amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        self.lastMsgTo = receiver;
        self.connections -= 1;
    }

    bounced(msg: bounced<UnfriendInternal>) {
        let last = self.lastMsgTo;
        self.friends.set(last, msg.amount);
        //self.mintInternal(msg.amount);
        self.balance += msg.amount;
        self.connections += 1;
    }

    receive(msg: UnfriendInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 2, queryId, forwardTonAmount, forwardPayload, responseDestination);

        let _ = self.friends.del(msg.sender);
        self.burnForce(msg.sender, msg.amount);
    }

    inline fun clearAllRequests() {
        if (!self.pendingRequests.isEmpty()) {
            self.pendingRequests = null; //emptyMap();
        }
        emit("clearedPendingRequests".asComment()); //TODO: handle events
    }

    inline fun follow(receiver: Address, amount: Int, msg: JettonTransfer) {
        self.connection(receiver);

        self.followings.set(receiver, amount);

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: FollowInternal {
                queryId: msg.queryId,
                amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        self.lastMsgTo = receiver;
        self.connections += 1;
    }

    bounced(msg: bounced<FollowInternal>) {
        let _ = self.followings.del(self.lastMsgTo);
        self.connections -= 1;
    }

    receive(msg: FollowInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 1, queryId, forwardTonAmount, forwardPayload, responseDestination);

        throwUnless(714, self.invitor != null);
        throwUnless(250, self.connections < 250);

        self.balance += mbrpAmount;

        self.followers.set(msg.sender, mbrpAmount);
        self.connections += 1;

        //TODO: tells follower's followers about this follow or invite and add to network
        //emitEvent(1, msg.sender, self.owner, msg.amount);
    }

    inline fun unfollow(receiver: Address, amount: Int, msg: JettonTransfer) {
        //throwUnless(717, self.followings.exists(receiver));
        throwUnless(717, self.followings.del(receiver)); //OPTIMISTIC

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: UnfollowInternal {
                queryId: msg.queryId,
                amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        self.lastMsgTo = receiver;
        self.connections -= 1;
    }

    bounced(msg: bounced<UnfollowInternal>) {
        self.followings.set(self.lastMsgTo, msg.amount);
        self.connections += 1;
    }

    receive(msg: UnfollowInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 2, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.unfollowInternal(msg.sender, msg.amount);
    }

    inline fun unfollowInternal(sender: Address, amount: Int) {
        throwUnless(707, self.reporterCount == 0); // can't unfollow reported

        let _ = self.followers.del(sender);

        if (self.connections > 0) {
            self.connections -= 1;
        }

        self.burnForce(sender, amount);
    }

    inline fun report(sender: Address, receiver: Address, amount: Int, reason: Bool, msg: JettonTransfer) { // TODO: forgiving(throttles chain) or punitive(just fee)+handle load on frontend.
        //require receiver is from same contract
        //require(receiver != self.owner || myAddress(), "Cannot report self");//programmedInHumans
        //throwUnless(708, receiver != self.minter);
        // if (receiver == self.minter) {//govtWay of discouraging smartAsses/badBehavior(stick over carrot)
        //     self.balance -= self.balance;
        //     require(false, "uROfficiallyFuckedBro!");
        // }
        self.balance -= amount;
        throwUnless(709, self.balance >= 0);
        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: ReportInternal {
                queryId: msg.queryId,
                amount,
                reason,
                sender,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();

        //self.lastMsgTo = receiver;
    }

    bounced(msg: bounced<ReportInternal>) { self.balance += msg.amount }

    receive(msg: ReportInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);
        self.reportInternal(msg.sender, msg.reason, msg);
    }

    inline fun reportInternal(sender: Address, reason: Bool, msg: ReportInternal) {
        //TODO: invitor auto disputes or noNeed (consider disputed implicitly)
        if (reason) {
            self.reportReason = reason;
        } //false byDefault//TODO: reason complete?
        throwUnless(702, self.invitor != null);
        throwUnless(710, !self.reports.exists(sender)); // already reported
        self.reports.set(sender, true);
        self.reporterCount += 1;
        self.reportResolutionTime = now() + closureWait; //TODO: INC time onlyIf this overtakes others(disputers)

        let receiver = self.invitor!!;
        //let receiverAddr = contractShardBasechainAddress(walletInit);
        //burn/stake from receiver's invitor once in case of tosViolate only?4Punish
        //if (reason && self.reports == null) { // TODO burn/stake from invitor always?
        if (self.reporterCount == 0) { // TODO burn/stake from invitor always?
            // confiscate on tosViolate
            self.terminated = true;
            MessageParameters {
                to: contractAddress(self.getInit(receiver)),
                value: 0,
                mode: SendRemainingValue,
                body: JettonTransferInternal { //TODO if s=r then burn maybe, bounce? inThisApproach?/reuse
                    queryId: msg.queryId,
                    amount: ton("0.02"),
                    version: self.version,
                    sender: self.owner,
                    responseDestination: msg.responseDestination,
                    forwardTonAmount: msg.forwardTonAmount,
                    forwardPayload: msg.forwardPayload,
                }.toCell(),
            }.send();
        }
    }

    inline fun dispute(sender: Address, amount: Int, receiver: Address, msg: JettonTransfer) {
        //stake
        throwUnless(708, receiver != self.minter);
        throwUnless(708, sender != receiver);
        self.balance -= amount;
        throwUnless(709, self.balance >= 0);

        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            mode: SendRemainingValue | SendBounceIfActionFail,
            body: DisputeInternal {
                queryId: msg.queryId,
                amount,
                sender,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();
    }

    bounced(msg: bounced<DisputeInternal>) { self.balance += msg.amount }

    receive(msg: DisputeInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.disputeInternal(msg.sender);
    }

    inline fun disputeInternal(sender: Address) {
        throwUnless(711, self.reporterCount > 0); // account not reported
        self.reports.set(sender, false);
        self.disputerCount += 1;
        self.reportResolutionTime = now() + closureWait;
    }

    inline fun reportResolution(receiver: Address, msg: JettonTransfer) {
        MessageParameters {
            to: contractAddress(self.getInit(receiver)),
            value: 0,
            bounce: false,
            mode: SendRemainingValue | SendBounceIfActionFail, //FIXME
            body: ResolutionInternal {
                queryId: msg.queryId,
                amount: msg.amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
                forwardTonAmount: msg.forwardTonAmount,
                forwardPayload: msg.forwardPayload,
            }.toCell(),

        }.send();
    }

    receive(msg: ResolutionInternal) {
        let queryId = msg.queryId;
        let forwardTonAmount = msg.forwardTonAmount;
        let forwardPayload = msg.forwardPayload;
        let responseDestination = msg.responseDestination;
        self.checkInternal(msg.sender, msg.amount, 0, queryId, forwardTonAmount, forwardPayload, responseDestination);

        self.reportResolutionInternal(msg);
    }

    inline fun reportResolutionInternal(msg: ResolutionInternal) {
        throwUnless(706, self.reportResolutionTime > 0); //notOptional it's semantic otherwise need null
        throwUnless(703, now() >= self.reportResolutionTime);

        let reporters = self.reporterCount;
        let disputers = self.disputerCount;
        let mbrp = mbrpAmount;

        // decide winner
        // reporters should be more than disputers no ties allowed
        let reportWinCloseAcc: Bool = reporters > disputers; //>= IF invitor NOT disputes byDefault 

        // reward winners 2x mbrp(stake+reward), losers lose stake
        let losersCount: Int = 0;
        if (reportWinCloseAcc) {
            losersCount = disputers;
        } else {
            losersCount = reporters;
        }
        let rewarded: Int = 0;

        // Distribute rewards: first `losersCount` winners get 2x, remaining winners get 1x.
        // Remove entries as we process them so the following foreach (below) becomes a no-op.
        foreach (addr, reporter in self.reports) { //TODO: can send only around 250 msg(maybe keep count & send last msg to self to process remaining txns.),forNow maxConn are 200
            // determine if this entry is a winner
            if ((reporter && reportWinCloseAcc) || (!reporter && !reportWinCloseAcc)) {
                let reward: Int = 0;
                if (rewarded < losersCount) {
                    reward = 2 * mbrp; // 2x mbrp
                    rewarded += 1;
                } else {
                    reward = mbrp; // release stake (1x mbrp)
                }

                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue,
                    body: JettonTransferInternal {
                        queryId: 0, //FIXME:
                        amount: reward,
                        version: self.version,
                        sender: self.owner, // reward
                        responseDestination: self.owner, //addr TODO
                        forwardTonAmount: 0,
                        forwardPayload: msg.forwardPayload,
                    }.toCell(),
                }.send();
            }
        }

        if (reportWinCloseAcc) { //TODO; REASON MATTERS?
            // burn minted mbrp from followers/followings/invited, 2x friends, 3x invitor

            foreach (addr, amount in self.followings) {
                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue, //TODO: addr pays fees
                    body: AccCloseBurnInternal {
                        queryId: msg.queryId,
                        amount,
                        sender: self.owner,
                        responseDestination: msg.responseDestination,
                        forwardPayload: msg.forwardPayload,
                        forwardTonAmount: msg.forwardTonAmount,
                    }.toCell(),
                }.send();
            }

            foreach (addr, amount in self.followers) {
                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue,
                    body: AccCloseBurnInternal {
                        queryId: msg.queryId,
                        amount,
                        sender: self.owner,
                        responseDestination: msg.responseDestination,
                        forwardPayload: msg.forwardPayload,
                        forwardTonAmount: msg.forwardTonAmount,
                    }.toCell(),
                }.send();
            }

            foreach (addr, amount in self.friends) {
                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue,
                    body: AccCloseBurnInternal {
                        queryId: msg.queryId,
                        amount: amount * 2, //2x mbrp
                        sender: self.owner,
                        responseDestination: msg.responseDestination,
                        forwardPayload: msg.forwardPayload,
                        forwardTonAmount: msg.forwardTonAmount,
                    }.toCell(),
                }.send();
            }

            foreach (addr, amount in self.invited) {
                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue,
                    body: AccCloseBurnInternal { //TODO: mark frozen/inactive
                        queryId: msg.queryId,
                        amount: 3 * amount, //3x mbrp
                        sender: self.owner,
                        responseDestination: msg.responseDestination,
                        forwardPayload: msg.forwardPayload,
                        forwardTonAmount: msg.forwardTonAmount,
                    }.toCell(),
                }.send();
                // set their invotor null
            }
            // burn 3x from invitor
            MessageParameters {
                to: contractAddress(self.getInit(self.invitor!!)),
                value: 0,
                mode: SendRemainingValue,
                body: AccCloseBurnInternal { //TODO: mark frozen/inactive
                    queryId: msg.queryId,
                    amount: 3 * mbrpAmount, //3x mbrp
                    sender: self.owner,
                    responseDestination: msg.responseDestination,
                    forwardPayload: msg.forwardPayload,
                    forwardTonAmount: msg.forwardTonAmount,
                }.toCell(),
            }.send();

            if (!self.reportReason) { // or release funds in any case
                // INSURANCE PAY
                let payback: Int = 0;
                if (self.insurance.emi > 0 && now() - self.initTime < ton("1261.440")) { // only < 40years old are paid
                    let emi = self.insurance.emi;
                    payback = muldivc(8, (self.initTime + self.insurance.startStop), 10) * emi;
                }

                MessageParameters { // bounce?
                    to: contractAddress(self.getInit(self.nominee)),
                    value: 0,
                    mode: SendPayFwdFeesSeparately,
                    body: JettonTransferInternal {
                        queryId: 0, //FIXME:
                        amount: self.balance + payback,
                        version: self.version,
                        sender: self.owner,
                        responseDestination: msg.sender,
                        forwardTonAmount: 0,
                        forwardPayload: msg.forwardPayload,
                    }.toCell(),
                }.send();

                // notify minter to update deficits
                MessageParameters {
                    to: self.minter,
                    value: 0,
                    mode: SendPayGasSeparately | SendIgnoreErrors,
                    bounce: false,
                    body: JettonBurnNotification {
                        queryId: 0,
                        amount: payback,
                        sender: emptyAddress(),
                        responseDestination: msg.sender, // or use this
                    }.toCell(),
                }.send();
            }
            // OR set nominee as owner + new connectStakes/credits , stop incoming
            self.terminated = true;

            // settle debts
            foreach (addr, amount in self.debts) { // TODO only this may bounce
                MessageParameters {
                    to: contractAddress(self.getInit(addr)),
                    value: 0,
                    mode: SendRemainingValue,
                    body: AccCloseBurnInternal { //TODO: mark frozen/inactive
                        queryId: msg.queryId,
                        amount,
                        sender: self.owner,
                        responseDestination: msg.responseDestination,
                        forwardPayload: msg.forwardPayload,
                        forwardTonAmount: msg.forwardTonAmount,
                    }.toCell(),
                }.send();
            }
        } else {
            // reset report-related state
            self.reports = null;
            self.reportResolutionTime = 0;
            self.reporterCount = 0;
            self.disputerCount = 0;
            self.reportReason = false;
        }
    }

    receive(msg: AccCloseBurnInternal) {
        self.burnForce(msg.sender, msg.amount);
        //FIXME:
    }

    bounced(msg: bounced<AccCloseBurnInternal>) {
        //notify treasury or external if p2p wallet
    }

    receive(msg: ProvideWalletBalance) {
        throwUnless(701, !self.terminated);
        let info: VerifyInfo? = null;
        if (msg.includeVerifyInfo) {
            info = VerifyInfo {
                minter: self.minter,
                owner: self.owner,
                code: myCode(),
            };
        }

        MessageParameters {
            body: TakeWalletBalance {
                balance: self.balance,
                verifyInfo: info,
            }.toCell(),
            to: msg.receiver,
            value: 0,
            mode: SendRemainingValue,
        }.send();
    }

    receive(msg: JettonBurn) {
        throwUnless(701, !self.terminated);
        // we can skip forceBasechain here because with other checks in place it's not possible
        // to acquire jettons outside of basechain, so amount check is enough
        throwUnless(700, sender() == self.owner);

        self.balance -= msg.amount;
        throwUnless(709, self.balance >= 0);

        let ctx = context();
        let fwdFee: Int = ctx.readForwardFee();
        throwUnless(703, ctx.value > (fwdFee + 2 * getComputeFee(gasForBurn, false)));

        MessageParameters {
            to: self.minter,
            value: 0,
            mode: SendRemainingValue,
            bounce: true,
            body: JettonBurnNotification {
                queryId: msg.queryId,
                amount: msg.amount,
                sender: self.owner,
                responseDestination: msg.responseDestination,
            }.toCell(),
        }.send();
    }

    receive(msg: ClaimTON) {
        // throwUnless(701, !self.terminated);
        throwUnless(700, sender() == self.owner);
        nativeReserve(minTonsForStorage, ReserveExact | ReserveBounceIfActionFail);

        // we allow bounce here and don't handle it, if claim fails we just accept the TONs back
        MessageParameters {
            to: msg.receiver,
            value: 0,
            mode: SendRemainingBalance,
        }.send();
    }

    // receive("updateMBRP") {
    //     throwUnless(701, !self.terminated);
    //     //TODO: v2
    // }

    bounced(msg: bounced<JettonTransferInternal>) {
        self.balance += msg.amount;
    }

    bounced(msg: bounced<JettonBurnNotification>) {
        //TODO: send again
        self.balance += msg.amount;
    }

    // bounced(rawMsg: Slice) {// fallback bounce handler
    //     let opcode = rawMsg.loadUint(32);
    //     if (opcode == TooBigToFit.opcode()) {
    //       // Now, you can obtain the truncated bits that did fit in the remaining
    //       // 224 bits of the bounced message.
    //       // Proceed with caution!
    //       let truncatedData = rawMsg.preloadUint(224);
    //     }
    // }
    //     message TooBigToFit {
    //     data: Int as uint225; // 1 bit is truncated, so the field could not be accessed directly
    // }

    // helpers
    // fun checks(sender: Address, receiver: Address) {
    //     throwUnless(700, sender == self.owner);// incorrect sender
    //     throwUnless(701, !self.terminated);//rootCanRestoreJustInCase
    //     throwUnless(702, self.invitor != null || self.owner == self.minterOwner);//TODO:
    //     forceBasechain(receiver);

    //     checkEitherForwardPayload(msg.forwardPayload);

    //     let ctx = context();
    //     let fwdCount = 1 + sign(msg.forwardTonAmount); // msg.forwardTonAmount is coins, so it's positive
    //     throwUnless(
    //         703,
    //         ctx.value >
    //         msg.forwardTonAmount +
    //         fwdCount * ctx.readForwardFee() +
    //         getForwardFee(walletStateInitCells, walletStateInitBits, false) +
    //         (2 * getComputeFee(gasForTransfer, false) + minTonsForStorage)
    //     );
    // }

    inline fun startRecovery(sender: Address) {
        self.ownerAfterRecovery = sender;
    }

    inline fun validateRecovery(sender: Address) {
        throwUnless(702, self.closeFriends.exists(sender));
        if (self.recoveryValidatorsCount >= divc(self.closeFriendsCount, 2)) {
            self.owner = self.ownerAfterRecovery;
            self.recoveryValidatorsCount = 0;
        } else {
            self.recoveryValidatorsCount += 1;
        }
    }

    inline fun requestUpgrade(from: Address) {
        MessageParameters {
            to: from,
            value: 0,
            bounce: false,
            mode: SendRemainingValue,
            body: RequestUpgradeCode {
                version: self.version,
            }.toCell(),
        }.send();
    }

    receive(msg: RequestUpgradeCode) {
        self.sendUpgrade();
    }

    fun sendUpgrade() {
        // noNeed to check version
        MessageParameters {
            to: sender(),
            mode: SendRemainingValue,
            value: 0,
            bounce: false,
            body: UpgradeCode {
                sender: self.owner,
                code: myCode(),
            }.toCell(),
        }.send();
    }

    receive(msg: UpgradeCode) {
        //throwUnless(702, sender() == self.minter);
        let wallet: StateInit = self.getInit(msg.sender);
        if (!(wallet.hasSameBasechainAddressWithoutShard(sender()))) { // peer or root
            throwUnless(700, self.minter == sender());
        }
        if (msg.code != null) { // msg.code!!
            setCode(msg.code!!);
            self.version += 1;
            //emit("upgraded".toCell());
        }
        // if (msg.sender == self.minter) {
        MessageParameters { // TODO: handle fees correctly
            to: self.owner,
            value: 0,
            mode: SendRemainingValue | SendIgnoreErrors,
            bounce: false,
            body: JettonExcesses { queryId: 0 }.toCell(),
        }.send();
        //}
    }

    inline fun voteProposal(proposer: Address) {
        MessageParameters {
            to: self.minter,
            mode: SendRemainingValue,
            value: 0,
            body: VoteProposal {
                sender: self.owner,
                proposer,
                turnover: self.turnover,
            }.toCell(),
        }.send();
        // reset turnover maybe TODO:
    }

    inline fun changeNominee(nominee: Address) {
        self.nominee = nominee;
    }

    inline fun insurance(amount: Int) {
        let existingEmi = self.insurance.emi;
        let newEmi = 0;
        if (amount == ton("0.401")) {
            self.insurance.emi = ton("100");
            newEmi = ton("100");
        } else if (amount == ton("0.402")) {
            self.insurance.emi = ton("500");
            newEmi = ton("500");
        } else if (amount == ton("0.404")) { // stop insurance
            self.insurance.emi = 0;
            return;
        }

        if (existingEmi > newEmi) { // decreasing amount resets time
            self.insurance.startStop = now();
        }
    }
    // inline fun adminAction(msg: JettonTransfer) {}

    // inline fun adminActionInternal(msg: JettonTransferInternal) {}

    // inline fun getterCall(body: AnyMessage) {
    //     MessageParameters {
    //         value: 0,
    //         to: sender(),
    //         bounce: false,
    //         body: body.toCell()
    //     }.send();
    // }

    // greed implemented
    receive(msg: Slice) {} // TODO: will this confuse me

    receive() {}

    fun _correctSender(sender: Address) {
        let wallet: StateInit = self.getInit(sender);
        if (!(wallet.hasSameBasechainAddressWithoutShard(sender()))) {
            throwUnless(700, self.minter == sender());
        }
    }

    fun connection(receiver: Address) {
        throwUnless(250, self.connections < 250); // NOTE: const MAX_CONNECTIONS = 250
        throwUnless(
            719,
            self.invitor != receiver && !self.friends.exists(receiver) && !self.followings.exists(receiver) && !self.invited.exists(receiver) && !self.followers.exists(receiver),
        ); //ACCOUNT EXISTS
    }

    fun checkInternal(sender: Address, amount: Int, mint: Int, queryId: Int, forwardTonAmount: Int, forwardPayload: Slice, responseDestination: Address?) { // mintAsUint2ToAvoidNullChecks
        //let senderJWC: Address = sender();
        //throwUnless(701, !self.terminated);
        // need active/unfrozen account or invite or unfreezing or recovery topup action,
        throwUnless(733, !self.frozen || amount == ton("0.1") || amount == ton("0.23") || amount == ton("0.98"));
        self._correctSender(sender);

        //throwUnless(713, amount >= ton("1"));

        // if (msg::op != op::InviteInternal) {
        //     throwUnless(702, self.invitor != null);//noIncomingTxns.
        // }

        let ctx: Context = context();
        let msgValue: Int = ctx.value;
        let tonBalanceBeforeMsg = myBalance() - msgValue;

        if (forwardTonAmount > 0) {
            let fwdFee: Int = ctx.readForwardFee();
            msgValue -= forwardTonAmount + fwdFee; // FIXME: this is not updated on init
            MessageParameters {
                to: self.owner,
                value: forwardTonAmount,
                mode: SendPayGasSeparately,
                bounce: false,
                body: JettonNotification { // 0x7362d09c -- Remind the new Owner
                    queryId,
                    amount,
                    sender,
                    forwardPayload,
                }.toCell(),
            }.send();
        }
        // reusing burnNotif for minting
        if (mint != 0) { // || sender == self.minter in case minter mints > 0
            msgValue -= ctx.readForwardFee();
            let finalSender = sender;
            if (mint == 1) {
                finalSender = emptyAddress(); //use emptyAddress()
            }

            MessageParameters {
                to: self.minter,
                value: 0,
                mode: SendPayGasSeparately | SendIgnoreErrors,
                bounce: false,
                body: JettonBurnNotification { //JettonMintBurnNotify maybe traitViolationOccursThen
                    queryId,
                    amount,
                    sender: finalSender, //use this for mint or burn identifier TODO:
                    responseDestination, // or use this
                }.toCell(),
            }.send();
        }
        nativeReserve(max(tonBalanceBeforeMsg, minTonsForStorage), ReserveAtMost);
        // 0xd53276db -- Cashback to the original Sender
        if (responseDestination != null && msgValue > 0) {
            MessageParameters {
                to: responseDestination!!,
                value: msgValue, // NOTE: VALUE + REM BALANCE?
                mode: SendRemainingBalance | SendIgnoreErrors,
                bounce: false,
                body: JettonExcesses { queryId: 0 }.toCell(),
            }.send();
        }
    }

    fun _deductDebt(amount: Int): Int {
        let remaining: Int = amount;
        // nothing to do
        if (remaining <= 0 || self.debts.isEmpty()) {
            return remaining;
        }

        // Pay debts in map order until remaining is exhausted
        foreach (from, debtVal in self.debts) {
            if (remaining <= 0) { // ==0
                return remaining; // 0
            }

            let debt: Int = debtVal;
            let pay = 0;
            if (remaining >= debt) {
                pay = debt;
            } else {
                pay = remaining;
            }
            debt -= pay;
            remaining -= pay;

            if (debt == 0) {
                let _ = self.debts.del(from);
            } else {
                self.debts.set(from, debt);
            }

            // optional: emit an event for debt payment
            // emitEvent(2, self.owner, from, pay);
        }

        return remaining;
    }

    fun mintInternal(amount: Int) {
        amount = self._deductDebt(amount);
        self.balance += amount;
    }

    fun burnForce(sender: Address, amount: Int) {
        if (amount <= 0) {
            return;
        }

        if (self.balance >= amount) {
            self.balance -= amount;
            return;
        }

        // Not enough balance — consume what is left and record remaining as debt to sender
        let shortfall: Int = amount - self.balance;
        self.balance = 0;

        let prevDebt: Int = 0; // TODO: need this? 
        if (self.debts.exists(sender)) {
            prevDebt = self.debts.get(sender)!!;
        }
        self.debts.set(sender, prevDebt + shortfall);
    }

    fun burn(amount: Int) {
        if (amount > ton("100") || now() - self.recentTxnTime < 86400) { // .1% fees levied on affluents for bounced burns, insurance
            let fee = divc(amount, ton("1000")); //amount / ton("1000");
            amount += fee;
        } // extra fees for payment channels?
        if (self.insurance.emi > 0) {
            let emi = self.insurance.emi;
            let pay = muldivc(emi, now() - self.recentTxnTime, ton("2.628")); // time as ton
            amount += pay;
        }
        //throwUnless(709, self.balance >= amount + ton("1")); // keep minted 1 ton
        throwUnless(709, self.balance >= amount); // invite mints
        self.balance -= amount;
        self.turnover += amount; // TODO: need in burnForce too?
        self.recentTxnTime = now();
        //TODO: notify treasury/minter
    }

    get fun get_wallet_data(): JettonWalletData { // tensor, JettonWalletData? for tuple
        throwUnless(701, !self.terminated);
        return JettonWalletData {
            balance: self.balance,
            owner: self.owner,
            minter: self.minter,
            code: myCode(),
        };
    }

    get fun state(): JettonWalletSharded {
        return self; // you do not have to list all fields of a contract for this
    }

    get fun get_invitor_nominee(): InvitorNominee {
        return InvitorNominee {
            invitor: self.invitor,
            nominee: self.nominee,
        };
    }

    get fun get_friends_and_followings(): FriendsAndFollowings {
        throwUnless(701, !self.terminated);
        //throwUnless(712, self.friends.exists(sender()) || self.followers.exists(sender()));// not authorized
        return FriendsAndFollowings {
            friends: self.friends.asCell(),
            followings: self.followings.asCell(),
            followers: self.followers.asCell(),
            invited: self.invited.asCell(),
            pendingRequests: self.pendingRequests.asCell(),
            debts: self.debts.asCell(),
            reports: self.reports.asCell(),
        };
    }

    get fun other_consts(): OtherStateConsts {
        return OtherStateConsts {
            reportReason: self.reportReason,
            reporterCount: self.reporterCount,
            disputerCount: self.disputerCount,
            reportResolutionTime: self.reportResolutionTime,
            connections: self.connections,
            terminated: self.terminated,
            mbrpAmount,
            closureWait,
            frozen: self.frozen,
            lastMsgTo: self.lastMsgTo,
        };
    }

    fun getInit(address: Address): StateInit {
        return initOf JettonWalletSharded(address, self.minter, 0);
    }
}
// ERROR_CODES ===============================================================================================================
//700 ERR_INCORRECT_SENDER
//const INCORRECT_SENDER: Int = 700;
// ACCOUNT_TERMINATED = 701;
// ACCOUNT_INACTIVE = 702;
// ACCOUNT_FROZEN = 722;
// INSUFFICIENT_TON = 703;
// RESERVED_INTERNAL = 704;
// FOLLOW_INSTEAD = 705;
// NO_PENDING_REQUEST = 706;
// CANT_UNFOLLOW_REPORTED = 707;
// SELF_DISPUTE_NOT_ALLOWED = 708;
// INSUFFICIENT_BALANCE = 709;
// ALREADY_REPORTED = 710;
// ACCOUNT_NOT_REPORTED = 711;
// NOT_AUTHORIZED = 712;
// LESS_THAN_1_TOKEN = 713;
// INVITE_FIRST = 714;
// AMOUNT_EXCEEDS_MBRP = 715;
// ALREADY_FRIEND_OR_FOLLOWING = 716;
// NOT_FOLLOWING = 717;
// DOES_NOT_EXIST = 718; //follower Cleared by confirmRequestInternal bounce
// CONNECTION_EXISTS = 719;
// NOT_FRIEND = 720;
// NOT_INVITOR = 721;
// ALREADY_INVITED = 723;
// UNAUTHORIZED_BURN = 724;
// MINT_CLOSED = 730;
// INSUFFICIENT_GAS_FOR_MINT = 731;
// NEED_WALLET_UPGRADE = 732;
// INACTIVE_ACCOUNT = 733;

// CONTRACT_CONSTS
// MAX_CONNECTIONS = 250; //coz of msg sending constraints during accClosing
//const PAYLOAD: Slice = beginCell().endCell().asSlice();//emptyCell().asSlice();//emptySlice();
// TODO: use consts for events also
/* TODO: implement traits ownableTransferable(to nominee) or internal update, delayedUpgradable
// TODO: p2p upgrades of walletCode + mbrpAmount etc using minter's signed payload
// call minter to update constants(mbrp) but only upwards is possible
//TODO: api to change invitor when/where fees goes for public works
//TODO: change gas co n sts
//if self.version != versionFromSender throw/notify updateVersion
//TODO: inactivate/freeze chain on receive from invitor then send to all invited
//both sides checks can prevent bounced(foreach) side effects at cost of confusion
//map for bounced codes
//TODO: simplify by txn fee as emi/tax/insurance then burn for nonExistent/dead accs
- walletContract as blockchain: p2p init verify
-- turnover & tick-tock taxes

FIXME: incoming gas checks are critical after separate receivers, specially for mint first txns like invite etc.

/* FEATURES
invitor gets 2x, mbrp for invitee, both 2x on friend, followed gets mbrp
unInvite for control, just freeze uninvited's invited not wholeChain cozOfBouncedConstraints
// NOTE: triggers = tick-tock functions
- instead of bounced what if use regular fallback msg receiver TODO: 
- text msg for semantic txns
*/
