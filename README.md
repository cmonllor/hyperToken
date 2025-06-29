# HyperToken #

## Description ##

HyperToken is a protocol for EVM-based blockchains that uses [Chainlink CCIP](https://docs.chain.link/ccip).

With  this protocols any user can wrap on-chain assets into hyperTokens. HyperTokens are Crss-Chain tokens, adjusted to the [**CCT** standard](https://docs.chain.link/ccip/concepts/cross-chain-token), so crosschain transfers can be made using the [TokenManager](https://test.tokenmanager.chain.link/) frome Chainlink Labs.

On each chain, there are two hyperToken deployed by developers team: one wraps LINK token and the other wrpas the Native token of the host blockchain.

Users can also create their own hyperTokens wrapping an ERC721 NFT, allowing fraccionalized ownership represented by an ERC20 Cross Chain Token.

Users can also wrap quantities of an ERC20 token in a 1:1 rate to its respective ERC20-Backed hyperToken. If an ERC20Backed-HyperToken does not exist for an ERC20, users can deploy a ERC20Backed hyperToken in an *open, permissionless and decentralized* way. 

## Disclaimer ##

This project is for entertainment, education and personal expertise showdown. This is not even a MVP, and many features lack proper testing. Critical security checks may have been missed. **Absolutely never use this code in production.**

