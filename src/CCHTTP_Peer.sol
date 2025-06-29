// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ICCTCP_Consumer} from "./interfaces/ICCTCP_Consumer.sol";
import {ICCTCP_Host} from "./interfaces/ICCTCP_Host.sol";

import {ICCHTTP_Consumer} from "./interfaces/ICCHTTP_Consumer.sol";
import {ICCHTTP_Peer} from "./interfaces/ICCHTTP_Peer.sol";

import {FeesManager} from "./FeesManager.sol";

import {HyperABICoder} from "./libraries/HyperABICoder.sol";
import {CCHTTP_Types} from "./CCHTTP_Types.sol";


contract CCHTTP_Peer is CCHTTP_Types, FeesManager, ICCTCP_Consumer, ICCHTTP_Peer {

    event NonRevertingError(string message, bytes data);
    // CCHTTP_Peer contract that implements ICCTCP_Consumer interface
    // This contract will handle the logic for receiving messages and notifying delivery

    // Define state variables as needed
    uint64 public chainId;
    address public router;
    address public CCTCP_host;
    address public hyperTokenFactory;
    // Constructor to initialize the contract
    constructor() {
        // Initialize state variables if needed
    }

    function init(
        uint64 _chainId,
        address _router,
        address _linkToken,
        address _wrappedNative,
        address _host,
        address _hyperTokenFactory
    ) external {
        // Initialize the contract with the provided parameters
        chainId = _chainId;
        router = _router;
        linkToken = _linkToken;
        wrappedNative = payable(_wrappedNative);
        CCTCP_host = _host;
        hyperTokenFactory = _hyperTokenFactory;
    }

    //ICCTCP_Consumer implementation
    //To be called from CCTCP Host
    function receiveMessage(
        uint64 _origChainId,
        bytes memory origData
    ) external override returns (bool) {
        CCHTTP_Message memory message = HyperABICoder.decodeCCHTTP_Message(origData);
        if (message.operation == CCHTTP_Operation.DEPLOY_AND_MINT) {
            // Handle deploy and mint operation
            DeployAndMintIndication(_origChainId, message.data);
            
        } else if (message.operation == CCHTTP_Operation.UPDATE_SUPPLY) {
            // Handle update supply operation
            UpdateSupplyIndication(_origChainId, message.data);
            
        } else {
            revert("Unsupported operation");
        }
        return true;
    } 

    function notifyDeliver(
        uint64 _origChainId,
        bytes memory origData
    ) external override returns (bool) {
        CCHTTP_Message memory message = HyperABICoder.decodeCCHTTP_Message(origData);
        if (message.operation == CCHTTP_Operation.DEPLOY_AND_MINT) {
            // Handle deploy and mint operation
            deploy_and_mint_mssg memory params = HyperABICoder.decodeDeployAndMintMessage(message.data);
            DeployAndMintConfirmation(_origChainId, params);
        } else if (message.operation == CCHTTP_Operation.UPDATE_SUPPLY) {
            // Handle update supply operation
            //update_supply_mssg memory params = HyperABICoder.decodeUpdateSupplyMessage(message.data);
            //UpdateSupplyConfirmation(_origChainId, params);
            emit NonRevertingError("UpdateSupplyConfirmation not implemented", origData);
            return false; // Indicate that the operation was not handled
        } else {
            revert("Unsupported operation");
        }
        return true;
    }


    function deployAndMintRequest(
        deployAndMintParams memory params
    ) external returns (bool) {
        deploy_and_mint_mssg memory mssg;
        
        mssg.name_length = params.name_length;
        mssg.name = params.name;
        mssg.symbol_length = params.symbol_length;
        mssg.symbol = params.symbol;
        mssg.decimals = params.decimals;
        mssg.deployer = params.deployer;
        mssg.chainSupply = params.chainSupply;
        mssg.expectedTokenAddress = params.expectedTokenAddress;
        mssg.tokenType = params.tokenType;
        mssg.backingToken = params.backingToken;
        mssg.tokenId = params.tokenId;

        CCHTTP_Message memory message;
        message.operation = CCHTTP_Operation.DEPLOY_AND_MINT;
        message.data = HyperABICoder.encodeDeployAndMintMessage(mssg);

        // Call the FeesManager to handle cash in and approve fees
        FeesManager.cashInAndApproveFeesAndACK(
            params.feeToken,
            params.feesAmount,
            params.linkToken,
            params.linkAmount,
            CCTCP_host
        );

        ICCTCP_Host(CCTCP_host).sendMessage(
            ICCTCP_Host.sendMessageParams({
                destChain: params.chainId,
                origWallet: params.deployer,
                linkForAck: params.linkAmount,
                linkToken: params.linkToken,
                data: HyperABICoder.encodeCCHTTP_Message(message),
                feeToken: params.feeToken,
                feeAmount: params.feesAmount
            })
        );
        return true;
    }

    function getFeesForDeployAndMint(
        deployAndMintParams memory params
    ) external view returns (uint256 feeAmount, uint256 linkForAck) {
        ICCTCP_Host.getFeesForMessageParams memory feesParams;
        feesParams.destChain = params.chainId;
        feesParams.linkToken = params.linkToken;
        feesParams.data = HyperABICoder.encodeDeployAndMintMessage(
            deploy_and_mint_mssg({
                name_length: params.name_length,
                name: params.name,
                symbol_length: params.symbol_length,
                symbol: params.symbol,
                decimals: params.decimals,
                deployer: params.deployer,
                chainSupply: params.chainSupply,
                expectedTokenAddress: params.expectedTokenAddress,
                tokenType: params.tokenType,
                backingToken: params.backingToken,
                tokenId: params.tokenId
            })
        );
        feesParams.feeToken = params.feeToken;

        (feeAmount, linkForAck) = ICCTCP_Host(CCTCP_host).getFeesForMessage(feesParams);
    }

    function updateSupplyRequest(
        updateSupplyParams memory params
    ) external returns (bool) {
        update_supply_mssg memory mssg;
        mssg.amount = params.amount;
        mssg.hyperToken = params.hyperToken;
        mssg.destination = params.destination;
        
        // Assuming hyperToken is passed in params

        CCHTTP_Message memory message;
        message.operation = CCHTTP_Operation.UPDATE_SUPPLY;
        message.data = HyperABICoder.encodeUpdateSupplyMessage(mssg);

        cashInAndApproveFeesAndACK(
            params.feeToken,
            params.feesAmount,
            address(0), // Assuming no link token for update supply
            0, // Assuming no link amount for update supply
            CCTCP_host
        );

        ICCTCP_Host(CCTCP_host).sendMessage(
            ICCTCP_Host.sendMessageParams({
                destChain: params.chainId,
                origWallet: tx.origin,
                linkForAck: 0, // Assuming no link for ack for update supply
                linkToken: address(0), // Assuming no link token for update supply
                data: HyperABICoder.encodeCCHTTP_Message(message),
                feeToken: params.feeToken,
                feeAmount: params.feesAmount
            })
        );
        return true;
    }


    function getFeesForUpdateSupply(
        updateSupplyParams memory params
    ) external view returns (uint256 feeAmount) {
        ICCTCP_Host.getFeesForMessageParams memory feesParams;
        feesParams.destChain = params.chainId;
        feesParams.data = HyperABICoder.encodeUpdateSupplyMessage(
            update_supply_mssg({
                amount: params.amount,
                hyperToken: params.hyperToken,
                destination: params.destination
            })
        );
        feesParams.feeToken = params.feeToken;
        feesParams.linkToken = address(0); // Assuming no link token for update supply

        (feeAmount,) = ICCTCP_Host(CCTCP_host).getFeesForMessage(feesParams);
    }


    function DeployAndMintIndication(
        uint64 origChainId,
        bytes memory data
    ) internal returns (bool) {
        // Implement the logic to handle the received deployment and minting request
        // This function involves calling the HyperTokenFactory to deploy a child HyperToken
        deploy_and_mint_mssg memory params = HyperABICoder.decodeDeployAndMintMessage(data);

        ICCHTTP_Consumer(hyperTokenFactory).DeployAndMintReceived(
            origChainId,
            params
        );

        return true; // Return true if the operation was successful
    }
    

    function UpdateSupplyIndication(
        uint64 origChainId,
        bytes memory data
    ) internal returns (bool) {
        // Implement the logic to handle the received update supply request
        // This function involves updating the supply of a HyperToken
        update_supply_mssg memory params = HyperABICoder.decodeUpdateSupplyMessage(data);
        ICCHTTP_Consumer(hyperTokenFactory).UpdateTotalSupplyReceived(
            origChainId,
            params
        );
        return true; // Return true if the operation was successful
    }


    function DeployAndMintConfirmation(
        uint64 origChainId,
        deploy_and_mint_mssg memory params
    ) internal returns (bool){
        // Implement the logic to handle the confirmation of a deployment and minting request
        // This function involves confirming the deployment of a child HyperToken
        ICCHTTP_Consumer(hyperTokenFactory).DeployAndMintConfirmed(
            origChainId,
            params
        );
        return true; // Return true if the operation was successful
    }

/*
    function UpdateSupplyConfirmation(
        uint64 origChainId,
        update_supply_mssg memory params
    ) internal returns (bool) {
        // Implement the logic to handle the confirmation of an update supply request
        // This function involves confirming the update of a HyperToken's supply
        ICCHTTP_Consumer(hyperTokenFactory).UpdateTotalSupplyConfirmed(
            origChainId,
            params
        );

        return true; // Return true if the operation was successful
    }
*/
}