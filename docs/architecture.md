# HyperToken protocols architecture #

Architecture is based on the Internet protocol stack TCP/IP. that's why protocol over CCIP is called CCTCP responding to *Cross Chain Transfer Control Protocol*, and the smart contract on which it's implemented is called CCTCP_Host. 

Protocol which bridges between application logic and communication logic is called CCHTTP for *Cross Chain Hyper Token Transfer Protocol*, and as hyperToken suite is not client/server but mostly Peer to Peer, contract is called CCHTTP_Peer.

HyperTokenManager handles all interactions with users, while HyperTokenFactory coordinate manager calls with CCHTTP protocol messaging (send, receive, confirm, receive confirmation) and calls to ProtocolFactory to create HyperToken contracts when needed.

![Protocol Architecture](/img/Architecture.jpeg)

## CCTCP Protocol. ##

CCTCP protocol is absolutely ignorant about CCHTTP messages, it just handles all logic for interacting with Chainlink CCIP Protocol. Messages must provide a token address which will be used to pay fees for sending message, also an amount of fees user is willing to pay. User must also provide an address of a token to pay for ACK sending cost. Ironically, fees are paid for what will happen on destination chain. ACK fees are paid for what will happen after ACK is received back in origin chain. Anyway, estimating the ACK cost has been a nightmare. Feel free to read about it [here](ackconst.md).

## FeesManager ##

FeesManager is an abstract contract which is inherited by all contracts on the stack which handle CCIP operations, starting from HyperTokenManager, also HyperTokenFactory, CCHTTP_Peer and CCTCVP_Host. Mainly it is here to avoid (more) duplicated code.

## HyperABICoder ## 

HyperABICoder has been implemented as a lybrary. It encodes all protocols data packed, and uses yul assembly to decode them. There are strings which are encoded with their length and decoded in an asembly loop. There are also ambiguous fields *bytes data*, luckily always at the end of the struct, so legnth can be calculated.

## CCHTTP_Peer ##

Serves as a bridge between CCIP handling logic in CCTCP_Host and business logic handled in HyperTokenFactory.

## HyperTokenFactory ##

Is the controller of hyperTokens logic. Receives orders from HyperTokenManager or from CCHTTP_Peer coming from peer chains. It commands mint and burns for wrap and unwrap backing values. It calls ProtocolFactory to deploy hyperTokens and calls hyperTokenManager to update the state and the information of hyperTokens.

## HyperTokenManager ##

Handles external operations. It's the contract which interact with both protocol deployer and common hyperToken deployer. It keeps all information about hypertokens and their deployment status. It also tracks cross chain supply for hyperTokens originated from its chain. In hyperToken code, we call it motherchain.

## HyperToken ##

HyperToken is an abstract contact containing all common operations of the different hyperTokens. Notice that some hyperTokens allow to wrap and unwrap under certian conditions, and as CrossChain Tokens CCT standard compliants, they also must implement burn and mint function with well defined roles for access control. 



