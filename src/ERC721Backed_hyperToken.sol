// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC721 } from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import { IERC721Metadata } from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { HyperToken } from "./hyperToken.sol";
import { IHyperTokenFactory } from "./interfaces/IHyperTokenFactory.sol";
import { FeesManager } from "./FeesManager.sol";


contract ERC721Backed_hyperToken is HyperToken, FeesManager {
    using SafeERC20 for IERC20;

    // The backing NFT for this hyperToken
    //  caracterized by (backingTokenAddress, backingNFT_Id)
    address public backingToken;
    uint256 public backingNFT_Id;


    constructor(
        string memory name_, 
        string memory symbol_,
        uint8 decimals_
    ) HyperToken(name_, symbol_, decimals_) 
    {
        
    }

    function init(
        uint64 _motherChainId,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address _backingToken,
        uint256 _backingNFT_Id,
        address _pool,
        address _wrappedNative,
        address _linkToken,
        address _hyperLinkToken        
    ) public  {
        
        super.init(
            _motherChainId,
            name,
            symbol,
            decimals
        );
        
        wrappedNative = payable(_wrappedNative);
        linkToken = _linkToken;
        hyperLinkToken = _hyperLinkToken;

        // Set the backing NFT
        backingToken = _backingToken;
        backingNFT_Id = _backingNFT_Id;        
        setPool(_pool);
    }

    function getBackingURI() external view returns (string memory) {
        // Return the URI of the backing NFT
        return IERC721Metadata(address(backingToken)).tokenURI(backingNFT_Id);
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        // This function is called when the contract receives an ERC721 token
        // We can use this to set the backing NFT if it wasn't set in the constructor
        
        require(
            msg.sender == backingToken, 
            "tk"
        );
        require(tokenId == backingNFT_Id,
                "ID");
        
        return IERC721Receiver.onERC721Received.selector;
    }
}