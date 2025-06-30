# The ACK cost problem #

## CCTCP Protocol ##

![ACK cost](/img/ACK.jpeg)

This is an *open, permisionless and decentralized* protocol, but to be fair, who makes an operation, should pay for all costs that operation originate. That's why user not only approve CCIP fees, but also what we call ACK fee. Ironically fees are taken in origin chain to pay for what will happen in destination chain and AKC fees are paid in destination chain to pay for what will happen after ACK is received back in origin chain.

Fees for sending messages are estimated by calling IRouter function *getFeee*. But there has been no way to precisely estimate ACK fees in origin chain, even if that fees are supposed to pay for operations happening in origin chain itself. 

LINK token is not CCIP transferable in testnet environment, to make it more difficult. Some approaches have been tryed. 

### TCP_Host as a LINK pool ###

CCTCP_Host contracts hold some INK to pay for ACKs. They are charged exactly what the ACK will cost, because from the viewpoint of de acknowledging chain, it's just sending a message, and getFees can be called. 

### HyperLinkToken ###

HyperLinkToken is a hyperToken backed by LINK. It's crosschain transferable. The hyperToken protocol stack allows it as payment for ACKs. There is a catch. HyperLinkTokens are supposed to be wrapped and unwrapped from HyperLinkPools, and minted and burned by MinimalBnMPool.