# HyperToken #

## Description ##

HyperToken is a protocol for EVM-based blockchains that uses [Chainlink CCIP](https://docs.chain.link/ccip).

With  this protocols any user can wrap on-chain assets into hyperTokens. HyperTokens are Crss-Chain tokens, adjusted to the [**CCT** standard](https://docs.chain.link/ccip/concepts/cross-chain-token), so crosschain transfers can be made using the [TokenManager](https://test.tokenmanager.chain.link/) frome Chainlink Labs.

On each chain, there are two hyperToken deployed by developers team: one wraps LINK token and the other wrpas the Native token of the host blockchain.

Users can also create their own hyperTokens wrapping an ERC721 NFT, allowing fraccionalized ownership represented by an ERC20 Cross Chain Token.

Users can also wrap quantities of an ERC20 token in a 1:1 rate to its respective ERC20-Backed hyperToken. If an ERC20Backed-HyperToken does not exist for an ERC20, users can deploy a ERC20Backed hyperToken on demand, in an *open, permissionless and decentralized* way, as we love it to be in blockchain communities.

## Disclaimer ##

This project is for entertainment, education and personal expertise showdown. This is not even a MVP, and many features lack proper testing. Critical safety checks may have been missed. **Absolutely never use this code in production.**

## Dependencies ##

This project uses mainly the [foundry](https://getfoundry.sh) suite. 

Tests use the 

## Testnets ##

In the begginning, this project was intended to be deployed in four chains:
- Ethereum Sepolia
- Arbitrum Sepolia
- Optimism Sepolia
- Avalanche Fuji

At submission date, some problems found in Avalanche Fuji deployment process couldn't be solved, so final demo is only deployed in:
- Ethereum Sepolia
- Arbitrum Sepolia
- Optimism Sepolia

*A pity, now we cannot apply for Avalanche track in Chromion Hackathon*


## Note for Chromion judges ##

HyperToken was an idea originally for Block Magic hackathon in May'24. At the end of Block Magic hackathon I realized it wasn't possible to get even a half-working demo version and had to resign... project was not submitted. 


### What I did for Block Magic hackathon. ###

- **CCTCP_Host** This contract is the basement of the stack and was thought in Block Magic. This year submission contains an iteration from last year version, with litle updates, one of the most significative is all ACK cost estimation relative code. Last year version didn't estimate it, but used big enough values to get the job done.
- **CCHTTP_Peer** Last year there wasn't CCT standard, so this contract included logic for Burn'n'Mint mechanism Crss Chain transfers. This submission contains a flattened version, with logic for deployments, and for wrap/unwrap messages (updateSupply)
- **HyperABICoder** This full of yum assembly code contract, last year had more structures to encode/decode because CCHTTP_Peer was much heavier than this year. Anyway, at the doors of submission date in Block Magic hackathon, last-minute changes in project structure broke it.
- **HyperTokenFactory** Blame EIP170 and 24k contract size limit. Last year, hyperTokenFactory was a monster containing logic from both *HyperTokenManager* and *HyperTokenFactory* and even included the code form *ERC20Backed_hyperToken* and *nativeBackedHyperToken*. With EIP170 in action, one of the main tasks this year has been flattening it, deriving logic to other contacts, using interfaces, ERC196 proxies ... 
-**hyperToken** Last year were developed versions of ERC20 and native backed hyperTokens.
-**ProtocolFactory** Last year project had indeed a protocolFactory which deployed just main protocols. 


### What has been done for Chromion hackathon ###

-**CCTCP_Host: ACK costs** Main novelty in CCTCP_Host is all logic trying to estimate ACK costs. Please refer the docs for more info.Even if a part of it has been discarded, it has been kept on published code commented as reference.
-**CCTCP_Host: predicable address** Last year I didn't dare to modify dependencies code, so as it inherited from CCIP_Receiver which has chain dependant arguments in the constructor, its address was different on each chain. This year I modified dependencies and put them in [mods](mods/) directory, removing chain dependant arguments from constructor, to an init function.
-**ProtocolFactory** ProtocolFactory this year handles main protocols deployment and most hyperTokens deployments. Usage of ERC195 Proxies is done also here.
-**HyperTokenFactory: size** HyperTokenFactory from last year has ben splitted. *hyperTokenManager* handles protocol deployer (special user: developer team) and hyperToken deployer (any user, it's open) interactions.
-**HyperTokenFactory: token registration** This year hyperTokenFactory does the registration process of a Chainlink [CCT](https://docs.chain.link/ccip/concepts/cross-chain-token) process. It's authomatic and without more need of user interaction than what is needed to deploy an  hyperToken.
-**HyperTokenManager:** This contract contains logic originally from *HyperTokenFactory*, but hard work has been needed to adapt this logic to be in another contract, trying to preserve protocol safety.
-**hyperTokens:** Even if ERC20Backed_Hyperrtoken and nativeBacked_hyperToken were started last year, they have been used as reference and its code has been completely rewritten. ERC721Backed_HyperToken is new. Abstract contract hyperToken has been substantially modified to adapt to logic split between *hyperTokenFactory* and *hyperTokenManager*.
