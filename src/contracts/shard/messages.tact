//  SPDX-License-Identifier: MIT
//  Copyright © 2025 TON Studio

struct Insurance {
    emi: Int as coins;
    startStop: Int as uint42; // TODO: enough for time
}
// Optimized action messages with op codes
message(0x7362d09c) JettonNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    forwardPayload: Slice as remaining;
}

message(0x595f07bc) JettonBurn {
    queryId: Int as uint64;
    amount: Int as coins;
    responseDestination: Address?;
    customPayload: Cell?;
}

message(0x7bdd97de) JettonBurnNotification {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
}

message(0xd53276db) JettonExcesses {
    queryId: Int as uint64;
}

message(0x2c76b973) ProvideWalletAddress {
    queryId: Int as uint64;
    ownerAddress: Address;
    includeAddress: Bool;
}

message(0xd1735400) TakeWalletAddress {
    queryId: Int as uint64;
    walletAddress: Address;
    ownerAddress: Cell?; //It is Maybe ^Address, just encoded it like this
}

message(0x642b7d07) Mint {
    queryId: Int as uint64;
    receiver: Address;
    mintMessage: JettonTransferInternal;
}

message(22) CloseMinting {}

message(3) ChangeOwner {
    queryId: Int as uint64;
    newOwner: Address;
}

// provide_wallet_balance#7ac8d559 receiver:MsgAddress include_verify_info:Bool = InternalMsgBody
message(0x7ac8d559) ProvideWalletBalance {
    receiver: Address;
    includeVerifyInfo: Bool;
}

struct VerifyInfo {
    owner: Address;
    minter: Address;
    code: Cell;
}

// verify_info$_ owner:MsgAddress minter:MsgAddress code:^Cell = VerifyInfo
// take_wallet_balance#ca77fdc2 balance:Coins verify_info:(Maybe VerifyInfo) = InternalMsgBody
message(0xca77fdc2) TakeWalletBalance {
    balance: Int as coins;
    verifyInfo: VerifyInfo?;
}

// claim_ton#0393b1ce receiver:MsgAddress = InternalMsgBody
message(0x0393b1ce) ClaimTON {
    receiver: Address;
}

message(1) InviteInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    invitor: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(2) Follow {
    target: Address;
    amount: Int as coins;
}

message(3) FollowInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x15) Unfollow {
    target: Address;
    amount: Int as uint16;
}

message(5) UnfollowInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(6) FriendRequestInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(7) ConfirmRequestInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(8) ReportInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    reason: Bool;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(9) DisputeInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(10) ResolutionInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x11) Report {
    target: Address;
    reason: Bool; //true for closure, false for fraud/duplicateAccount
}

message(0x12) Dispute {
    target: Address;
}

message(0x13) ProcessComplaint {
    target: Address;
}

message(0x14) AdminAction {
    action: Int as uint8;
    value: Int as coins;
}

// Event with optimized data packing
// message(0x16) NetworkEvent {
//     eventType: Int as uint8;
//     from: Address;
//     to: Address;
//     amount: Int as coins;
// }

struct FriendsAndFollowings {
    friends: Cell?; //map<Address, Int as uint12>;
    followings: Cell?; //map<Address, Int as uint12>;
    //TODO: remove maybe
    followers: Cell?; //map<Address, Int as uint12>;
    invited: Cell?; //map<Address, Int as uint12>;
    pendingRequests: Cell?; //map<Address, Int as uint12>;
    debts: Cell?; //map<Address, Int as uint20>;
    reports: Cell?; //map<Address, Bool>;
}

struct OtherStateConsts {
    reportReason: Bool;
    reporterCount: Int as uint10;
    disputerCount: Int as uint10;
    reportResolutionTime: Int as uint32;
    connections: Int as uint8;
    terminated: Bool;
    mbrpAmount: Int as coins;
    closureWait: Int as uint32;
    frozen: Bool;
    lastMsgTo: Address;
}

struct InvitorNominee {
    invitor: Address?;
    nominee: Address;

    //minterOwner: Address;
}

//minterOwner: Address;
struct JettonData {
    totalSupply: Int as coins;
    mintable: Bool;
    owner: Address;
    content: Cell;
    jettonWalletCode: Cell;
}

struct JettonWalletData {
    balance: Int as coins; //TODO: map of different jettons
    owner: Address;
    minter: Address; // TODO: array of different minters(maybe wallet gen isInTrouble coz of this)
    code: Cell;
}

struct MaybeAddress {
    address: Address?;
}

message(4) JettonUpdateContent {
    queryId: Int as uint64;
    content: Cell? = null;
    jettonWalletCode: Cell? = null;
}

message(0xf8a7ea5) JettonTransfer {
    queryId: Int as uint64;
    amount: Int as coins;
    destination: Address;
    responseDestination: Address?;
    customPayload: Cell?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x178d4519) JettonTransferInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    version: Int as uint10;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
// TODO: sent but received : maybe sent to app and not contract

message(0x25) Mintable {
    mintable: Bool;
}
message(0x31) UnfriendInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(0x32) ReInviteInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(0x34) UnInviteInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}
message(0x33) U {
    op: Int as uint6;
    amount: Int? as coins;
    sender: Address?;
    receiver: Address?;
    forwardPayload: Slice as remaining;
}
message(0x35) AccCloseBurnInternal {
    queryId: Int as uint64;
    amount: Int as coins;
    sender: Address;
    responseDestination: Address?;
    forwardTonAmount: Int as coins;
    forwardPayload: Slice as remaining;
}

message(0x36) EnquireInvitor {
    sender: Address;
}
message(0x37) TakeInvitor {
    sender: Address;
    invitor: Address;
}

message(0x38) RequestUpgradeCode {
    version: Int as uint10;
}

message(0x39) UpgradeCode {
    sender: Address;
    /// New code of the contract.
    /// Defaults to `null`, which keeps the previous code.
    code: Cell? = null;

    /// New data of the contract.
    /// Defaults to `null`, which keeps the previous data.
    //data: Cell? = null;
    /// Delay in seconds before upgrade can be confirmed.
    /// Defaults to zero, which means the upgrade can be confirmed immediately.
    /// Unused in `Upgradable` trait.
    //timeout: Int = 0;
}

/// New data of the contract.
/// Defaults to `null`, which keeps the previous data.
//data: Cell? = null;
/// Delay in seconds before upgrade can be confirmed.
/// Defaults to zero, which means the upgrade can be confirmed immediately.
/// Unused in `Upgradable` trait.
//timeout: Int = 0;
message(0x40) AccountGenerated {
    deployer: Address;
    newAccount: Address;
}

message(0x41) ApplyGrant {
    sender: Address;
    amount: Int as coins;
}
message(0x42) VoteProposal {
    sender: Address;
    proposer: Address;
    turnover: Int as coins;
}
message(0x43) CitizenAdded {
    sender: Address;
    newAccount: Address;
}
