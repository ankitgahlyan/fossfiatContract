import "@stdlib/ownable";

/// Message for upgrading contract code and data with a timeout.
message(91) Upgrade {
    /// New code of the contract.
    /// Defaults to `null`, which keeps the previous code.
    code: Cell? = null;

    /// New data of the contract.
    /// Defaults to `null`, which keeps the previous data.
    data: Cell? = null;

    /// Delay in seconds before upgrade can be confirmed.
    /// Defaults to zero, which means the upgrade can be confirmed immediately.
    /// Unused in `Upgradable` trait.
    timeout: Int = 0;
}

/// Message for confirming delayed upgrade execution.
/// Must be sent after the timeout specified in the `Upgrade` message has elapsed.
/// Can only be processed by contracts that implement the `DelayedUpgradable` trait.
message(92) Confirm {}

/// Extended version of `Upgradable` that adds a delay mechanism.
///
/// The upgrade process happens in two steps:
/// 1. Owner initiates an upgrade by sending the `Upgrade` message.
/// 2. After a timeout period, the owner confirms the upgrade by sending the `Confirm` message.
trait DelayedUpgradable with Upgradable {
    /// Contract owner address that can perform upgrades.
    owner: Address;

    /// Current contract version, auto-increments after each upgrade.
    /// Meant to be private and only accessible through the relevant getter.
    _version: Int as uint32;

    /// Timestamp in seconds of the last `Upgrade` message arrival.
    /// Used to enforce a timeout period before the confirmation.
    initiatedAt: Int;

    /// Contains new code, new data, and a timeout period.
    upgradeInfo: Upgrade;

    /// Confirms and executes a pending upgrade only after `upgradeInfo.timeout`
    /// seconds have passed since the last `_initiatedAt`.
    receive(msg: Confirm) {
        require(now() >= self.initiatedAt + self.upgradeInfo.timeout, "DelayedUpgradable: Cannot confirm upgrade before timeout");

        if (self.upgradeInfo.code != null) {
            // Change of code will be applied at the end of this transaction
            setCode(self.upgradeInfo.code!!);
        }
        if (self.upgradeInfo.data != null) {
            // Change of data will be immediate
            setData(self.upgradeInfo.data!!);

            // By the end of every transaction,
            // the Tact compiler automatically adds a call to setData() for your convenience.
            // However, we have already set the data ourselves,
            // so let us stop the execution now to prevent a secondary call to setData().
            throw(0);
        }
    }

    /// Instead of performing an upgrade right away,
    /// saves details for delayed execution.
    override inline fun upgrade(_: Context, msg: Upgrade) {
        self.upgradeInfo = msg;
        self.initiatedAt = now();
    }
}

//
// Helper traits and functions described earlier on this page
//

trait Upgradable with OwnableTransferable {
    owner: Address;
    _version: Int as uint32;

    receive(msg: Upgrade) {
        let ctx = context();
        self.validateUpgrade(ctx, msg);
        self.upgrade(ctx, msg);

        self._version += 1;
    }

    virtual inline fun validateUpgrade(_: Context, __: Upgrade) {
        self.requireOwner();
    }

    virtual inline fun upgrade(_: Context, msg: Upgrade) {
        if (msg.code != null) {
            setCode(msg.code!!);
        }
        if (msg.data != null) {
            setData(msg.data!!);
            throw(0);
        }
    }

    get fun isUpgradable(): Bool {
        return true;
    }

    get fun version(): Int {
        return self._version;
    }
}

asm fun setCode(code: Cell) { SETCODE }

fun emitEvent(eventType: Int, from: Address, to: Address, amount: Int) {
    emit(NetworkEvent {
        eventType,
        from,
        to,
        amount,
    }.toCell());
}

//
// Reference solution
//

message(93) Vote {
    value: Bool;
}

//
// Reference solution
//

struct ProposalInit {
    master: Address;
    proposalId: Int as uint32;
}

message(94) DeployNewProposal {
    votingEndingAt: Int as uint32;
}

message(95) StartVoting {
    cashbackAddress: Address;
    votingEndingAt: Int as uint32;
}

contract ProposalMaster {
    const RESERVED_FUNDS: Int = ton("0.01");

    nextProposalId: Int as uint32 = 0;

    // top up
    receive() {
        nativeReserve(self.RESERVED_FUNDS, ReserveAtMost);
        cashbackBalance(sender());
    }

    receive(msg: DeployNewProposal) {
        require(msg.votingEndingAt >= now(), "Voting must end in the future");

        let proposalInit = initOf Proposal(ProposalInit {
            master: myAddress(),
            proposalId: self.nextProposalId,
        });

        deploy(DeployParameters {
            init: proposalInit,
            mode: SendRemainingValue,
            value: 0,
            body: StartVoting {
                cashbackAddress: sender(),
                votingEndingAt: msg.votingEndingAt,
            }.toCell(),
        });

        self.nextProposalId += 1;
    }

    get fun nextProposalId(): Int { return self.nextProposalId }
}

// ==============================================================================

struct ProposalState {
    yesCount: Int as uint32;
    noCount: Int as uint32;
    master: Address;
    proposalId: Int as uint32;
    votingEndingAt: Int as uint32;
}

contract Proposal {
    const INVALID_TIME: Int = 0;

    master: Address;
    proposalId: Int as uint32;

    votingEndingAt: Int as uint32;

    voters: map<Address, Bool> = emptyMap();
    yesCount: Int as uint7 = 0;
    totalCount: Int as uint7 = 0;

    init(data: ProposalInit) {
        throwUnless(2025, data.master == sender());
        self.proposalId = data.proposalId;
        self.master = data.master;
        self.votingEndingAt = self.INVALID_TIME;
    }

    receive(msg: StartVoting) {
        // init() is implicitly called here, so we know it is called by master
        // StartVoting can be called only once: it is guaranteed by the master contract
        require(self.votingEndingAt == self.INVALID_TIME, "Voting is already started");
        self.votingEndingAt = msg.votingEndingAt;

        cashbackBalance(msg.cashbackAddress);
    }

    receive(msg: Vote) {
        // There cannot be more than 100 voters
        throwUnless(700, self.totalCount < 100);
        // Voting is already finished!
        throwUnless(701, now() < self.votingEndingAt);
        let sender = sender();
        // User already voted
        throwUnless(702, !self.voters.exists(sender));

        self.voters.set(sender, true);

        if (msg.value) {
            self.yesCount += 1;
        }

        self.totalCount += 1;

        cashbackBalance(sender());
    }

    get fun proposalState(): ProposalState {
        return ProposalState {
            yesCount: self.yesCount,
            noCount: self.totalCount - self.yesCount,
            master: self.master,
            proposalId: self.proposalId,
            votingEndingAt: self.votingEndingAt,
        };
    }
}

asm fun cashbackBalance(to: Address) {
    // The following asm is equivalent to
    // ```tact
    // let msg: Cell = beginCell().storeInt(0b010000, 6).storeAddress(to).storeInt(0, 111).endCell();
    // nativeSendMessage(msg, SendRemainingBalance | SendIgnoreErrors);
    // ```
    // but is a bit more gas efficient
    16 PUSHINT       // 0x10, i.e. 0x18 but with bounce = false
    NEWC
    6 STU            // .storeUint(0x10, 6)
    STSLICE          // .storeAddress(to)
    0 PUSHINT        // 0
    111 STUR         // .storeUint(0, 111)
    // 4 zeros for coins and 107 zeros for lt, fees, etc.
    ENDC
    130 PUSHINT       // SendRemainingBalance | SendIgnoreErrors
    SENDRAWMSG
}

// struct Array {
//     // An array of Int values as a map of Int to Int,
//     // with serialization of its keys to uint16 to save space
//     m: map<Int as uint16, Address>;
//     // Length of the array, defaults to 0
//     length: Int = 0;
// }
// // Compile-time constant upper bound for our map representing an array.
// const MaxArraySize: Int = 5_000; // 5,000 entries max, to stay reasonably far from limits
// // Extension mutation function for adding new entries to the end of the array
// extends mutates fun append(self: Array, item: Address) {
//     require(self.length + 1 <= MaxArraySize, "No space in the array left for new items!");
//     self.m.set(self.length, item); // set the entry (key-value pair)
//     self.length += 1; // increase the length field
// }
// // Extension mutation function for inserting new entries at the given index
// extends mutates fun insert(self: Array, item: Address, idx: Int) {
//     require(self.length + 1 <= MaxArraySize, "No space in the array left for new items!");
//     require(idx >= 0, "Index of the item cannot be negative!");
//     require(idx < self.length, "Index is out of array bounds!");
//     // Move all items from idx to the right
//     let i: Int = self.length; // not a typo, as we need to start from the non-existing place
//     while (i > idx) {
//         // Note that we use the !! operator, as we know for sure the value would be there
//         self.m.set(i, self.m.get(i - 1)!!);
//         i -= 1;
//     }
//     // Insert the new item
//     self.m.set(idx, item); // set the entry (key-value pair)
//     self.length += 1; // increase the length field
// }
// // Extension function for getting the value at the given index
// extends fun getIdx(self: Array, idx: Int): Address {
//     require(self.length > 0, "No items in the array!");
//     require(idx >= 0, "Index of the item cannot be negative!");
//     require(idx < self.length, "Index is out of array bounds!");
//     // Note that we use the !! operator, as we know for sure the value would be there
//     return self.m.get(idx)!!;
// }
// // Extension function for returning the last value
// extends fun getLast(self: Array): Address {
//     require(self.length > 0, "No items in the array!");
//     // Note that we use the !! operator, as we know for sure the value would be there
//     return self.m.get(self.length - 1)!!;
// }
// // Extension mutation function for deleting an entry at the given index and returning its value
// extends mutates fun deleteIdx(self: Array, idx: Int): Address {
//     require(self.length > 0, "No items in the array to delete!");
//     require(idx >= 0, "Index of the item cannot be negative!");
//     require(idx < self.length, "Index is out of array bounds!");
//     // Remember the value that is going to be deleted
//     let memorized = self.m.get(idx)!!;
//     // Move all items from idx onwards to the left
//     let i: Int = idx;
//     while (i + 1 < self.length) {
//         // Note that we use the !! operator, as we know for sure the value would be there
//         self.m.set(i, self.m.get(i + 1)!!);
//         i += 1;
//     }
//     self.m.set(self.length - 1, null); // delete the last entry
//     self.length -= 1; // decrease the length field
//     return memorized;
// }
// // Extension mutation function for deleting the last entry and returning its value
// extends fun deleteLast(self: Array): Address {
//     require(self.length > 0, "No items in the array!");
//     // Note that we use the !! operator, as we know for sure the value would be there
//     let lastItem = self.m.get(self.length - 1)!!;
//     self.m.set(self.length - 1, null); // delete the entry
//     self.length -= 1; // decrease the length field
//     return lastItem;
// }
// // Extension function for deleting all items in the Array
// extends mutates fun deleteAll(self: Array) {
//     self.m = emptyMap();
//     self.length = 0;
// }
// // Global static function for creating an empty Array
// fun emptyArray(): Array {
//     return Array { m: emptyMap(), length: 0 }; // length defaults to 0
// }
// // Contract emulating an Array using the map
// contract MapAsArray {
//     // Persistent state variables
//     array: Array;
//     // Constructor (initialization) function of the contract
//     init() {
//         self.array = emptyArray();
//     }
//     // Internal message receiver, which responds to a `null` message body
//     // If used for deployment, forwards the remaining value back to the sender
//     receive() { cashback(sender()) }
//     // Internal message receiver, which responds to a String message "append"
//     receive("append") {
//         // Add a new item
//         self.array.append(42);
//     }
//     // Internal message receiver, which responds to a String message "delete_5th"
//     receive("delete_5th") {
//         // Remove the 5th item if it exists and reply back with its value, or raise an error
//         self.reply(self.array.deleteIdx(4).toCoinsString().asComment()); // index offset 0 + 4 gives the 5th item
//     }
//     // Internal message receiver, which responds to a String message "del_last"
//     receive("del_last") {
//         // Remove the last item and reply back with its value, or raise an error
//         self.reply(self.array.deleteLast().toCoinsString().asComment());
//     }
//     // Internal message receiver, which responds to a String message "get_last"
//     receive("get_last") {
//         // Reply back with the latest item in the array if it exists, or raise an error
//         self.reply(self.array.getLast().toCoinsString().asComment());
//     }
//     // Internal message receiver, which responds to a String message "delete_all"
//     receive("delete_all") {
//         self.array.deleteAll();
//     }
//}

// self.forward();// low level for below funs
// self.reply();// bounce
// self.notify();// no bounce
//cashback(sender());// only alone works in receiver

// let publicKey = getPublicKey(msg.privateKey);
//         require(checkDataSignature(msg.data, msg.signature, publicKey), "Invalid signature!");
// Don’t throw 0 or 1 directly.

/*
- Consider using the commit-and-disclose scheme:

Participants generate random numbers off-chain and send their hashes to the contract.
Once all hashes are received, participants disclose their original numbers.
Combine the disclosed numbers (e.g., summing them) to produce a secure random value.

to: sender();// front run possible?
queryid: for replay
to: for front run protection

let body = inMsg();

replace all text receivers with binary ones and create relevant message structs even if they’ll be empty and only their opcodes will be used.

Use arithmetic and standard library functions over branching or complex control flow whenever possible.

emptyBasechainAddress()
newBasechainAddress()
contractBasechainAddress()

// gas optimisation tips

Prefer contract parameters to init() and contract fields
Do not deploy contracts with Deployable trait
Use BasechainAddress struct and related functions for runtime manipulations on addresses in the base workchain
Pay attention to “500+ gas” badge
Inline functions that are rarely called
Prefer manipulating strings off-chain
Prefer arithmetic to branching operators
Prefer specialized math functions to general ones
Asm functions
Disable run-time safety checks for well-tested contracts
Receiving messages
Prefer binary receivers to text receivers
Prefer inMsg() to Message.toSlice()
Avoid internal contract functions
Use sender() over context().sender
Use throwUnless() over require()
Use SignedBundle to verify signatures in external message receivers
Sending messages
Prefer message() and cashback() to self.forward(), self.reply(), and self.notify()
Use deploy() function for on-chain deployments
Use message() function for non-deployment messages
Applied examples of best gas practices

// security tips
Sending sensitive data on-chain
Misuse of signed integers
Invalid throw values
Insecure random numbers
Optimized message handling
Gas limitation
Identity validation
Replay protection
Preventing front-running with signature verification
Race condition of messages
Handle/Send bounced messages
Transaction and phases
Return gas excesses carefully
Pulling data from another contract
Pay attention to safety option set of tact.config.json

FUTURE ROADMAP============================================================================
virtual addresses, one time use and throw address generation
account age , older can deactivate
minter stores coordinates received via notifs


*/
