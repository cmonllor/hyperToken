# HyperToken protocols architecture #

Architecture is based on the Internet protocol stack TCP/IP. that's why protocol over CCIP is called CCTCP responding to *Cross Chain Transfer Control Protocol*, and the smart contract on which it's implemented is called CCTCP_Host. 

Protocol which bridges between application logic and communication logic is called CCHTTP for *Cross Chain Hyper Token Transfer Protocol*, and as hyperToken suite is not client/server but mostly Peer to Peer, contract is called CCHTTP_Peer.

HyperTokenManager handles all interactions with users, while HyperTokenFactory coordinate manager calls with CCHTTP protocol messaging (send, receive, confirm, receive confirmation) and calls to ProtocolFactory to create HyperToken contracts when needed.

![Protocol Architecture](/img/Architecture.jpeg)

## CCTCP Protocol. ##

CCTCP protocol is absolutely ignorant about CCHTTP messages, it just handles all logic for interacting with Chainlink CCIP Protocol. Messages must provide a token address which will be used to pay fees for sending message, also an amount of fees user is willing to pay. 