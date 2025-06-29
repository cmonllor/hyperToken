//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


abstract contract CCHTTP_Types{
 
    enum CCHTTP_Operation{
        UPDATE_SUPPLY,
        DEPLOY_AND_MINT 
    }

    enum CCHTTP_Message_Status{
        UNTRACKED,
        PENDING,
        SENT,
        RECEIVED,
        CONFIRMED,
        FAILED
    }

    enum HyperToken_Types{
        HyperNative,
        HyperERC20,
        HyperERC721,
        HyperUnbacked
    }


    struct deployAndMintParams{
        uint64 chainId;
        address origin;
        address destination;
        address linkToken;
        uint256 linkAmount;
        address feeToken;
        uint256 feesAmount;
        uint8 name_length;
        string name;
        uint8 symbol_length;
        string symbol;
        uint8 decimals;
        address deployer;
        uint256 chainSupply;
        address expectedTokenAddress;
        HyperToken_Types tokenType;
        address backingToken;//wrapped for native
        uint256 tokenId; //for erc721
    }

    struct deploy_and_mint_mssg{
        uint8 name_length;
        string name;
        uint8 symbol_length;
        string symbol;
        uint8 decimals;
        address deployer;
        uint256 chainSupply;
        address expectedTokenAddress;
        HyperToken_Types tokenType;
        address backingToken;//wrapped for native
        uint256 tokenId; //for erc721
    }

    struct updateSupplyParams{
        uint64 chainId;
        address feeToken;
        uint256 feesAmount;
        int256 amount;
        address hyperToken;
        address destination;
    }

    struct update_supply_mssg{
        address hyperToken;
        int256 amount;
        address destination;
    }


    struct CCHTTP_Message{
        CCHTTP_Operation operation;
        bytes data;
    }

    struct CCHTTP_Message_Info{
        uint64 origChainId;
        address origHost;
        uint64 destChainId;
        address destHost;
        address linkToken;
        uint256 linkAmount;
        address feeToken;
        uint256 feesAmount;
        CCHTTP_Message_Status status;
        CCHTTP_Message message;
    }

}
